const Parser = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const TokenStream = @import("TokenStream.zig");
const Item = TokenStream.Item;
const Token = @import("token.zig").Token;
const token = @import("token.zig");
const results = @import("parsing_results.zig");

pub const ParserError =
    std.mem.Allocator.Error ||
    TokenStream.SourceMapError ||
    error{ Syntax, InputTooLarge };

allocator: std.mem.Allocator,
input: *TokenStream,

pub fn init(alloc: std.mem.Allocator, input: *TokenStream) Parser {
    return .{
        .allocator = alloc,
        .input = input,
    };
}

// https://drafts.csswg.org/css-syntax/#parse-grammar
pub fn parseSomething(
    self: *Parser,
    comptime T: type,
    comptime parse: fn ([]const results.ComponentValue) ?T,
) ParserError!?T {
    return parse(try self.parseListOfComponentValues());
}

// https://drafts.csswg.org/css-syntax/#parse-comma-list
pub fn parseCommaSeparatedList(
    self: *Parser,
    comptime T: type,
    comptime parse: fn ([]const results.ComponentValue) ?T,
) ParserError![]?T {
    const start = self.input.index;
    self.input.discardWhitespace();
    if (self.input.empty()) {
        return self.allocator.alloc(?T, 0);
    }
    self.input.index = start;

    const groups = try self.parseCommaSeparatedListOfComponentValues();
    defer self.allocator.free(groups);

    const list = try self.allocator.alloc(?T, groups.len);
    for (groups, list) |group, *result| result.* = parse(group);
    return list;
}

// https://drafts.csswg.org/css-syntax/#parse-stylesheet
pub fn parseStylesheet(self: *Parser) ParserError!results.Stylesheet {
    return .{ .rules = try self.consumeStylesheetContents(self.input) };
}

// https://drafts.csswg.org/css-syntax/#parse-stylesheet-contents
pub fn parseStylesheetContents(self: *Parser) ParserError![]results.Rule {
    return self.consumeStylesheetContents(self.input);
}

// https://drafts.csswg.org/css-syntax/#parse-block-contents
pub fn parseBlockContents(self: *Parser) ParserError![]results.BlockItem {
    return self.consumeBlockContents(self.input);
}

// https://drafts.csswg.org/css-syntax/#parse-rule
pub fn parseRule(self: *Parser) ParserError!results.Rule {
    self.input.discardWhitespace();
    if (self.input.empty()) return error.Syntax;

    const rule = switch (self.input.nextToken().*) {
        .token => |tk| if (tk == .at_keyword)
            (try self.consumeAtRule(self.input, false)) orelse return error.Syntax
        else
            (try self.consumeQualifiedRule(self.input, false)) orelse return error.Syntax,
        .component_value => (try self.consumeQualifiedRule(self.input, false)) orelse
            return error.Syntax,
    };

    self.input.discardWhitespace();
    if (!self.input.empty()) return error.Syntax;
    return rule;
}

// https://drafts.csswg.org/css-syntax/#parse-list-of-component-values
pub fn parseListOfComponentValues(self: *Parser) ParserError![]results.ComponentValue {
    return self.consumeListOfComponentValues(self.input);
}

// https://drafts.csswg.org/css-syntax/#parse-comma-separated-list-of-component-values
pub fn parseCommaSeparatedListOfComponentValues(self: *Parser) ParserError![][]results.ComponentValue {
    var groups: std.ArrayList([]results.ComponentValue) = .empty;
    errdefer groups.deinit(self.allocator);

    while (!self.input.empty()) {
        try groups.append(
            self.allocator,
            try self.consumeListOfComponentValues(self.input, .comma, false),
        );
        self.input.discardToken();
    }
    return groups.toOwnedSlice(self.allocator);
}

const StopToken = enum { comma, semicolon };

// https://drafts.csswg.org/css-syntax/#consume-stylesheet-contents
fn consumeStylesheetContents(
    self: *Parser,
    input: *TokenStream,
) ParserError![]results.Rule {
    _ = self;
    _ = input;
    @panic("TODO CSS Syntax §5.5.1");
}

// https://drafts.csswg.org/css-syntax/#consume-at-rule
fn consumeAtRule(
    self: *Parser,
    input: *TokenStream,
    nested: bool,
) ParserError!?results.Rule {
    _ = self;
    _ = input;
    _ = nested;
    @panic("TODO CSS Syntax §5.5.2");
}

// https://drafts.csswg.org/css-syntax/#consume-qualified-rule
fn consumeQualifiedRule(
    self: *Parser,
    input: *TokenStream,
    nested: bool,
) ParserError!?results.Rule {
    _ = self;
    _ = input;
    _ = nested;
    @panic("TODO CSS Syntax §5.5.3");
}

// https://drafts.csswg.org/css-syntax/#consume-block-contents
fn consumeBlockContents(
    self: *Parser,
    input: *TokenStream,
) ParserError![]results.BlockItem {
    _ = self;
    _ = input;
    @panic("TODO CSS Syntax §5.5.5");
}

// https://drafts.csswg.org/css-syntax/#consume-list-of-components
fn consumeListOfComponentValues(
    self: *Parser,
    stream: *TokenStream,
    stop: ?Token,
    nested: bool,
) ParserError![]results.ComponentValue {
    _ = self;
    _ = stream;
    _ = stop;
    _ = nested;
    @panic("TODO CSS Syntax §5.5.7");
}
