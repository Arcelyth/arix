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

const eof_item: Item = .{ .token = .eof };

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

/// Return a reference to the item at the current index or the conceptual EOF
/// token.
/// "process" operation is intentionally expressed at each call site so there
/// is no callback or dynamic dispatch in the parser hot path.
pub inline fn nextToken(self: *const TokenStream) *const Item {
    if (self.index < self.tokens.len) return &self.tokens[self.index];
    return &eof_item;
}

pub inline fn empty(self: *const TokenStream) bool {
    return isEof(self.nextToken());
}

pub inline fn consumeToken(self: *TokenStream) *const Item {
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

inline fn isEof(item: *const Item) bool {
    return switch (item.*) {
        .token => |value| value == .eof,
        .component_value => false,
    };
}

inline fn isWhitespace(item: *const Item) bool {
    return switch (item.*) {
        .token => |value| value == .whitespace,
        .component_value => |value| switch (value) {
            .preserved_token => |preserved| preserved == .whitespace,
            else => false,
        },
    };
}

const testing = std.testing;

test "CSS Token Stream: consumes discards and reaches conceptual EOF" {
    const items = [_]Item{
        .{ .token = .whitespace },
        .{ .token = .{ .ident = &.{'a'} } },
    };
    var stream = TokenStream.init(testing.allocator, &items);
    defer stream.deinit();

    stream.discardWhitespace();
    try testing.expectEqual(1, stream.index);
    const ident = stream.consumeToken().token.ident;
    try testing.expectEqualSlices(u21, &.{'a'}, ident);
    try testing.expect(stream.empty());
    stream.discardToken();
    try testing.expectEqual(2, stream.index);
    try testing.expectEqual(std.meta.Tag(Token).eof, std.meta.activeTag(stream.consumeToken().token));
    try testing.expectEqual(3, stream.index);
}

test "CSS Token Stream: restores and discards nested marks" {
    const items = [_]Item{
        .{ .token = .colon },
        .{ .token = .semicolon },
    };
    var stream = TokenStream.init(testing.allocator, &items);
    defer stream.deinit();

    try stream.mark();
    stream.discardToken();
    try stream.mark();
    stream.discardToken();
    try stream.restoreMark();
    try testing.expectEqual(1, stream.index);
    try stream.discardMark();
    try testing.expectEqual(1, stream.index);
    try testing.expectError(error.NoMark, stream.restoreMark());
    try testing.expectError(error.NoMark, stream.discardMark());
}

test "CSS Token Stream: reproduces original text" {
    const source = "color /* retained */ : red";
    const items = [_]Item{
        .{ .token = .{ .ident = &.{ 'c', 'o', 'l', 'o', 'r' } } },
        .{ .token = .colon },
        .{ .token = .{ .ident = &.{ 'r', 'e', 'd' } } },
    };
    const spans = [_]Span{
        .{ .start = 0, .end = 5 },
        .{ .start = 21, .end = 22 },
        .{ .start = 23, .end = 26 },
    };
    var stream = try TokenStream.initWithSource(testing.allocator, &items, source, &spans);
    defer stream.deinit();

    try testing.expectEqualStrings(source, stream.originalText(0, 3).?);
    try testing.expectEqualStrings(": red", stream.originalText(1, 3).?);
    try testing.expectEqualStrings("", stream.originalText(3, 3).?);
    try testing.expect(stream.originalText(2, 1) == null);
}
