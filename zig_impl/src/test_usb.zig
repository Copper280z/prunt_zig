const std = @import("std");
const usb = @import("usb.zig"); // your wrapper module
const libusb = usb.libusb;

const Allocator = std.mem.Allocator;
const default_vid: u16 = 0xcafe;
const default_pid: u16 = 0x4011;

// Helper: get VID/PID for tests from environment (hex values).
fn getTestVidPid(alloc: Allocator) !?struct { vid: u16, pid: u16 } {
    const vid_str = std.process.getEnvVarOwned(alloc, "USB_TEST_VID") catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => return .{ .vid = default_vid, .pid = default_pid },
            else => return err,
        }
    };
    defer alloc.free(vid_str);

    const pid_str = std.process.getEnvVarOwned(alloc, "USB_TEST_PID") catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => return .{ .vid = default_vid, .pid = default_pid },
            else => return err,
        }
    };
    defer alloc.free(pid_str);

    const vid = std.fmt.parseUnsigned(u16, vid_str, 16) catch return null;
    const pid = std.fmt.parseUnsigned(u16, pid_str, 16) catch return null;

    return .{ .vid = vid, .pid = pid };
}

// didn't want to make this function public in usb.zig, but it's useful for testing.
fn descriptorFromLibusb(desc: libusb.libusb_device_descriptor) usb.DeviceDescriptor {
    return .{
        .usb_bcd = desc.bcdUSB,
        .device_class = desc.bDeviceClass,
        .device_subclass = desc.bDeviceSubClass,
        .device_protocol = desc.bDeviceProtocol,
        .max_packet_size_0 = desc.bMaxPacketSize0,
        .vendor_id = desc.idVendor,
        .product_id = desc.idProduct,
        .device_bcd = desc.bcdDevice,
        .manufacturer_str_index = desc.iManufacturer,
        .product_str_index = desc.iProduct,
        .serial_number_str_index = desc.iSerialNumber,
        .num_configurations = desc.bNumConfigurations,
    };
}

pub fn descriptorFromBytes(bytes: []const u8) usb.UsbError!usb.DeviceDescriptor {
    if (bytes.len < @sizeOf(libusb.libusb_device_descriptor)) {
        return usb.UsbError.InvalidParam;
    }
    const raw_desc = libusb.libusb_device_descriptor{
        .bLength = bytes[0],
        .bDescriptorType = bytes[1],
        .bcdUSB = std.mem.readInt(u16, bytes[2..4], .little),
        .bDeviceClass = bytes[4],
        .bDeviceSubClass = bytes[5],
        .bDeviceProtocol = bytes[6],
        .bMaxPacketSize0 = bytes[7],
        .idVendor = std.mem.readInt(u16, bytes[8..10], .little),
        .idProduct = std.mem.readInt(u16, bytes[10..12], .little),
        .bcdDevice = std.mem.readInt(u16, bytes[12..14], .little),
        .iManufacturer = bytes[14],
        .iProduct = bytes[15],
        .iSerialNumber = bytes[16],
        .bNumConfigurations = bytes[17],
    };
    return descriptorFromLibusb(raw_desc);
}
pub fn descriptorEql(self: usb.DeviceDescriptor, other: usb.DeviceDescriptor) bool {
    return std.meta.eql(self, other);
}

test "libusb context init/deinit works" {
    var ctx = try usb.Context.init();
    ctx.deinit();
}

test "open device by VID/PID and read descriptor" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const maybe_ids = try getTestVidPid(alloc);
    if (maybe_ids == null) {
        std.debug.print("skipping: USB_TEST_VID / USB_TEST_PID not set\n", .{});
        return;
    }
    const ids = maybe_ids.?;

    var ctx = try usb.Context.init();
    defer ctx.deinit();

    const maybe_handle = try ctx.openDeviceByVidPid(ids.vid, ids.pid);
    if (maybe_handle == null) {
        std.debug.print(
            "skipping: device {x:0>4}:{x:0>4} not present\n",
            .{ ids.vid, ids.pid },
        );
        return;
    }
    var handle = maybe_handle.?;
    defer handle.close();

    const desc = try handle.getDeviceDescriptor();

    // Check that the descriptor matches the VID/PID we opened.
    try std.testing.expectEqual(ids.vid, desc.vendor_id);
    try std.testing.expectEqual(ids.pid, desc.product_id);

    // Smoke-check some basic info.
    const bus_addr = handle.getBusAndAddress();
    std.debug.print(
        "Opened device {x:0>4}:{x:0>4} on bus {d}, addr {d}, speed {any}\n",
        .{ desc.vendor_id, desc.product_id, bus_addr.bus, bus_addr.address, handle.getSpeed() },
    );
}

test "control transfer: GET_DESCRIPTOR (device) works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const maybe_ids = try getTestVidPid(alloc);
    if (maybe_ids == null) {
        std.debug.print("skipping: USB_TEST_VID / USB_TEST_PID not set\n", .{});
        return;
    }
    const ids = maybe_ids.?;

    var ctx = try usb.Context.init();
    defer ctx.deinit();

    const maybe_handle = try ctx.openDeviceByVidPid(ids.vid, ids.pid);
    if (maybe_handle == null) {
        std.debug.print(
            "skipping: device {x:0>4}:{x:0>4} not present\n",
            .{ ids.vid, ids.pid },
        );
        return;
    }
    var handle = maybe_handle.?;
    defer handle.close();

    // Standard GET_DESCRIPTOR(Device) request:
    // bmRequestType: device-to-host, standard, device
    // bRequest: GET_DESCRIPTOR (0x06)
    // wValue: (descriptor_type << 8) | descriptor_index
    //         descriptor_type = 1 (DEVICE), index = 0
    // wIndex: 0
    const descriptor_type_device: u8 = 1;
    const descriptor_index: u8 = 0;

    const wValue: u16 =
        (@as(u16, descriptor_type_device) << 8) |
        @as(u16, descriptor_index);

    var buf: [64]u8 = undefined; // standard device descriptor size
    const got = try handle.controlIn(
        usb.RequestType.standard,
        usb.Recipient.device,
        0x06, // GET_DESCRIPTOR
        wValue,
        0, // wIndex
        &buf,
        1000, // timeout ms
    );

    // Many devices will return exactly 18 bytes for the device descriptor.
    // Be a bit tolerant: must be at least the header size.
    try std.testing.expect(got >= 18);

    // Quick sanity: first byte is length, second is descriptor type (1)
    const length = buf[0];
    const dtype = buf[1];
    try std.testing.expectEqual(@as(u8, 18), length);
    try std.testing.expectEqual(descriptor_type_device, dtype);

    const ctrl_desc = try descriptorFromBytes(buf[0..got]);
    std.debug.print("Got device descriptor via control transfer: {d} bytes\n", .{got});

    const descriptor = try handle.getDeviceDescriptor();
    // Check that the descriptor matches the VID/PID we opened.
    try std.testing.expectEqual(ids.vid, descriptor.vendor_id);
    try std.testing.expectEqual(ids.pid, descriptor.product_id);
    try std.testing.expect(descriptorEql(descriptor, ctrl_desc));

    // Get a string descriptor and print it.
    var string_buf: [256]u8 = undefined;
    {
        const ascii_descriptor = try handle.getStringDescriptorAscii(descriptor.manufacturer_str_index, &string_buf);
        std.debug.print("Manufacturer descriptor: {s}\n", .{ascii_descriptor});
    }
    {
        const ascii_descriptor = try handle.getStringDescriptorAscii(descriptor.product_str_index, &string_buf);
        std.debug.print("Product descriptor: {s}\n", .{ascii_descriptor});
    }
}
