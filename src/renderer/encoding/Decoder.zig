const Decoder = @This();
const std = @import("std");
const Encoding = @import("encoding.zig").Encoding;
const IoQueue = @import("queue.zig").IoQueue;
const ascii = @import("../utils/ascii.zig");

pub const ErrorMode = enum { replacement, fatal };

/// Item storage must remain valid until processItem has appended it to output.
pub const HandlerResult = union(enum) {
    finished,
    items: []const u21,
    err,
    continue_,
};

pub const ProcessResult = enum { finished, continue_ };

encoding: Encoding,

// https://encoding.spec.whatwg.org/#concept-encoding-run
/// NeedInput suspends an unfinished stream; the caller retains both queues and
/// the decoder to resume.
/// Fatal decoding errors return InvalidSequence.
pub fn processQueue(
    self: *Decoder,
    allocator: std.mem.Allocator,
    input: *IoQueue(u8),
    output: *IoQueue(u21),
    mode: ErrorMode,
) !ProcessResult {
    while (true) {
        const result = try self.processItem(allocator, try input.read(), input, output, mode);
        if (result != .continue_) return result;
    }
}

/// https://encoding.spec.whatwg.org/#concept-encoding-process
pub fn processItem(
    self: *Decoder,
    allocator: std.mem.Allocator,
    item: ?u8,
    input: *IoQueue(u8),
    output: *IoQueue(u21),
    mode: ErrorMode,
) !ProcessResult {
    const result = try self.handler(allocator, input, item);
    return processResult(allocator, output, result, mode);
}

// Decoder error policy is independent of the encoding-specific handler.
fn processResult(allocator: std.mem.Allocator, output: *IoQueue(u21), result: HandlerResult, mode: ErrorMode) !ProcessResult {
    switch (result) {
        .finished => {
            try output.push(allocator, null);
            return .finished;
        },
        .items => |items| {
            for (items) |cp| std.debug.assert(cp <= 0x10FFFF and !ascii.isSurrogate(u21, cp));
            try output.pushSlice(allocator, items);
        },
        .err => switch (mode) {
            .replacement => try output.push(allocator, 0xFFFD),
            .fatal => return error.InvalidSequence,
        },
        .continue_ => {},
    }
    return .continue_;
}

/// https://encoding.spec.whatwg.org/#handler
fn handler(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) HandlerResult {
    // TODO:
    _ = self;
    _ = allocator;
    _ = input;
    _ = item;
}
