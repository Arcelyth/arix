/// Implementation of CSS Syntax §5.3 token streams.
const TokenStream = @This();

const std = @import("std");
const parsing_results = @import("parsing_results.zig");
const ComponentValue = parsing_results.ComponentValue;
const Token = @import("token.zig").Token;

pub const Item = union(enum) {
    token: Token,
    component_value: ComponentValue,
};

/// Half-open byte offsets into the decoded UTF-8 source.
pub const Span = struct {
    start: u32,
    end: u32,
};

pub const MarkError = error{NoMark};
pub const SourceMapError = error{InvalidSourceMap};

allocator: std.mem.Allocator,
tokens: []const Item,
index: usize = 0,
marked_indexes: std.ArrayList(usize) = .empty,

/// Optional source information used to reproduce declaration text.
source: ?[]const u8 = null,
spans: ?[]const Span = null,

pub fn init(allocator: std.mem.Allocator, tokens: []const Item) TokenStream {
    return .{
        .allocator = allocator,
        .tokens = tokens,
    };
}

pub fn initWithSource(
    allocator: std.mem.Allocator,
    tokens: []const Item,
    source: []const u8,
    spans: []const Span,
) SourceMapError!TokenStream {
    if (tokens.len != spans.len or source.len > std.math.maxInt(u32))
        return error.InvalidSourceMap;

    var prev_end: u32 = 0;
    for (spans) |span| {
        if (span.start < prev_end or span.end < span.start or span.end > source.len)
            return error.InvalidSourceMap;
        prev_end = span.end;
    }

    return .{
        .allocator = allocator,
        .tokens = tokens,
        .source = source,
        .spans = spans,
    };
}

pub fn deinit(self: *TokenStream) void {
    self.marked_indexes.deinit(self.allocator);
}

pub inline fn nextToken(self: *const TokenStream) Item {
    if (self.index < self.tokens.len) return self.tokens[self.index];
    return .{ .token = .eof };
}

pub inline fn empty(self: *const TokenStream) bool {
    return isEof(self.nextToken());
}

pub inline fn consumeToken(self: *TokenStream) Item {
    const item = self.nextToken();
    self.index += 1;
    return item;
}

pub inline fn discardToken(self: *TokenStream) void {
    if (!self.empty()) self.index += 1;
}

pub fn mark(self: *TokenStream) std.mem.Allocator.Error!void {
    try self.marked_indexes.append(self.allocator, self.index);
}

pub fn restoreMark(self: *TokenStream) MarkError!void {
    self.index = self.marked_indexes.pop() orelse return error.NoMark;
}

pub fn discardMark(self: *TokenStream) MarkError!void {
    _ = self.marked_indexes.pop() orelse return error.NoMark;
}

pub fn discardWhitespace(self: *TokenStream) void {
    while (isWhitespace(self.nextToken())) self.discardToken();
}

pub fn process(
    self: *TokenStream,
    comptime Result: type,
    context: anytype,
    action: anytype,
) Result {
    while (true) {
        if (action(context, self, self.nextToken())) |result| return result;
    }
}

pub fn originalText(self: *const TokenStream, first: usize, past_last: usize) ?[]const u8 {
    const source = self.source orelse return null;
    const spans = self.spans orelse return null;
    if (first > past_last or past_last > spans.len) return null;

    if (first == past_last) {
        const position: usize = if (first < spans.len) spans[first].start else source.len;
        return source[position..position];
    }

    return source[spans[first].start..spans[past_last - 1].end];
}

inline fn isEof(item: Item) bool {
    return switch (item) {
        .token => |value| value == .eof,
        .component_value => false,
    };
}

inline fn isWhitespace(item: Item) bool {
    return switch (item) {
        .token => |value| value == .whitespace,
        .component_value => |value| switch (value) {
            .preserved_token => |preserved| preserved == .whitespace,
            else => false,
        },
    };
}


