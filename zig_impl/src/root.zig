//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const plt = @import("plot.zig");
const diff = @import("diff.zig");
const libusb = @import("libusb");
const Transport = @import("transport.zig");

const AxisMoveCmd = types.AxisMoveCmd;
const MoveCmd = types.MoveCmd;

// pub const std_options: std.Options = .{
//     .log_level = .debug,
// };

var gpa = *std.heap.GeneralPurposeAllocator(.{});
const Diff = diff.BinomialDerivator(6);

const Server = struct {
    move_queue: std.fifo.LinearFifo(MoveCmd, .Dynamic) = undefined,
    alloc: std.mem.Allocator = undefined,
    differ: [4]Diff = undefined,
    Ts: f32 = 0.0001,
    run_thread: bool = false,
    pub fn init(allocator: std.mem.Allocator) !*@This() {
        var ret = try allocator.create(@This());
        ret.move_queue = std.fifo.LinearFifo(MoveCmd, .Dynamic).init(allocator);
        ret.alloc = allocator;
        return ret;
    }
    pub fn run(self: *@This()) void {
        std.log.info("Starting server", .{});
        while (self.run_thread) {
            std.log.info("Running main server thread", .{});
            std.Thread.sleep(1e9);
        }
        std.log.info("We're done", .{});
    }

    pub fn EnqueueMove(self: *@This(), cmd: MoveCmd) void {
        self.move_queue.writeItem(cmd) catch {
            std.log.err("We're done", .{});
        };
    }
    pub fn Plot(self: *@This()) void {
        // kick off a thread that runs the plot window
        plt.PlotMove(self.move_queue.readableSlice(0), self.Ts, self.alloc) catch {
            std.log.err("Failed to plot move data", .{});
        };
        self.move_queue.discard(self.move_queue.count);
    }
    pub fn GetDerivative(self: *@This(), val: f64, axis: u4) AxisMoveCmd {
        const xdiff = self.differ[axis].calc(val);
        const cmd: AxisMoveCmd = .{ .pos = @floatCast(xdiff[0]), .vel = @floatCast(xdiff[1]), .acc = @floatCast(xdiff[2]), .jerk = @floatCast(xdiff[3]), .snap = @floatCast(xdiff[4]), .crackle = @floatCast(xdiff[5]) };
        return cmd;
    }
};

var server: *Server = undefined;

fn list_usb_devs() void {
    std.log.info("Enumerating usb devices", .{});
    var ctx: ?*libusb.libusb_context = undefined;
    const r = libusb.libusb_init(&ctx);
    if (r < 0) {
        std.log.err("Initialization error {}\n", .{r});
        return;
    }

    var devs: [*c]*libusb.libusb_device = undefined;
    const dev_count = libusb.libusb_get_device_list(ctx, &devs);
    if (dev_count < 0) {
        std.log.err("Error in get device list\n", .{});
        libusb.libusb_exit(ctx);
        return;
    }

    std.log.info("{} Devices found", .{dev_count});
    for (0..@intCast(dev_count)) |i| {
        var desc: libusb.libusb_device_descriptor = undefined;

        const devs_ptr = devs[i];
        const err = libusb.libusb_get_device_descriptor(devs_ptr, &desc);
        if (err == 0) {
            std.log.warn("Device {}: Vendor=0x{x}, Product=0x{x}", .{ i, desc.idVendor, desc.idProduct });
        }
    }
    libusb.libusb_free_device_list(@ptrCast(devs), 1);
    libusb.libusb_exit(ctx);
}

fn run_server(Ts: f32, allocator: std.mem.Allocator) void {
    list_usb_devs();
    var transport = Transport.USBTransport.init(0x4012, 0xcafe) catch {
        std.log.err("Failed to init transport", .{});
        return;
    };
    // transport.control_xfer(0x1);
    // std.Thread.sleep(1e9);
    transport.control_xfer(0xbeef);
    // std.Thread.sleep(1e9);
    transport.control_xfer(0x1);
    // std.Thread.sleep(1e9);

    transport.control_xfer(0xbeef);

    transport.deinit();

    std.debug.print("Starting server\n", .{});
    server = Server.init(allocator) catch {
        std.log.err("Failed to allocate Server", .{});
        return;
    };
    server.Ts = Ts;
    for (&server.differ) |*d| {
        d.* = Diff.init(Ts);
    }
    server.run_thread = true;
    server.run();
}

pub export fn enable_stepper(axis: i32) callconv(.C) void {
    std.log.info("Enabling axis: {}", .{axis});
}
pub export fn disable_stepper(axis: i32) callconv(.C) void {
    std.log.info("Disabling axis: {}", .{axis});
}

pub export fn enqueue_command(x: f64, y: f64, z: f64, e: f64, index: i32, safe_stop: i32) callconv(.C) void {
    _ = index;
    std.log.warn("Move cmd: X={} Y={} Z={}, E={}", .{ x, y, z, e });
    const X = server.GetDerivative(x, 0);
    const Y = server.GetDerivative(y, 1);
    const Z = server.GetDerivative(z, 2);
    const E = server.GetDerivative(e, 3);

    server.EnqueueMove(.{
        .X = X,
        .Y = Y,
        .Z = Z,
        .E = E,
    });
    if (safe_stop != 0) {
        std.log.warn("Safe Stop here", .{});
        server.Plot();
    }
}

pub export fn configure(interp_time: f32) callconv(.C) void {
    std.log.info("Configuring Server:", .{});
    std.log.info("Interepolation time: {}", .{interp_time});
    var thread_config = std.Thread.SpawnConfig{};
    thread_config.allocator = std.heap.c_allocator;
    const thread = std.Thread.spawn(thread_config, run_server, .{ interp_time, std.heap.c_allocator }) catch {
        std.log.err("Server thread failed to start!:", .{});
        return;
    };
    thread.detach();
    std.log.info("Finished Configuring Server", .{});
}

pub export fn shutdown() callconv(.C) void {
    std.log.info("Turning off Motors", .{});
}

test "startup shutdown" {
    const expect = std.testing.expect;
    configure(1e-4);
    std.Thread.sleep(1e9);
    try expect(server.run_thread == true);
    shutdown();
    std.Thread.sleep(1e6);
}
