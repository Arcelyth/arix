const std = @import("std");

// FIXME: Not implemented.
pub const ArrayBuffer = opaque {};
pub const ArrayBufferView = opaque {};

pub const State = enum {
    readable,
    closed,
    errored,
};

/// Native cancellation reasons.
// TODO: support js value.
pub const Reason = union(enum) {
    none,
    failure: anyerror,
    composite: []const Reason,
};

pub const Source = UnderlyingSource(@import("ReadableByteStreamController.zig"));
pub const DefaultSource = UnderlyingSource(@import("ReadableStreamDefaultController.zig"));

/// Source callbacks receive the controller for their stream type.
/// See https://streams.spec.whatwg.org/#dictdef-underlyingsource
pub fn UnderlyingSource(comptime Controller: type) type {
    return struct {
        /// Points to the source’s data.
        /// For example, a file handle, network connection, or current read position.
        context: *anyopaque,
        start: ?*const fn (*anyopaque, *Controller) anyerror!void = null,
        pull: ?*const fn (*anyopaque, *Controller) void = null,
        cancel: ?*const fn (*anyopaque, *Controller, Reason) void = null,
        deinit: ?*const fn (*anyopaque) void = null,
    };
}

/// https://streams.spec.whatwg.org/#pull-into-descriptor
pub const PullIntoDescriptor = struct {
    buffer: *ArrayBuffer,
    buffer_byte_length: usize,
    byte_offset: usize,
    byte_length: usize,
    bytes_filled: usize,
    minimum_fill: usize,
    element_size: usize,
    // FIXME: need ECMAScript's TypedArray constructor.
    //    view_constructor: ,
    reader_type: enum { default, byob, none },
};

/// https://streams.spec.whatwg.org/#readable-byte-stream-queue-entry
pub const ByteQueueEntry = struct {
    buffer: *ArrayBuffer,
    byte_offset: usize,
    byte_length: usize,
};

/// https://streams.spec.whatwg.org/#read-into-request
// FIXME: Not implemented.
pub const ReadIntoRequest = struct {
    context: *anyopaque,
    chunk_steps: *const fn (*anyopaque) void,
    close_steps: *const fn (*anyopaque) void,
    error_steps: *const fn (*anyopaque) void,
};

/// https://streams.spec.whatwg.org/#read-request
// FIXME: Not implemented.
pub const ReadRequest = struct {
    context: *anyopaque,
    chunk_steps: *const fn (*anyopaque) void,
    close_steps: *const fn (*anyopaque) void,
    error_steps: *const fn (*anyopaque) void,
};
