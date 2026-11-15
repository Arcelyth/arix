//! https://streams.spec.whatwg.org/#rs-class
const ReadableStream = @This();
const std = @import("std");
const ReadableByteStreamController = @import("ReadableByteStreamController.zig");
const ReadableStreamDefafultController = @import("ReadableStreamDefaultController.zig");
const ReadableStreamDefaultReader = @import("ReadableStreamDefaultReader.zig");
const ReadableStreamBYOBReader = @import("ReadableStreamBYOBReader.zig");
pub const types = @import("types.zig");

const Controller = union(enum) {
    default: ReadableStreamDefafultController,
    byte: ReadableByteStreamController,
};

const Reader = union(enum) {
    default: ReadableStreamDefaultReader,
    byob: ReadableStreamBYOBReader,
};

allocator: std.mem.Allocator,
state: types.State = .readable,
// FIXME: Replace with specified error type.
stored_error: ?anyerror = null,
disturbed: bool = false,
reader: ?*Reader = null,
controller: Controller,

/// Creates a default stream with a size strategy. Call release when finished.
pub fn create(allocator: std.mem.Allocator, source: ?types.DefaultSource) !*ReadableStream {
    _ = allocator;
    _ = source;
    @panic("TODO");
}

/// Sets up a byte stream with the default byte high water mark, zero.
/// Call release when finished.
pub fn createByteStream(allocator: std.mem.Allocator, source: ?types.Source) !*ReadableStream {
    _ = allocator;
    _ = source;
    @panic("TODO");
}

pub fn release(self: *ReadableStream) void {
    self.allocator.destroy(self);
}

/// Tees the stream into two branches of the same type. Each needs release.
/// https://streams.spec.whatwg.org/#readablestream-tee
pub fn tee(self: *ReadableStream) ![2]*ReadableStream {
    _ = self;
    @panic("TODO");
}

/// https://streams.spec.whatwg.org/#readablestream-locked
pub fn isLocked(self: *const ReadableStream) bool {
    return self.reader != null;
}
