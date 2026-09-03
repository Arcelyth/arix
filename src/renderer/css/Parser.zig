const Parser = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const TokenStream = @import("TokenStream.zig");
const Item = TokenStream.Item;
const Token = @import("token.zig").Token;
const token = @import("token.zig");
const results = @import("parsing_results.zig");
const ComponentValue = results.ComponentValue;

pub const ParserError =
    std.mem.Allocator.Error ||
    TokenStream.SourceMapError ||
    error{ Syntax, InputTooLarge };

pub const Input = union(enum) {
    token_stream: *TokenStream,
    items: []const Item,
    string: []const u8,
};

allocator: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator) Parser {
    return .{ .allocator = alloc };
}

// https://drafts.csswg.org/css-syntax/#parse-grammar
pub fn parseAccordingToGrammar(
    self: *Parser,
    input: Input,
    comptime T: type,
    comptime match: fn ([]const ComponentValue) ?T,
) ParserError!?T {
    const values = try self.parseListOfComponentValues(input);
    return match(values);
}

// https://drafts.csswg.org/css-syntax/#parse-list-of-component-values
pub fn parseListOfComponentValues(self: *Parser, input: Input) ParserError![]ComponentValue {
    var normalized = try self.normalize(input);
    defer normalized.deinit();
    return self.consumeListOfComponentValues(normalized.stream());
}

/// `borrowed` refers to an existing stream and does not own it.
/// `owned` contains a stream created during normalization and owns it.
const Normalized = union(enum) {
    borrowed: *TokenStream,
    owned: TokenStream,

    fn stream(self: *Normalized) *TokenStream {
        return switch (self.*) {
            .borrowed => |value| value,
            .owned => |*value| value,
        };
    }

    fn deinit(self: *Normalized) void {
        switch (self.*) {
            .borrowed => {},
            .owned => |*value| value.deinit(),
        }
    }
};

fn normalize(self: *Parser, input: Input) ParserError!Normalized {
    return switch (input) {
        .token_stream => |stream| .{ .borrowed = stream },
        .items => |items| .{ .owned = TokenStream.init(self.allocator, items) },
        .string => |string| .{ .owned = try self.tokenize(string) },
    };
}

fn tokenize(self: *Parser, source: []const u8) ParserError!TokenStream {
    if (source.len > std.math.maxInt(u32)) return error.InputTooLarge;
    var tokenizer = Tokenizer.init(self.allocator, source);
    defer tokenizer.deinit();
    var items: std.ArrayList(Item) = .empty;
    var spans: std.ArrayList(TokenStream.Span) = .empty;

    while (true) {
        const start = tokenizer.position();
        const value = tokenizer.consume(false);
        const end = tokenizer.position();
        if (value == .eof) break;
        try items.append(self.allocator, .{ .token = try self.cloneToken(value) });
        try spans.append(self.allocator, .{ .start = @intCast(start), .end = @intCast(end) });
    }
    return try TokenStream.initWithSource(
        self.allocator,
        try items.toOwnedSlice(self.allocator),
        source,
        try spans.toOwnedSlice(self.allocator),
    );
}

inline fn cloneText(self: *Parser, value: []const u21) ParserError![]const u21 {
    return self.allocator.dupe(u21, value);
}

inline fn cloneToken(self: *Parser, value: Token) ParserError!Token {
    return switch (value) {
        .ident => |v| .{ .ident = try self.cloneText(v) },
        .function => |v| .{ .function = try self.cloneText(v) },
        .at_keyword => |v| .{ .at_keyword = try self.cloneText(v) },
        .hash => |v| .{ .hash = .{ .value = try self.cloneText(v.value), .type_flag = v.type_flag } },
        .string => |v| .{ .string = try self.cloneText(v) },
        .url => |v| .{ .url = try self.cloneText(v) },
        .dimension => |v| .{ .dimension = .{
            .value = v.value,
            .sign = v.sign,
            .type_flag = v.type_flag,
            .unit = try self.cloneText(v.unit),
        } },
        else => value,
    };
}

// https://drafts.csswg.org/css-syntax/#consume-list-of-components
fn consumeListOfComponentValues(
    self: *Parser,
    stream: *TokenStream,
) ParserError![]results.ComponentValue {
    _ = self;
    _ = stream;
}
