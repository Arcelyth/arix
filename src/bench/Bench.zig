/// Type-erased benchmark interface.
const Bench = @This();

const std = @import("std");

name: []const u8,
ptr: *anyopaque,
stepFn: *const fn (*anyopaque, []const u8) anyerror!usize,

pub fn init(
    name: []const u8,
    pointer: anytype,
    comptime stepFn: fn (@TypeOf(pointer), []const u8) anyerror!usize,
) Bench {
    const Ptr = @TypeOf(pointer);
    const gen = struct {
        fn step(ptr: *anyopaque, input: []const u8) anyerror!usize {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return stepFn(self, input);
        }
    };
    return .{ .name = name, .ptr = pointer, .stepFn = gen.step };
}

pub inline fn step(self: Bench, input: []const u8) !usize {
    return self.stepFn(self.ptr, input);
}

pub fn run(self: Bench, input: []const u8, iterations: usize, io: std.Io) !u64 {
    const start = std.Io.Clock.Timestamp.now(io, .cpu_process);
    for (0..iterations) |_| {
        const result = try self.step(input);
        std.mem.doNotOptimizeAway(result);
    }
    return @intCast(start.untilNow(io).raw.nanoseconds);
}
