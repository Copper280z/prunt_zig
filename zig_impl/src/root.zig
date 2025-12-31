//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const plt = @import("plot.zig");
const diff = @import("diff.zig");
const Transport = @import("transport.zig");
const dequeue = @import("dequeue.zig");

const AxisMoveCmd = types.AxisMoveCmd;
const MoveCmd = types.MoveCmd;

// pub const std_options: std.Options = .{
//     .log_level = .err,
// };
// pub const log_level: std.log.log_level = .debug;

const Diff = diff.BinomialDerivator(6);

const DeviceConfig = struct {
    x: bool,
    y: bool,
    z: bool,
    e: bool,
};

const MoveQueue = dequeue.Deque(MoveCmd);

const Server = struct {
    move_queue: MoveQueue,
    // move_queue: std.fifo.LinearFifo(MoveCmd, .{ .Static = 5000 }) = undefined,
    alloc: std.mem.Allocator = undefined,
    differ: [4]Diff = undefined,
    Ts: f32 = 0.0001,
    run_thread: bool = false,
    transport: Transport.USBTransport,
    pub fn init(allocator: std.mem.Allocator, Ts: f32) !*@This() {
        var ret = try allocator.create(@This());
        ret.move_queue = try MoveQueue.initCapacity(allocator, 5000);
        ret.Ts = Ts;

        for (&ret.differ) |*d| {
            d.* = Diff.init(Ts);
        }
        ret.run_thread = true;

        ret.alloc = allocator;
        ret.transport = try Transport.USBTransport.init(0x4011, 0xcafe);
        return ret;
    }
    pub fn run(self: *@This()) void {
        std.log.info("Starting server", .{});
        std.debug.print("Server thread run\n", .{});
        // var i: usize = 0;
        // var msg: [512]u8 = undefined;
        // for (msg[0..]) |*b| {
        //     b.* = @addWithOverflow(@as(u8, 45), @as(u8, @intCast(i % 255)))[0];
        // }
        // i += 1;
        // for (0..3334) |_| {
        //     const maybe_sent = self.transport.bulk_transfer_send(&msg);
        //     if (maybe_sent) |s| {
        //         std.log.info("Sent {} bytes via bulk transfer\n", .{s});
        //     } else |err| {
        //         std.log.info("Error in bulk transfer: {any}\n", .{err});
        //     }
        // }
        var msgs_sent: usize = 0;
        var timer = std.time.Timer.start() catch unreachable;
        while (self.run_thread) {
            // std.log.info("Running main server thread", .{});
            while (self.move_queue.len > 0) {
                std.log.info("something in queue", .{});

                const maybe_cmd = self.move_queue.popFront();

                if (maybe_cmd) |cmd| {
                    std.log.info("Processing move command: {}", .{cmd});
                    self.transport.send_move(cmd) catch |err| {
                        std.log.err("Failed to send move command: {}", .{err});
                        continue;
                    };
                    msgs_sent += 1;
                    std.log.info("Messages sent: {}", .{msgs_sent});
                }
            }
        }
        const time = timer.read();
        std.debug.print("Server Thread Time taken for 10k messages: {} ms\n", .{time / 1000000});
        std.debug.print("Server thread sent: {} messages\n", .{msgs_sent});
        std.log.info("We're done: run", .{});
    }

    pub fn EnqueueMove(self: *@This(), cmd: MoveCmd) void {
        self.move_queue.pushBack(self.alloc, cmd) catch {
            std.log.err("failed to enqueue move\n", .{});
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
        // std.debug.print("axis {}: derivative: {}\n", .{ axis, cmd });
        return cmd;
    }
};

var server: ?*Server = null;

fn run_server(allocator: std.mem.Allocator) void {
    _ = allocator;
    if (server) |s| {
        std.log.info("running server loop\n", .{});
        s.run();
    }
    std.debug.print("Server thread done\n", .{});
    std.log.info("Done\n", .{});
    std.Thread.sleep(1e9);
}

pub export fn enable_stepper(axis: i32) callconv(.C) void {
    std.log.info("Enabling axis: {}", .{axis});
}
pub export fn disable_stepper(axis: i32) callconv(.C) void {
    std.log.info("Disabling axis: {}", .{axis});
}

pub export fn enqueue_command(x: f64, y: f64, z: f64, e: f64, index: i32, safe_stop: i32) callconv(.C) void {
    _ = index;
    // std.log.warn("Move cmd: X={} Y={} Z={}, E={}", .{ x, y, z, e });
    if (server) |s| {
        const X = s.GetDerivative(x, 0);
        const Y = s.GetDerivative(y, 1);
        const Z = s.GetDerivative(z, 2);
        const E = s.GetDerivative(e, 3);

        s.EnqueueMove(.{
            .X = X,
            .Y = Y,
            .Z = Z,
            .E = E,
        });
        if (safe_stop != 0) {
            std.log.warn("Safe Stop here", .{});
            // s.Plot();
        }
    }
}

// TODO: make allocator configurable
pub export fn configure(interp_time: f32) callconv(.C) void {
    const allocator = std.heap.c_allocator;
    std.log.info("Configuring Server:", .{});
    std.log.info("Interepolation time: {}", .{interp_time});
    var thread_config = std.Thread.SpawnConfig{};
    thread_config.allocator = allocator;

    std.log.info("Starting server\n", .{});
    server = Server.init(allocator, interp_time) catch |err| {
        std.log.err("Failed to allocate Server: {any}", .{err});
        return;
    };
    var thread = std.Thread.spawn(thread_config, run_server, .{allocator}) catch {
        std.log.err("Server thread failed to start!:", .{});
        return;
    };
    // TODO: add timeout
    while (true) {
        if (server) |s| {
            if (s.run_thread) {
                break;
            }
        }
    }
    thread.detach();
    std.log.info("Finished Configuring Server", .{});
}

pub export fn shutdown() callconv(.C) void {
    std.log.info("Turning off Motors", .{});
}

test "startup shutdown" {
    // std.testing.log_level = .debug;
    const expect = std.testing.expect;
    configure(1e-4);
    if (server) |s| {
        try expect(s.run_thread == true);
        var timer = std.time.Timer.start() catch unreachable;
        for (0..10000) |_i| {
            const i: f64 = @floatFromInt(_i);
            // std.debug.print("enqueue_command!\n", .{});
            enqueue_command(i * 1.0, i * 2.0, i * 3.0, i * 4.0, 0, 0);
        }
        const time = timer.read();
        // while (s.move_queue.len > 0) {}
        shutdown();
        s.run_thread = false;
        std.debug.print("Time taken for 10k messages: {} ns\n", .{time});
    } else {
        std.debug.print("Server is null\n", .{});
        try expect(false);
    }
    std.Thread.sleep(2e9);
    std.debug.print("Done!\n", .{});
}
