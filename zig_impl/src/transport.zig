const std = @import("std");
const types = @import("types.zig");
const usb = @import("usb.zig");
const nanopb = @import("nanopb");

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
    ctx: usb.Context,
    dev: usb.DeviceHandle,
    vendor_if_num: u8 = 8,
    vendor_ep_out: usb.EndpointAddress = .{ .number = 0x6, .direction = .out },
    vendor_ep_in: usb.EndpointAddress = .{ .number = 0x6, .direction = .in },

    pub fn init(pid: u16, vid: u16) !USBTransport {
        std.log.info("Initializiing USB Transport", .{});

        // usb.Context.setLogLevel(0);

        var ctx = try usb.Context.init();
        errdefer ctx.deinit();

        const maybe_handle = try ctx.openDeviceByVidPid(vid, pid);
        if (maybe_handle == null) {
            std.log.err(
                "skipping: device {x:0>4}:{x:0>4} not present\n",
                .{ vid, pid },
            );
            return USBError.InitializationError;
        }
        var handle = maybe_handle.?;
        errdefer handle.close();

        handle.setAutoDetachKernelDriver(true) catch |e| {
            if (e == usb.UsbError.NotSupported) {
                std.log.warn("Auto detach kernel driver not supported: {}", .{e});
            } else {
                std.log.err("Failed to set auto detach kernel driver: {}", .{e});
                return USBError.Error;
            }
        };

        // handle.claimInterface(self.vendor_if_num) catch |e| {
        //     std.log.err("Failed to claim interface: {}\n", .{e});
        //     return USBError.Error;
        // };
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
        const wIndex: u16 = 0;
        const bRequest: u8 = 42; // application specific unless req type is LIBUSB_REQUEST_TYPE_STANDARD
        const timeout = 100;
        self.dev.controlOut(.vendor, .endpoint, bRequest, wValue, wIndex, buf, timeout) catch |e| {
            std.log.err("control xfer error: {}\n", .{e});
            return USBError.Error;
        };
    }
    pub fn bulk_transfer_send(self: *@This(), data: []const u8) !usize {
        const actual_xfer_len = self.dev.bulkOut(self.vendor_ep_out, data, 100) catch |e| {
            std.log.err("bulk transfer error: {}\n", .{e});
            return USBError.Error;
        };
        if (actual_xfer_len != data.len) {
            std.log.warn("short transfer: {}\n", .{@as(i32, @intCast(data.len)) - @as(i32, @intCast(actual_xfer_len))});
        }
        return actual_xfer_len;
    }
    pub fn bulk_transfer_recv(self: *@This(), data: *[]u8) !usize {
        const recv_len = self.dev.bulkIn(self.vendor_ep_in, data, 100) catch |e| {
            std.log.err("bulk transfer error: {}\n", .{e});
            return USBError.Error;
        };
        return recv_len;
    }

    fn zig_axis_move_to_pb(axis: types.AxisMoveCmd) nanopb.AxisMoveCmd {
        var pb_move: nanopb.AxisMoveCmd = undefined;
        pb_move.pos = axis.pos;
        pb_move.vel = axis.vel;
        pb_move.acc = axis.acc;
        pb_move.jerk = axis.jerk;
        pb_move.snap = axis.snap;
        // pb_move.has_crackle = true;
        pb_move.crackle = axis.crackle;
        return pb_move;
    }

    fn zig_move_to_pb(move: types.MoveCmd) nanopb.MoveCmd {
        var pb_move: nanopb.MoveCmd = undefined;
        pb_move.has_x = true;
        pb_move.has_y = true;
        pb_move.has_z = true;
        pb_move.has_e = true;
        pb_move.x = zig_axis_move_to_pb(move.X);
        pb_move.y = zig_axis_move_to_pb(move.Y);
        pb_move.z = zig_axis_move_to_pb(move.Z);
        pb_move.e = zig_axis_move_to_pb(move.E);
        return pb_move;
    }

    fn pb_move_to_zig(move: nanopb.MoveCmd) types.MoveCmd {
        var zig_move: types.MoveCmd = undefined;
        zig_move.X = pb_axis_move_to_zig(move.x);
        zig_move.Y = pb_axis_move_to_zig(move.y);
        zig_move.Z = pb_axis_move_to_zig(move.z);
        zig_move.E = pb_axis_move_to_zig(move.e);
        return zig_move;
    }
    fn pb_axis_move_to_zig(axis: nanopb.AxisMoveCmd) types.AxisMoveCmd {
        var zig_axis: types.AxisMoveCmd = undefined;
        zig_axis.pos = axis.pos;
        zig_axis.vel = axis.vel;
        zig_axis.acc = axis.acc;
        zig_axis.jerk = axis.jerk;
        zig_axis.snap = axis.snap;
        zig_axis.crackle = axis.crackle;
        return zig_axis;
    }

    pub fn send_move(self: *@This(), msg: types.MoveCmd) !void {
        _ = self;
        std.debug.print("***************************************\n", .{});
        std.debug.print("***************************************\n", .{});
        std.debug.print("msg: {any}\n", .{msg});
        var cmd: nanopb.Cmd = undefined;
        cmd.which_payload = nanopb.Cmd_move_tag;
        cmd.payload.move = zig_move_to_pb(msg);
        var buf: [2 * @sizeOf(types.MoveCmd)]u8 = undefined;
        var stream = nanopb.pb_ostream_from_buffer(@ptrCast(@constCast(buf[0..].ptr)), buf.len);
        const status = nanopb.pb_encode(@constCast(&stream), nanopb.Cmd_fields, &cmd);
        if (!status) {
            std.log.err("Failed to encode pb: {}\n", .{status});
            return USBError.Error;
        }
        std.debug.print("msg size: {}\n", .{@bitSizeOf(types.MoveCmd) / 8});
        std.debug.print("bytes encoded: {}\n", .{stream.bytes_written});

        var istream = nanopb.pb_istream_from_buffer(@ptrCast(@constCast(buf[0..].ptr)), stream.bytes_written);
        var recv_cmd: nanopb.Cmd = undefined;
        const status2 = nanopb.pb_decode(@constCast(&istream), nanopb.Cmd_fields, &recv_cmd);

        const tcmd = pb_move_to_zig(cmd.payload.move);
        const rcmd = pb_move_to_zig(recv_cmd.payload.move);

        if (!status2) {
            std.log.err("Failed to decode pb: {}\n", .{status2});
        }
        std.debug.print("trans_cmd: {any}\n", .{tcmd});
        std.debug.print("recv_cmd: {any}\n", .{rcmd});
    }

    pub fn deinit(self: *@This()) void {
        self.dev.close();
        self.ctx.deinit();
    }
};
