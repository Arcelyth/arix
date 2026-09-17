/// Implementation of CSS Syntax §5.3 token streams.
const TokenStream = @This();

const std = @import("std");
const parsing_results = @import("parsing_results.zig");
const ComponentValue = parsing_results.ComponentValue;
const Token = @import("token.zig").Token;
const String = @import("String.zig");

const eof_item: Token = .eof;

/// Half-open byte offsets into the decoded UTF-8 source.
pub const Span = struct {
    start: u32,
    end: u32,
};

pub const MarkError = error{NoMark};
pub const SourceMapError = error{InvalidSourceMap};

allocator: std.mem.Allocator,
tokens: []const Token,
index: usize = 0,
marked_indexes: std.ArrayList(usize) = .empty,

/// Optional source information used to reproduce declaration text.
source: ?[]const u8 = null,
spans: ?[]const Span = null,

pub fn init(allocator: std.mem.Allocator, tokens: []const Token) TokenStream {
    return .{
        .allocator = allocator,
        .tokens = tokens,
    };
}

pub fn initWithSource(
    allocator: std.mem.Allocator,
    tokens: []const Token,
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
pub inline fn peek(self: *const TokenStream) Token {
    if (self.index < self.tokens.len) return self.tokens[self.index];
    return eof_item;
}

pub inline fn empty(self: *const TokenStream) bool {
    return self.peek() == .eof;
}

pub inline fn consume(self: *TokenStream) Token {
    const item = self.peek();
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
    while (self.peek() == .whitespace) self.discardToken();
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

/// A bounded view shares tokens and source storage, but has its own cursor.
pub fn view(self: *const TokenStream, start: usize, end: usize) TokenStream {
    return .{
        .allocator = self.allocator,
        .tokens = self.tokens[start..end],
        .source = self.source,
        .spans = if (self.spans) |spans| spans[start..end] else null,
    };
}

/// Consume one component without allocating a component-value tree.
pub fn skipComponent(self: *TokenStream) error{NestingLimit}!void {
    var stack: [128]std.meta.Tag(Token) = undefined;
    var len: usize = 0;
    while (!self.empty()) {
        const tk = self.consume();
        switch (tk) {
            .function, .left_paren, .left_bracket, .left_brace => {
                if (len == stack.len) return error.NestingLimit;
                stack[len] = switch (tk) {
                    .function, .left_paren => .right_paren,
                    .left_bracket => .right_bracket,
                    else => .right_brace,
                };
                len += 1;
            },
            .right_paren, .right_bracket, .right_brace => {
                if (len != 0 and stack[len - 1] == std.meta.activeTag(tk)) len -= 1;
            },
            else => {},
        }
        if (len == 0) return;
    }
}

/// The opening token is at the cursor. EOF implicitly closes the block, as in
/// CSS Syntax. The parent advances past the closing token, if present.
pub fn block(self: *TokenStream) error{NestingLimit}!TokenStream {
    const opening = self.peek();
    const closing: std.meta.Tag(Token) = switch (opening) {
        .function, .left_paren => .right_paren,
        .left_bracket => .right_bracket,
        .left_brace => .right_brace,
        else => unreachable,
    };
    _ = self.consume();
    const start = self.index;
    // Skip nested components as units. A close belonging to a nested block at
    // EOF must remain inside this view, not be mistaken for our own close.
    while (!self.empty()) {
        if (std.meta.activeTag(self.peek()) == closing) {
            const end = self.index;
            _ = self.consume();
            return self.view(start, end);
        }
        try self.skipComponent();
    }
    return self.view(start, self.index);
}

const testing = std.testing;

test "CSS Token Stream: consumes discards and reaches conceptual EOF" {
    const items = [_]Token{
        .whitespace,
        .{ .ident = String.fromSource("a") },
    };
    var stream = TokenStream.init(testing.allocator, &items);
    defer stream.deinit();

    stream.discardWhitespace();
    try testing.expectEqual(1, stream.index);
    const ident = stream.consume().ident;
    try testing.expect(ident.eqlAscii("a"));
    try testing.expect(stream.empty());
    stream.discardToken();
    try testing.expectEqual(2, stream.index);
    try testing.expectEqual(std.meta.Tag(Token).eof, std.meta.activeTag(stream.consume()));
    try testing.expectEqual(3, stream.index);
}

test "CSS Token Stream: restores and discards nested marks" {
    const items = [_]Token{
        .colon,
        .semicolon,
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
    const items = [_]Token{
        .{ .ident = String.fromSource("color") },
        .colon,
        .{ .ident = String.fromSource("red") },
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

test "CSS Token Stream: block excludes its delimiters and preserves nested content" {
    const items = [_]Token{
        .left_paren,
        .left_bracket,
        .right_bracket,
        .right_paren,
        .semicolon,
    };
    var stream = TokenStream.init(testing.allocator, &items);
    defer stream.deinit();
    var content = try stream.block();
    defer content.deinit();

    try testing.expectEqual(2, content.tokens.len);
    try testing.expect(content.consume() == .left_bracket);
    try testing.expect(content.consume() == .right_bracket);
    try testing.expect(content.empty());
    try testing.expectEqual(4, stream.index);
    try testing.expect(stream.peek() == .semicolon);
}
