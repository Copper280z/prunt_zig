const std = @import("std");

const Cmd = union(enum) {
    Move: MoveCmd, //
};

pub const Axis = enum { X, Y, Z, E };

pub const AxisMoveCmd = struct {
    pos: f32,
    vel: f32,
    acc: f32,
    jerk: f32,
    snap: f32,
    crackle: f32,
};
pub const MoveCmd = struct {
    X: AxisMoveCmd,
    Y: AxisMoveCmd,
    Z: AxisMoveCmd,
    E: AxisMoveCmd,
};
