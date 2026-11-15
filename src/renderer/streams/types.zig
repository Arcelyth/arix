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
