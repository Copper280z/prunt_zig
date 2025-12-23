//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const plt = @import("plot.zig");
const diff = @import("diff.zig");
const Transport = @import("transport.zig");

const AxisMoveCmd = types.AxisMoveCmd;
const MoveCmd = types.MoveCmd;

pub const std_options: std.Options = .{
    .log_level = .info,
};

var gpa = *std.heap.GeneralPurposeAllocator(.{});
const Diff = diff.BinomialDerivator(6);

const Server = struct {
    move_queue: std.fifo.LinearFifo(MoveCmd, .Dynamic) = undefined,
    alloc: std.mem.Allocator = undefined,
    differ: [4]Diff = undefined,
    Ts: f32 = 0.0001,
    run_thread: bool = false,
    transport: Transport.USBTransport,
    pub fn init(allocator: std.mem.Allocator) !*@This() {
        var ret = try allocator.create(@This());
        ret.move_queue = std.fifo.LinearFifo(MoveCmd, .Dynamic).init(allocator);
        ret.alloc = allocator;
        ret.transport = try Transport.USBTransport.init(0x4011, 0xcafe);
        return ret;
    }
    pub fn run(self: *@This()) void {
        std.log.info("Starting server", .{});
        const msg: [3]u8 = .{ 49, 1, 3 };
        const maybe_sent = self.transport.bulk_transfer_send(&msg);
        if (maybe_sent) |s| {
            std.log.info("Sent {} bytes via bulk transfer\n", .{s});
        } else |err| {
            std.log.info("Error in bulk transfer: {any}\n", .{err});
        }
        while (self.run_thread) {
            // std.log.info("Running main server thread", .{});
            while (self.move_queue.readItem()) |cmd| {
                std.log.info("Processing move command: {}", .{cmd});
                self.transport.send_move(cmd) catch {
                    std.log.err("Failed to send move command", .{});
                };
            }
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
        std.debug.print("axis {}: derivative: {}\n", .{ axis, cmd });
        return cmd;
    }
};

var server: ?*Server = undefined;

fn run_server(Ts: f32, allocator: std.mem.Allocator) void {
    _ = allocator;
    if (server) |s| {
        s.Ts = Ts;
        for (&s.differ) |*d| {
            d.* = Diff.init(Ts);
        }
        s.run_thread = true;
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
    std.log.warn("Move cmd: X={} Y={} Z={}, E={}", .{ x, y, z, e });
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
            s.Plot();
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

    std.debug.print("Starting server\n", .{});
    server = Server.init(allocator) catch |err| {
        std.log.err("Failed to allocate Server: {any}", .{err});
        return;
    };
    const thread = std.Thread.spawn(thread_config, run_server, .{ interp_time, allocator }) catch {
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
    std.testing.log_level = .debug;
    const expect = std.testing.expect;
    configure(1e-4);
    if (server) |s| {
        std.Thread.sleep(1e9);
        try expect(s.run_thread == true);
        for (0..50) |_i| {
            const i: f64 = @floatFromInt(_i);
            std.debug.print("enqueue_command!\n", .{});
            enqueue_command(i * 1.0, i * i * 2.0, i * i * i * 3.0, i * 4.0, 0, 0);
        }
        shutdown();
        s.run_thread = false;
    } else {
        std.debug.print("Server is null\n", .{});
        try expect(false);
    }
    std.Thread.sleep(2e9);
    std.debug.print("Done!\n", .{});
}
