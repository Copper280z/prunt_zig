const std = @import("std");
const types = @import("types.zig");
const libusb = @import("libusb");

pub const Transport = struct {
    ptr: *anyopaque,
    sendFn: *const fn (ptr: *anyopaque, msg: anytype) anyerror!void,
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

    pub fn init(pid: u16, vid: u16) !USBTransport {
        std.log.info("Initializiing USB Transport", .{});
        var ctx: ?*libusb.libusb_context = undefined;
        const r = libusb.libusb_init(&ctx);
        if (r < 0) {
            std.log.err("Initialization error {}\n", .{r});
            return USBError.InitializationError;
        }

        var devs: [*c]*libusb.libusb_device = undefined;
        const dev_count = libusb.libusb_get_device_list(ctx, &devs);
        if (dev_count < 0) {
            std.log.err("Error in get device list\n", .{});
            libusb.libusb_exit(ctx);
            return USBError.Error;
        }

        std.log.info("{} Devices found", .{dev_count});
        var dev: *libusb.struct_libusb_device = undefined;
        for (0..@intCast(dev_count)) |i| {
            var desc: libusb.libusb_device_descriptor = undefined;
            const tmp_dev: *libusb.struct_libusb_device = devs[i];
            const err = libusb.libusb_get_device_descriptor(tmp_dev, &desc);
            if (err == 0) {
                std.log.info("Device {}: Vendor=0x{x}, Product=0x{x}", .{ i, desc.idVendor, desc.idProduct });
                if (desc.idVendor == vid and desc.idProduct == pid) {
                    dev = tmp_dev;
                    break;
                }
            }
        }
        var handle: ?*libusb.libusb_device_handle = undefined;
        const err = libusb.libusb_open(dev, &handle);
        if (err != 0) {
            std.log.err("Error opening device: {}\n", .{err});
        }
        libusb.libusb_free_device_list(@ptrCast(devs), 1);
        _ = libusb.libusb_set_auto_detach_kernel_driver(handle, 1);
        return .{ .dev = handle, .ctx = ctx };
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
    pub fn deinit(self: *@This()) void {
        libusb.libusb_close(self.dev);
        libusb.libusb_exit(self.ctx);
    }
};
