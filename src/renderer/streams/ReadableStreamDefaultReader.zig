//! https://streams.spec.whatwg.org/#readablestreamdefaultreader
const ReadableStreamDefaultReader = @This();

const std = @import("std");
const Stream = @import("ReadableStream.zig");
const types = @import("types.zig");

allocator: std.mem.Allocator,
stream: ?*Stream = null,
read_requests: std.Deque(types.ReadRequest) = .empty,
