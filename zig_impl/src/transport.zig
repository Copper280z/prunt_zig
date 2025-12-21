const std = @import("std");
const types = @import("types.zig");
const libusb = @import("libusb");

const Cmd = types.Cmd;

pub const Transport = struct {
    ptr: *anyopaque,
    sendFn: *const fn (ptr: *anyopaque, msg: Cmd) anyerror!void,
    recvFn: *const fn (ptr: *anyopaque, msg: anytype) anyerror!void,
    pub fn send(self: Transport, msg: anytype) !void {
        self.sendFn(self.ptr, msg);
    }
    pub fn recv(self: Transport, msg: anytype) !void {
        self.recvFn(self.ptr, msg);
    }
};

pub const USBError = error{
    InitializationError,
    OutOfMemory,
    Error,
};

pub const USBTransport = struct {
    ctx: ?*libusb.libusb_context = undefined,
    dev: ?*libusb.libusb_device_handle = undefined,
    vendor_if_num: u8 = 2,
    vendor_ep_out: u8 = 0x6,
    vendor_ep_in: u8 = 0x86,

    pub fn init(pid: u16, vid: u16) !USBTransport {
        const iface_number: u8 = 8;
        std.log.info("Initializiing USB Transport", .{});
        var ctx: ?*libusb.libusb_context = undefined;
        const r = libusb.libusb_init(&ctx);
        errdefer libusb.libusb_exit(ctx);
        if (r < 0) {
            std.log.err("Initialization error {}\n", .{r});
            return USBError.InitializationError;
        }

        var devs: [*c]*libusb.libusb_device = undefined;
        defer libusb.libusb_free_device_list(@ptrCast(devs), 1);
        const dev_count = libusb.libusb_get_device_list(ctx, &devs);
        if (dev_count < 0) {
            std.log.err("Error in get device list\n", .{});
            return USBError.Error;
        }

        std.log.info("{} Devices found", .{dev_count});
        var dev: ?*libusb.struct_libusb_device = undefined;
        var found_dev: bool = false;
        for (0..@intCast(dev_count)) |i| {
            var desc: libusb.libusb_device_descriptor = undefined;
            const tmp_dev: *libusb.struct_libusb_device = devs[i];
            const err = libusb.libusb_get_device_descriptor(tmp_dev, &desc);
            if (err == 0) {
                std.log.info("Device {}: Vendor=0x{x}, Product=0x{x}", .{ i, desc.idVendor, desc.idProduct });
                if (desc.idVendor == vid and desc.idProduct == pid) {
                    dev = tmp_dev;
                    std.log.info("Using this device\n", .{});
                    found_dev = true;
                    break;
                }
            }
        }
        if (found_dev) {
            std.log.info("Using dev ptr: {}\n", .{@intFromPtr(dev)});
        } else {
            std.log.err("No USB Device Found\n", .{});
            return USBError.Error;
        }

        var handle: ?*libusb.libusb_device_handle = undefined;
        var err = libusb.libusb_open(dev, &handle);
        if (err != 0) {
            std.log.err("Error opening device: {}\n", .{err});
            return USBError.Error;
        }
        _ = libusb.libusb_set_auto_detach_kernel_driver(handle, 1);

        err = libusb.libusb_claim_interface(handle, iface_number);
        return .{ .dev = handle, .ctx = ctx };
    }
    pub fn send(self: *@This(), msg: Cmd) !void {
        switch (msg) {
            .MoveCmd => |c| try self.send_move(c),
        }
    }
    pub fn transport(self: *@This()) Transport {
        return .{ .ptr = self };
    }
    fn find_endpoints(self: *@This()) void {
        _ = self;
        //
    }
    pub fn control_xfer(self: *@This(), wValue: u16) void {
        var buf: [64]u8 = undefined;
        buf[0] = 42;
        buf[1] = 43;
        buf[2] = 44;
        buf[3] = 45;
        const dir: u8 = libusb.LIBUSB_ENDPOINT_OUT; // Out: host-to-device.
        const recipient: u8 = libusb.LIBUSB_RECIPIENT_ENDPOINT;
        const req_type: u8 = libusb.LIBUSB_REQUEST_TYPE_VENDOR;
        const val: u16 = wValue;
        const index: u16 = 0;

        const bmRequestType: u8 = recipient | req_type | dir;
        const bRequest: u8 = 42; // application specific unless req type is LIBUSB_REQUEST_TYPE_STANDARD
        const timeout = 100;
        const wLength = 4;
        const err = libusb.libusb_control_transfer(self.dev, bmRequestType, bRequest, val, index, &buf, wLength, timeout);
        if (err < libusb.LIBUSB_SUCCESS) {
            const err_string = libusb.libusb_error_name(err);
            std.log.warn("Error Sending control transfer: {}, {s}", .{ err, err_string });
        }
    }
    pub fn bulk_transfer_send(self: *@This(), data: []const u8) !usize {
        var actual_xfer_len: i32 = 0;
        const err = libusb.libusb_bulk_transfer(self.dev, self.vendor_ep_out, @ptrCast(@constCast(data.ptr)), @intCast(data.len), &actual_xfer_len, 250);
        if (err < libusb.LIBUSB_SUCCESS) {
            std.log.err("bulk transfer error: {}\n", .{err});
        }
        if (actual_xfer_len != data.len) {
            std.log.warn("short transfer: {}\n", .{@as(i32, @intCast(data.len)) - actual_xfer_len});
        }
        return @intCast(actual_xfer_len);
    }
    pub fn bulk_transfer_recv(self: *@This(), data: *[]u8) !usize {
        var actual_xfer_len: i32 = 0;
        const err = libusb.libusb_bulk_transfer(self.dev, self.vendor_ep_in, data.ptr, data.len, &actual_xfer_len, 1000);
        if (err < libusb.LIBUSB_SUCCESS) {
            std.log.err("bulk transfer error: {}\n", .{err});
        }
        return @intCast(actual_xfer_len);
    }

    fn send_move(self: *@This(), msg: types.MoveCmd) !void {
        _ = self;
        _ = msg;
    }

    pub fn deinit(self: *@This()) void {
        libusb.libusb_close(self.dev);
        libusb.libusb_exit(self.ctx);
    }
};
