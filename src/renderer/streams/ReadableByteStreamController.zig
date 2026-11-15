//! https://streams.spec.whatwg.org/#readablebytestreamcontroller
const ReadableByteStreamController = @This();

const std = @import("std");
const Stream = @import("ReadableStream.zig");
const types = @import("types.zig");
const ReadableStreamBYOBRequest = @import("ReadableStreamBYOBRequest.zig");

stream: *Stream,
auto_allocate_chunk_size: ?u64 = null,
byob_request: ?*ReadableStreamBYOBRequest = null,
close_requested: bool = false,
pull_again: bool = false,
pulling: bool = false,
pending_pull_intos: std.Deque(types.PullIntoDescriptor) = .empty,
queue: std.Deque(types.ByteQueueEntry) = .empty,
queue_total_size: f64 = 0,
started: bool = false,
strategy_hwm: f64,
