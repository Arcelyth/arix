//! https://streams.spec.whatwg.org/#readablestreamdefaultcontroller
const ReadableStreamDefaultController = @This();

const std = @import("std");
const Stream = @import("ReadableStream.zig");
const types = @import("types.zig");
const QueueWithSizes = @import("QueueWithSizes.zig");

stream: *Stream,
queue: QueueWithSizes = .empty,
queue_total_size: f64 = 0,
started: bool = false,
close_requested: bool = false,
pull_again: bool = false,
pulling: bool = false,
strategy_hwm: f64,
// strategy_size_algorithm: ,
// pull_algorithm: ,
// cancel_algorithm: ,
