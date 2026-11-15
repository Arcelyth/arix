//! https://fetch.spec.whatwg.org/#concept-body
const Body = @This();
const std = @import("std");
const Stream = @import("../streams/ReadableStream.zig");
const types = @import("../streams/types.zig");

// FIXME: not implemented yet.
pub const Blob = opaque {};
pub const FormData = opaque {};
pub const URLSearchParams = opaque {};

/// A scalar value string encoded as UTF-8.
pub const USVString = []const u8;

pub const BufferSource = union(enum) {
    array_buffer: *types.ArrayBuffer,
    array_buffer_view: *types.ArrayBufferView,
};

pub const XMLHttpRequestBodyInit = union(enum) {
    blob: *Blob,
    buffer_source: BufferSource,
    form_data: *FormData,
    url_search_params: *URLSearchParams,
    usv_string: USVString,
};

/// https://fetch.spec.whatwg.org/#bodyinit
pub const BodyInit = union(enum) {
    stream: *Stream,
    blob: *Blob,
    buffer_source: BufferSource,
    form_data: *FormData,
    url_search_params: *URLSearchParams,
    usv_string: USVString,
};

pub const Input = union(enum) { bytes: []const u8, body_init: BodyInit };

pub const Source = union(enum) {
    bytes: []const u8,
    blob: *Blob,
    form_data: *FormData,
};

/// The body and its optional MIME type returned by extraction.
/// https://fetch.spec.whatwg.org/#body-with-type
pub const WithType = struct {
    body: Body,
    type: ?[]const u8 = null,

    pub fn deinit(self: *WithType) void {
        self.body.deinit();
    }
};

stream: *Stream,
source: ?Source = null,
length: ?u64 = null,

pub fn deinit(self: *Body) void {
    self.stream.release();
}

/// https://fetch.spec.whatwg.org/#concept-bodyinit-extract
pub fn extract(allocator: std.mem.Allocator, input: Input, keepalive: bool) !WithType {
    _ = allocator;
    _ = input;
    _ = keepalive;
}

/// https://fetch.spec.whatwg.org/#bodyinit-safely-extract
pub fn safelyExtract(allocator: std.mem.Allocator, input: Input) !WithType {
    if (input == .stream) std.debug.assert(!input.stream.disturbed and !input.stream.isLocked());
    return extract(allocator, input, false);
}

/// Tees the stream, keeps the first branch, and returns a body using the second.
/// https://fetch.spec.whatwg.org/#concept-body-clone
pub fn clone(self: *Body) !Body {
    const branches = try self.stream.tee();
    self.stream.release();
    self.stream = branches[0];
    return .{
        .stream = branches[1],
        .source = self.source,
        .length = self.length,
    };
}
