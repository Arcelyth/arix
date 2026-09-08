/// Type-erased benchmark interface.
const Bench = @This();

const std = @import("std");

name: []const u8,
ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    prepareFn: *const fn (*anyopaque, []const u8) anyerror!void,
    stepFn: *const fn (*anyopaque) anyerror!usize,
    finishFn: *const fn (*anyopaque) void,
};

pub fn init(
    name: []const u8,
    pointer: anytype,
    comptime prepareFn: fn (@TypeOf(pointer), []const u8) anyerror!void,
    comptime stepFn: fn (@TypeOf(pointer)) anyerror!usize,
    comptime finishFn: fn (@TypeOf(pointer)) void,
) Bench {
    const Pointer = @TypeOf(pointer);
    const Wrapper = struct {
        const vtable = VTable{
            .prepareFn = prepare,
            .stepFn = step,
            .finishFn = finish,
        };

        fn prepare(ptr: *anyopaque, input: []const u8) anyerror!void {
            return prepareFn(@as(Pointer, @ptrCast(@alignCast(ptr))), input);
        }

        fn step(ptr: *anyopaque) anyerror!usize {
            return stepFn(@as(Pointer, @ptrCast(@alignCast(ptr))));
        }

        fn finish(ptr: *anyopaque) void {
            finishFn(@as(Pointer, @ptrCast(@alignCast(ptr))));
        }
    };
    return .{
        .name = name,
        .ptr = pointer,
        .vtable = &Wrapper.vtable,
    };
}

pub fn run(self: Bench, input: []const u8, iters: usize, io: std.Io) !u64 {
    var elapsed: u64 = 0;
    for (0..iters) |_| {
        try self.vtable.prepareFn(self.ptr, input);

        const start = std.Io.Clock.Timestamp.now(io, .cpu_process);
        const result = self.vtable.stepFn(self.ptr) catch |err| {
            self.vtable.finishFn(self.ptr);
            return err;
        };
        elapsed += @intCast(start.untilNow(io).raw.nanoseconds);
        std.mem.doNotOptimizeAway(result);

        self.vtable.finishFn(self.ptr);
    }
    return elapsed;
}
