/// Temporary token storage. Source bytes are borrowed; decoded token strings
/// live in this buffer.
const Buffer = @This();

const std = @import("std");
const Token = @import("token.zig").Token;
const String = @import("String.zig");
const Tokenizer = @import("Tokenizer.zig");
const token = @import("token.zig");
const TokenStream = @import("TokenStream.zig");
const types = @import("types.zig");
const Span = types.Span;

arena: std.heap.ArenaAllocator,
items: []const Token,
spans: []const Span,
source: []const u8,

pub fn init(allocator: std.mem.Allocator, source: []const u8) !Buffer {
    if (source.len > std.math.maxInt(u32)) return error.InputTooLarge;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();
    var items: std.ArrayList(Token) = .empty;
    defer items.deinit(allocator);
    var spans: std.ArrayList(Span) = .empty;
    defer spans.deinit(allocator);
    while (true) {
        tokenizer.consumeComments();
        const start = tokenizer.position();
        const tk = tokenizer.consume(false);
        if (tk == .eof) break;
        try items.append(allocator, try token.cloneToken(alloc, tk));
        try spans.append(allocator, .{ .start = @intCast(start), .end = @intCast(tokenizer.position()) });
    }
    const retained_items = try alloc.dupe(Token, items.items);
    const retained_spans = try alloc.dupe(Span, spans.items);
    return .{
        .arena = arena,
        .items = retained_items,
        .spans = retained_spans,
        .source = source,
    };
}

pub fn deinit(self: *Buffer) void {
    self.arena.deinit();
}

pub fn stream(self: *const Buffer, allocator: std.mem.Allocator) TokenStream {
    return .{ .allocator = allocator, .tokens = self.items, .spans = self.spans, .source = self.source };
}
