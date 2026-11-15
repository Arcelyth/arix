//! https://streams.spec.whatwg.org/#queue-with-sizes
const QueueWithSizes = @This();
const std = @import("std");
const types = @import("types.zig");

/// A JavaScript value and its queue size.
pub const ValueWithSize = struct {
    // value: ,
    size: f64,
};

/// An entry shared by readable and writable stream queues.
pub const EnqueuedValue = union(enum) {
    /// Bytes supplied by native code.
    native: []u8,
    js: ValueWithSize,
    /// The writable-stream close marker.
    /// See https://streams.spec.whatwg.org/#close-sentinel
    close_sentinel,
};

queue: std.Deque(EnqueuedValue) = .empty,
total_size: f64 = 0,

pub const empty: QueueWithSizes = .{};
