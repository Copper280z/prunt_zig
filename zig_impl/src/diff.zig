const std = @import("std");

pub fn BinomialDerivator(order: u8) type {
    const verbose = false;
    if (order % 2 == 1) {
        @compileError("Odd derivatiive orders not currently supported");
    }

    const n_values = order + 1;
    // const center_idx: u32 = @divExact(@as(i32, @intCast(order)), 2);
    const FIFO = std.fifo.LinearFifo(f64, .{ .Static = n_values });
    var _binomials: [n_values][n_values]u32 = comptime blk: {
        var bins: [n_values][n_values]u32 = undefined;
        for (0..n_values) |i| {
            for (0..n_values) |j| {
                bins[i][j] = 0;
            }
        }
        break :blk bins;
    };

    for (0..n_values) |n| {
        for (0..n + 1) |k| {
            if ((k == 0) or (k == order)) {
                _binomials[n][k] = 1;
                continue;
            }
            var res: u32 = 1;
            for (1..k + 1) |i| {
                res *= (n - i + 1);
                res /= i;
            }
            _binomials[n][k] = res;
        }
    }

    const binomials = _binomials;

    return struct {
        previous_vals: FIFO,
        Ts: f64 = 1.0,
        startup_counter: u8 = 0,
        pub fn init(Ts: f64) @This() {
            var fifo = FIFO.init();
            for (0..n_values) |_| {
                fifo.writeItemAssumeCapacity(0);
            }
            return .{ .previous_vals = fifo, .Ts = Ts };
        }
        pub fn startup(self: *@This(), data: [n_values]f64) [n_values][order]f64 {
            for (data) |val| {
                self.fifo.writeItemAssumeCapacity(val);
            }
        }
        pub fn calc(self: *@This(), val: f64) [order]f64 {
            if (verbose) std.debug.print("\nval: {d:6.3}, count: {}, n_values: {}\n", .{ val, self.previous_vals.count, n_values });
            if (self.previous_vals.count >= n_values) {
                self.previous_vals.discard(1);
            }
            self.previous_vals.writeItemAssumeCapacity(val);

            var out: [order]f64 = undefined;
            for (0..order) |n| {
                if (verbose) std.debug.print("order: {}\n", .{n});
                if (n == 0) {
                    out[n] = val;
                    continue;
                }
                if (n % 2 == 1) {
                    out[n] = self.central_odd_difference(n);
                } else {
                    out[n] = self.central_even_difference(n);
                }
            }
            return out;
        }
        fn forward_difference(self: *@This(), n: usize, data: []f64) f64 {
            _ = self;
            _ = n;
            _ = data;
        }
        fn central_even_difference(self: *@This(), n: usize) f64 {
            var delta: f64 = 0;
            const bins = binomials[n][0 .. n + 1];
            if (verbose) std.debug.print("binomials: ", .{});
            for (0.., bins) |i, C| {
                const coeff = @as(f64, @floatFromInt(std.math.pow(i32, -1, @intCast(i)) * @as(i32, @intCast(C))));
                if (verbose) std.debug.print("{}, ", .{coeff});
            }
            if (verbose) std.debug.print("\nf(): ", .{});
            for (0.., bins) |i, C| {
                const idx: i32 = @divExact(@as(i32, @intCast(n)), 2) - @as(i32, @intCast(i));
                const f = self.previous_vals.peekItem(@intCast(order / 2 - idx));
                const coeff = @as(f64, @floatFromInt(std.math.pow(i32, -1, @intCast(i)) * @as(i32, @intCast(C))));
                if (verbose) std.debug.print("{d:4.1}, ", .{f});
                delta += coeff * f;
            }
            const fd = delta / (std.math.pow(f64, self.Ts, @floatFromInt(n)));
            if (verbose) std.debug.print("\nfd={}\n", .{fd});

            return fd;
        }
        fn central_odd_difference(self: *@This(), n: usize) f64 {
            var delta: f64 = 0.0;
            const n_over_2 = @as(f64, @floatFromInt(n)) / 2.0;
            // const ceil_n_over_2: usize = @intFromFloat(@ceil(n_over_2));
            const bins = binomials[n][0 .. n + 1];
            if (verbose) std.debug.print("binomials: ", .{});
            for (0.., bins) |i, C| {
                const coeff = @as(f64, @floatFromInt(std.math.pow(i32, -1, @intCast(i)) * @as(i32, @intCast(C))));
                if (verbose) std.debug.print("{}, ", .{coeff});
            }
            if (verbose) std.debug.print("\nf(): ", .{});
            for (0.., bins) |i, C| {
                const idx_low: i32 = @as(i32, @intFromFloat(@floor(n_over_2))) - @as(i32, @intCast(i));
                const idx_high: i32 = @as(i32, @intFromFloat(@ceil(n_over_2))) - @as(i32, @intCast(i));

                const f_low = self.previous_vals.peekItem(@intCast(order / 2 - idx_low));
                const f_high = self.previous_vals.peekItem(@intCast(order / 2 - idx_high));
                const coeff = -1.0 * @as(f64, @floatFromInt(std.math.pow(i32, -1, @intCast(i)) * @as(i32, @intCast(C))));
                const f_avg = (f_low + f_high) / 2.0;
                if (verbose) std.debug.print("{d:4.1}, ", .{f_avg});
                delta += coeff * f_avg;
            }
            const fd = delta / (std.math.pow(f64, self.Ts, @floatFromInt(n)));
            if (verbose) std.debug.print("\nfd={}\n", .{fd});

            return fd;
        }
        fn binomial(n: usize) [n_values]u32 {
            return binomials[n];
        }
    };
}

