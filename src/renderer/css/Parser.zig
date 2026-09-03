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

// https://drafts.csswg.org/css-syntax/#parse-declaration
pub fn parseDeclaration(self: *Parser) ParserError!results.Declaration {
    self.input.discardWhitespace();
    return (try self.consumeDeclaration(self.input, false)) orelse error.Syntax;
}

// https://drafts.csswg.org/css-syntax/#parse-component-value
pub fn parseComponentValue(self: *Parser) ParserError!results.ComponentValue {
    self.input.discardWhitespace();
    if (self.input.empty()) return error.Syntax;

    const value = try self.consumeComponentValue(self.input);
    self.input.discardWhitespace();
    if (!self.input.empty()) return error.Syntax;
    return value;
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
    var rules: std.ArrayList(results.Rule) = .empty;
    errdefer rules.deinit(self.allocator);

    while (true) switch (input.nextToken().*) {
        .token => |tk| switch (tk) {
            .whitespace, .cdo, .cdc => input.discardToken(),
            .eof => return rules.toOwnedSlice(self.allocator),
            .at_keyword => if (try self.consumeAtRule(input, false)) |rule|
                try rules.append(self.allocator, rule),
            else => if (try self.consumeQualifiedRule(input, false)) |rule|
                try rules.append(self.allocator, rule),
        },
        .component_value => if (try self.consumeQualifiedRule(input, false)) |rule|
            try rules.append(self.allocator, rule),
    };
}

// https://drafts.csswg.org/css-syntax/#consume-at-rule
fn consumeAtRule(
    self: *Parser,
    input: *TokenStream,
    nested: bool,
) ParserError!?results.Rule {
    const name = switch (input.consumeToken().*) {
        .token => |tk| switch (tk) {
            .at_keyword => |value| value,
            else => unreachable,
        },
        .component_value => unreachable,
    };

    var prelude: std.ArrayList(results.ComponentValue) = .empty;
    errdefer prelude.deinit(self.allocator);

    while (true) switch (input.nextToken().*) {
        .token => |tk| switch (tk) {
            .semicolon, .eof => {
                input.discardToken();
                return .{ .at_rule = .{
                    .name = name,
                    .prelude = try prelude.toOwnedSlice(self.allocator),
                } };
            },
            .right_brace => {
                if (nested) {
                    return .{ .at_rule = .{
                        .name = name,
                        .prelude = try prelude.toOwnedSlice(self.allocator),
                    } };
                }
                try prelude.append(self.allocator, input.consumeToken());
            },
            .left_brace => {
                const block = try self.consumeBlock(input);
                var rule: results.AtRule = .{
                    .name = name,
                    .prelude = try prelude.toOwnedSlice(self.allocator),
                };
                errdefer self.allocator.free(rule.prelude);
                try self.handleBlockItems(block, &rule);
                return .{ .at_rule = rule };
            },
            else => try prelude.append(self.allocator, try self.consumeComponentValue(input)),
        },
        .component_value => try prelude.append(
            self.allocator,
            try self.consumeComponentValue(input),
        ),
    };
}

// FIXME: This function should be optimized.
fn handleBlockItems(self: *Parser, block: []results.BlockItem, rule: *results.AtRule) std.mem.Allocator.Error!void {
    defer {
        for (block) |item| switch (item) {
            .declarations => |decls| self.allocator.free(decls),
            .rule => {},
        };
        self.allocator.free(block);
    }

    var decl_count: usize = 0;
    var child_rule_count: usize = 0;
    for (block) |item| switch (item) {
        .declarations => |decls| decl_count += decls.len,
        .rule => child_rule_count += 1,
    };

    const decls = try self.allocator.alloc(results.Declaration, decl_count);
    errdefer self.allocator.free(decls);
    const child_rules = try self.allocator.alloc(results.Rule, child_rule_count);
    errdefer self.allocator.free(child_rules);

    var decl_idx: usize = 0;
    var child_rule_index: usize = 0;
    for (block) |item| switch (item) {
        .declarations => |items| {
            @memcpy(decls[decl_idx..][0..items.len], items);
            decl_idx += items.len;
        },
        .rule => |child_rule| {
            child_rules[child_rule_index] = child_rule;
            child_rule_index += 1;
        },
    };

    rule.declarations = decls;
    rule.child_rules = child_rules;
}

