//! https://streams.spec.whatwg.org/#readablestreambyobreader
const ReadableStreamBYOBReader = @This();

const std = @import("std");
const Stream = @import("ReadableStream.zig");
const types = @import("types.zig");

allocator: std.mem.Allocator,
stream: ?*Stream = null,
read_into_requests: std.Deque(types.ReadIntoRequest) = .empty,