test "binomials" {
    const verbose = false;
    const order = 6;

    const testing = std.testing;
    const SecondOrderDiff = BinomialDerivator(order);

    for (0..order) |n| {
        if (verbose) std.debug.print("{}th order FD Binomials: ", .{n});
        const binomials = SecondOrderDiff.binomial(n);
        for (binomials) |C| {
            if (verbose) std.debug.print("{}, ", .{C});
        }
        if (verbose) std.debug.print("\n", .{});
    }
    if (verbose) std.debug.print("\n", .{});

    const binomials = SecondOrderDiff.binomial(5);

    const known_binomials = [_]u32{ 1, 5, 10, 10, 5, 1, 0 };

    for (binomials, known_binomials) |C, K| {
        if (verbose) std.debug.print("{}, ", .{C});
        try testing.expectEqual(K, C);
    }
    if (verbose) std.debug.print("\n", .{});
}

fn populate_test_arr_poly(arr: []f64, Ts: f64, order: f64) void {
    for (arr, 0..) |*v, i| {
        const x = @as(f64, @floatFromInt(i));
        v.* = std.math.pow(f64, x * Ts, order);
    }
}

fn populate_test_arr_exp(arr: []f64, coeff: f64) void {
    for (arr, 0..) |*v, i| {
        const x = @as(f64, @floatFromInt(i));
        v.* = std.math.exp(coeff * x);
    }
}

test "binomial_diff" {
    const verbose = false;
    const order = 6;
    const num_vals = 50;
    const Ts = 0.005;

    var data: [num_vals + order + 1]f64 = undefined;
    var result: [num_vals + order + 1][order]f64 = undefined;
    populate_test_arr_poly(&data, Ts, 8);

    const testing = std.testing;
    const SecondOrderDiff = BinomialDerivator(order);
    var differ = SecondOrderDiff.init(Ts);

    if (verbose) std.debug.print("Testing Binomial FD\n", .{});

    for (data, 0..) |x, i| {
        const offset = order / 2;
        if (i < (offset)) {
            _ = differ.calc(x);
        } else {
            result[i - offset] = differ.calc(x);
        }
    }

    for (0.., data, result) |_x, y, dy| {
        const x = @as(f64, @floatFromInt(_x));
        if (data.len - order / 2 <= _x) continue;
        if (x == 0) continue;

        if (verbose) std.debug.print("x,y = {d:3.1}, {d:4.3}: ", .{ x, y });
        try testing.expectApproxEqAbs((8.0) * std.math.pow(f64, (x * Ts), 7), dy[1], 1e-3);
        try testing.expectApproxEqAbs((8.0 * 7.0) * std.math.pow(f64, (x * Ts), 6), dy[2], 1e-3);
        try testing.expectApproxEqAbs((8.0 * 7.0 * 6.0) * std.math.pow(f64, (x * Ts), 5), dy[3], 1e-2);
        try testing.expectApproxEqAbs((8.0 * 7.0 * 6.0 * 5.0) * std.math.pow(f64, (x * Ts), 4), dy[4], 1e-2);
        try testing.expectApproxEqAbs((8.0 * 7.0 * 6.0 * 5.0 * 4.0) * std.math.pow(f64, (x * Ts), 3), dy[5], 1e-1);
        if (verbose) std.debug.print("\n", .{});
    }
}