// https://drafts.csswg.org/css-syntax/#consume-qualified-rule
fn consumeQualifiedRule(
    self: *Parser,
    input: *TokenStream,
    nested: bool,
) ParserError![]results.BlockItem {
    _ = self;
    _ = input;
    _ = nested;
    @panic("TODO CSS Syntax §5.5.3");
}

// https://drafts.csswg.org/css-syntax/#consume-block
fn consumeBlock(self: *Parser, input: *TokenStream) ParserError![]results.BlockItem {
    input.discardToken();
    const rules = try self.consumeBlockContents(input);
    input.discardToken();
    return rules;
}

// https://drafts.csswg.org/css-syntax/#consume-block-contents
fn consumeBlockContents(
    self: *Parser,
    input: *TokenStream,
) ParserError![]results.BlockItem {
    var rules: std.ArrayList(results.BlockItem) = .empty;
    errdefer rules.deinit(self.allocator);
    var decls: std.ArrayList(results.Declaration) = .empty;
    defer decls.deinit(self.allocator);

    while (true) switch (input.nextToken().*) {
        .token => |tk| switch (tk) {
            .whitespace, .semicolon => input.discardToken(),
            .eof, .right_brace => return rules.toOwnedSlice(self.allocator),
            .at_keyword => {
                try self.flushDeclarations(&rules, &decls);
                if (try self.consumeAtRule(input, true)) |rule|
                    try rules.append(self.allocator, .{ .rule = rule });
            },
            else => try self.consumeBlockContentItem(input, &rules, &decls),
        },
        .component_value => try self.consumeBlockContentItem(input, &rules, &decls),
    };
}

fn consumeBlockContentItem(
    self: *Parser,
    input: *TokenStream,
    rules: *std.ArrayList(results.BlockItem),
    decls: *std.ArrayList(results.Declaration),
) ParserError!void {
    try input.mark();
    const declaration = self.consumeDeclaration(input, true) catch |err| {
        input.restoreMark() catch unreachable;
        return err;
    };

    if (declaration) |decl| {
        input.discardMark() catch unreachable;
        try decls.append(self.allocator, decl);
        return;
    }

    input.restoreMark() catch unreachable;
    const rule = self.consumeQualifiedRule(input, .semicolon, true) catch |err| switch (err) {
        error.InvalidRule => {
            try self.flushDeclarations(rules, decls);
            return;
        },
        else => return err,
    };

    if (rule) |parsed| {
        try self.flushDeclarations(rules, decls);
        try rules.append(self.allocator, .{ .rule = parsed });
    }
}

fn flushDeclarations(
    self: *Parser,
    rules: *std.ArrayList(results.BlockItem),
    declarations: *std.ArrayList(results.Declaration),
) std.mem.Allocator.Error!void {
    if (declarations.items.len == 0) return;

    const owned = try declarations.toOwnedSlice(self.allocator);
    errdefer self.allocator.free(owned);
    try rules.append(self.allocator, .{ .declarations = owned });
}

// https://drafts.csswg.org/css-syntax/#consume-declaration
fn consumeDeclaration(
    self: *Parser,
    input: *TokenStream,
    nested: bool,
) ParserError!?results.Declaration {
    _ = self;
    _ = input;
    _ = nested;
    @panic("TODO CSS Syntax §5.5.6");
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

// https://drafts.csswg.org/css-syntax/#consume-component-value
fn consumeComponentValue(
    self: *Parser,
    input: *TokenStream,
) ParserError!results.ComponentValue {
    _ = self;
    _ = input;
    @panic("TODO CSS Syntax §5.5.8");
}
