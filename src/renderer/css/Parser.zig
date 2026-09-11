const Parser = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const TokenStream = @import("TokenStream.zig");
const Item = TokenStream.Item;
const token = @import("token.zig");
const Token = token.Token;
const cloneToken = token.cloneToken;
const results = @import("parsing_results.zig");
const ascii = @import("../utils/ascii.zig");
const CssString = @import("String.zig");

pub const ParserError =
    std.mem.Allocator.Error ||
    TokenStream.SourceMapError ||
    error{ Syntax, InvalidRule, InputTooLarge };

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
            (try self.consumeQualifiedRule(self.input, null, false)) orelse return error.Syntax,
        .component_value => (try self.consumeQualifiedRule(self.input, null, false)) orelse
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
    return self.consumeListOfComponentValues(self.input, null, false);
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
            else => if (try self.consumeQualifiedRule(input, null, false)) |rule|
                try rules.append(self.allocator, rule),
        },
        .component_value => if (try self.consumeQualifiedRule(input, null, false)) |rule|
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
                input.discardToken();
                try prelude.append(self.allocator, .{ .preserved_token = .right_brace });
            },
            .left_brace => {
                const block = try self.consumeBlock(input);
                var rule: results.AtRule = .{
                    .name = name,
                    .prelude = try prelude.toOwnedSlice(self.allocator),
                };
                errdefer self.allocator.free(rule.prelude);
                try self.materializeAtRuleRuleBlock(block, &rule);
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
fn materializeAtRuleRuleBlock(self: *Parser, block: []results.BlockItem, rule: *results.AtRule) std.mem.Allocator.Error!void {
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
    stop: ?StopToken,
    nested: bool,
) ParserError!?results.Rule {
    var prelude: std.ArrayList(results.ComponentValue) = .empty;
    defer prelude.deinit(self.allocator);

    while (true) {
        const item = input.nextToken();
        switch (item.*) {
            .token => |tk| {
                if (tk == .eof or isStopToken_O(tk, stop)) {
                    return null;
                }

                switch (tk) {
                    .right_brace => {
                        if (nested) return null;
                        input.discardToken();
                        try prelude.append(self.allocator, .{ .preserved_token = .right_brace });
                    },
                    .left_brace => {
                        if (startsCustomPropertyDeclaration(prelude.items)) {
                            if (nested) {
                                try self.consumeBadDeclarationRemnants(input, true);
                            } else {
                                const discarded = try self.consumeBlock(input);
                                self.freeBlockItems(discarded);
                            }
                            return null;
                        }

                        const block = try self.consumeBlock(input);
                        var rule: results.QualifiedRule = .{
                            .prelude = try prelude.toOwnedSlice(self.allocator),
                        };
                        errdefer self.allocator.free(rule.prelude);
                        try self.materializeQualifiedRuleBlock(block, &rule);
                        return .{ .qualified_rule = rule };
                    },
                    else => try prelude.append(
                        self.allocator,
                        try self.consumeComponentValue(input),
                    ),
                }
            },
            .component_value => try prelude.append(
                self.allocator,
                try self.consumeComponentValue(input),
            ),
        }
    }
}

inline fn isStopToken_O(tk: Token, stop: ?StopToken) bool {
    const value = stop orelse return false;
    return switch (value) {
        .comma => tk == .comma,
        .semicolon => tk == .semicolon,
    };
}

/// A custom property declaration starts with an identifier whose name begins
/// with `--`, followed by optional whitespace and a colon.
/// For example: `--foo: value`
fn startsCustomPropertyDeclaration(prelude: []const results.ComponentValue) bool {
    var first: ?results.PreservedToken = null;
    var second: ?results.PreservedToken = null;

    for (prelude) |value| {
        const preserved = switch (value) {
            .preserved_token => |tk| tk,
            else => return false,
        };
        if (preserved == .whitespace) continue;
        if (first == null) {
            first = preserved;
        } else {
            second = preserved;
            break;
        }
    }

    const name = switch (first orelse return false) {
        .ident => |value| value,
        else => return false,
    };
    if (!name.startsWith("--")) return false;
    return (second orelse return false) == .colon;
}

// FIXME: This function should be optimized.
fn materializeQualifiedRuleBlock(
    self: *Parser,
    block: []results.BlockItem,
    rule: *results.QualifiedRule,
) std.mem.Allocator.Error!void {
    errdefer self.freeBlockItems(block);

    var first_child: usize = 0;
    if (block.len > 0) switch (block[0]) {
        .declarations => |declarations| {
            rule.declarations = declarations;
            first_child = 1;
        },
        .rule => {},
    };

    const child_rules = try self.allocator.alloc(results.Rule, block.len - first_child);
    errdefer self.allocator.free(child_rules);

    for (block[first_child..], child_rules) |item, *child| {
        child.* = switch (item) {
            .rule => |child_rule| child_rule,
            .declarations => |declarations| .{ .qualified_rule = .{
                .declarations = declarations,
            } },
        };
    }

    self.allocator.free(block);
    rule.child_rules = child_rules;
}

fn freeBlockItems(self: *Parser, block: []results.BlockItem) void {
    for (block) |item| switch (item) {
        .declarations => |declarations| self.allocator.free(declarations),
        .rule => {},
    };
    self.allocator.free(block);
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
            .eof, .right_brace => {
                try self.flushDeclarations(&rules, &decls);
                return rules.toOwnedSlice(self.allocator);
            },
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
    const name = switch (input.nextToken().*) {
        .token => |tk| switch (tk) {
            .ident => |value| value,
            else => {
                try self.consumeBadDeclarationRemnants(input, nested);
                return null;
            },
        },
        .component_value => {
            try self.consumeBadDeclarationRemnants(input, nested);
            return null;
        },
    };
    input.discardToken();

    input.discardWhitespace();
    switch (input.nextToken().*) {
        .token => |tk| if (tk == .colon) input.discardToken() else {
            try self.consumeBadDeclarationRemnants(input, nested);
            return null;
        },
        .component_value => {
            try self.consumeBadDeclarationRemnants(input, nested);
            return null;
        },
    }

    const value_start = input.index;
    var value = try self.consumeListOfComponentValues(
        input,
        if (nested) .semicolon else null,
        nested,
    );
    errdefer self.allocator.free(value);
    const value_end = input.index;

    var important = false;
    var last_non_ws: ?usize = null;
    var snd_last_non_ws: ?usize = null;
    var index = value.len;
    while (index > 0 and snd_last_non_ws == null) {
        index -= 1;
        if (isWhitespaceComponentValue(value[index])) continue;
        if (last_non_ws == null)
            last_non_ws = index
        else
            snd_last_non_ws = index;
    }

    var important_start: ?usize = null;
    if (last_non_ws) |last| if (snd_last_non_ws) |second_last| {
        if (isImportant(value[last]) and isBang(value[second_last])) {
            important = true;
            important_start = second_last;
        }
    };

    if (important_start) |start| value = try self.allocator.realloc(value, start);

    const custom_property = name.startsWith("--");
    const original_text = input.originalText(value_start, value_end);
    if (!custom_property and containsInvalidTopLevelBrace(value)) {
        self.allocator.free(value);
        return null;
    }

    if (!custom_property and name.eqlAscii("unicode-range")) {
        if (original_text) |text| {
            const unicode_ranges = try self.consumeUnicodeRangeValue(text);
            self.allocator.free(value);
            value = unicode_ranges;
        }
    }

    return .{
        .name = name,
        .value = value,
        .important = important,
        .original_text = if (custom_property)
            if (original_text) |text| results.String.fromSource(text) else null
        else
            null,
    };
}

// https://drafts.csswg.org/css-syntax/#consume-the-remnants-of-a-bad-declaration
fn consumeBadDeclarationRemnants(
    self: *Parser,
    input: *TokenStream,
    nested: bool,
) ParserError!void {
    while (true) switch (input.nextToken().*) {
        .token => |tk| switch (tk) {
            .eof, .semicolon => {
                input.discardToken();
                return;
            },
            .right_brace => {
                if (nested) return;
                input.discardToken();
            },
            else => _ = try self.consumeComponentValue(input),
        },
        .component_value => _ = try self.consumeComponentValue(input),
    };
}

inline fn isWhitespaceComponentValue(value: results.ComponentValue) bool {
    return switch (value) {
        .preserved_token => |tk| tk == .whitespace,
        else => false,
    };
}

inline fn isBang(value: results.ComponentValue) bool {
    return switch (value) {
        .preserved_token => |tk| switch (tk) {
            .delim => |cp| cp == '!',
            else => false,
        },
        else => false,
    };
}

inline fn isImportant(value: results.ComponentValue) bool {
    return switch (value) {
        .preserved_token => |tk| switch (tk) {
            .ident => |name| name.eqlAscii("important"),
            else => false,
        },
        else => false,
    };
}

fn containsInvalidTopLevelBrace(value: []const results.ComponentValue) bool {
    var non_whitespace: usize = 0;
    var has_brace = false;
    for (value) |item| {
        if (isWhitespaceComponentValue(item)) continue;
        non_whitespace += 1;
        if (item == .simple_block and item.simple_block.associated_token == .left_brace)
            has_brace = true;
    }
    return has_brace and non_whitespace > 1;
}

// https://drafts.csswg.org/css-syntax/#consume-list-of-components
fn consumeListOfComponentValues(
    self: *Parser,
    input: *TokenStream,
    stop: ?StopToken,
    nested: bool,
) ParserError![]results.ComponentValue {
    var values: std.ArrayList(results.ComponentValue) = .empty;
    errdefer values.deinit(self.allocator);

    while (true) switch (input.nextToken().*) {
        .token => |tk| {
            if (tk == .eof or isStopToken_O(tk, stop))
                return values.toOwnedSlice(self.allocator);

            if (tk == .right_brace and nested)
                return values.toOwnedSlice(self.allocator);

            try values.append(self.allocator, try self.consumeComponentValue(input));
        },
        .component_value => try values.append(
            self.allocator,
            try self.consumeComponentValue(input),
        ),
    };
}

// https://drafts.csswg.org/css-syntax/#consume-component-value
fn consumeComponentValue(
    self: *Parser,
    input: *TokenStream,
) ParserError!results.ComponentValue {
    return switch (input.nextToken().*) {
        .component_value => input.consumeToken().component_value,
        .token => |tk| switch (tk) {
            .left_brace, .left_bracket, .left_paren => .{
                .simple_block = try self.consumeSimpleBlock(input),
            },
            .function => .{ .function = try self.consumeFunction(input) },
            else => .{ .preserved_token = results.preservedToken(input.consumeToken().token) },
        },
    };
}

// https://drafts.csswg.org/css-syntax/#consume-simple-block
fn consumeSimpleBlock(
    self: *Parser,
    input: *TokenStream,
) ParserError!results.SimpleBlock {
    const opening = input.nextToken().token;
    const associated_tk: results.BlockToken, const ending: Token = switch (opening) {
        .left_brace => .{ .left_brace, .right_brace },
        .left_bracket => .{ .left_bracket, .right_bracket },
        .left_paren => .{ .left_paren, .right_paren },
        else => unreachable,
    };
    input.discardToken();

    var value: std.ArrayList(results.ComponentValue) = .empty;
    errdefer value.deinit(self.allocator);
    while (true) switch (input.nextToken().*) {
        .token => |tk| if (tk == .eof or std.meta.activeTag(tk) == std.meta.activeTag(ending)) {
            input.discardToken();
            return .{
                .associated_token = associated_tk,
                .value = try value.toOwnedSlice(self.allocator),
            };
        } else try value.append(self.allocator, try self.consumeComponentValue(input)),
        .component_value => try value.append(
            self.allocator,
            try self.consumeComponentValue(input),
        ),
    };
}

// https://drafts.csswg.org/css-syntax/#consume-function
fn consumeFunction(
    self: *Parser,
    input: *TokenStream,
) ParserError!results.Function {
    const name = input.nextToken().token.function;
    input.discardToken();

    var value: std.ArrayList(results.ComponentValue) = .empty;
    errdefer value.deinit(self.allocator);
    while (true) switch (input.nextToken().*) {
        .token => |tk| if (tk == .eof or tk == .right_paren) {
            input.discardToken();
            return .{
                .name = name,
                .value = try value.toOwnedSlice(self.allocator),
            };
        } else try value.append(self.allocator, try self.consumeComponentValue(input)),
        .component_value => try value.append(
            self.allocator,
            try self.consumeComponentValue(input),
        ),
    };
}

// https://drafts.csswg.org/css-syntax/#consume-unicode-range-value
fn consumeUnicodeRangeValue(
    self: *Parser,
    input: []const u8,
) ParserError![]results.ComponentValue {
    var tokenizer = Tokenizer.init(self.allocator, input);
    defer tokenizer.deinit();
    return self.consumeTokenizerValues(&tokenizer, null);
}

const TokenTag = std.meta.Tag(Token);

fn consumeTokenizerValues(
    self: *Parser,
    tokenizer: *Tokenizer,
    ending: ?TokenTag,
) ParserError![]results.ComponentValue {
    var values: std.ArrayList(results.ComponentValue) = .empty;
    errdefer {
        for (values.items) |value| self.freeOwnedComponentValue(value);
        values.deinit(self.allocator);
    }

    while (true) {
        const tk = tokenizer.consume(true);
        const tag = std.meta.activeTag(tk);
        if (tag == .eof or (if (ending) |end| tag == end else false))
            return values.toOwnedSlice(self.allocator);

        const value = try self.consumeTokenizerComponentValue(tokenizer, tk);
        values.append(self.allocator, value) catch |err| {
            self.freeOwnedComponentValue(value);
            return err;
        };
    }
}

fn consumeTokenizerComponentValue(
    self: *Parser,
    tokenizer: *Tokenizer,
    tk: Token,
) ParserError!results.ComponentValue {
    return switch (tk) {
        .left_brace => .{ .simple_block = .{
            .associated_token = .left_brace,
            .value = try self.consumeTokenizerValues(tokenizer, .right_brace),
        } },
        .left_bracket => .{ .simple_block = .{
            .associated_token = .left_bracket,
            .value = try self.consumeTokenizerValues(tokenizer, .right_bracket),
        } },
        .left_paren => .{ .simple_block = .{
            .associated_token = .left_paren,
            .value = try self.consumeTokenizerValues(tokenizer, .right_paren),
        } },
        .function => |name| blk: {
            const owned_name = try name.cloneDecoded(self.allocator);
            errdefer owned_name.freeDecoded(self.allocator);
            break :blk .{ .function = .{
                .name = owned_name,
                .value = try self.consumeTokenizerValues(tokenizer, .right_paren),
            } };
        },
        .eof => unreachable,
        else => .{ .preserved_token = results.preservedToken(try cloneToken(self.allocator, tk)) },
    };
}

fn freeOwnedComponentValue(self: *Parser, value: results.ComponentValue) void {
    switch (value) {
        .preserved_token => |tk| switch (tk) {
            .ident,
            .at_keyword,
            .string,
            .url,
            => |text| text.freeDecoded(self.allocator),
            .hash => |hash| hash.value.freeDecoded(self.allocator),
            .dimension => |dimension| dimension.unit.freeDecoded(self.allocator),
            else => {},
        },
        .function => |function| {
            function.name.freeDecoded(self.allocator);
            for (function.value) |child| self.freeOwnedComponentValue(child);
            self.allocator.free(function.value);
        },
        .simple_block => |block| {
            for (block.value) |child| self.freeOwnedComponentValue(child);
            self.allocator.free(block.value);
        },
    }
}

/// Represents the An+B type.
pub const Nth = struct {
    a: i32,
    b: i32,
};

// https://drafts.csswg.org/css-syntax/#anb-production
pub fn parseNth(self: *Parser) ParserError!Nth {
    self.input.discardWhitespace();

    const first = item2Token(self.input.consumeToken()) orelse return error.Syntax;
    const result: Nth = switch (first) {
        .ident => |name| blk: {
            if (name.eqlAscii("odd")) break :blk .{ .a = 2, .b = 1 };
            if (name.eqlAscii("even")) break :blk .{ .a = 2, .b = 0 };
            break :blk try self.parseNthIdent(name, false);
        },
        .number => |num| .{
            .a = 0,
            .b = integerValue(num.value, num.type_flag) orelse return error.Syntax,
        },
        .dimension => |dim| try self.parseNthDimension(
            dim.value,
            dim.type_flag,
            dim.unit,
        ),
        .delim => |delimiter| blk: {
            if (delimiter != '+') return error.Syntax;

            // The grammar permits no whitespace between this optional '+' and
            // the following ident token.
            const name = switch (item2Token(self.input.consumeToken()) orelse return error.Syntax) {
                .ident => |name| name,
                else => return error.Syntax,
            };
            break :blk try self.parseNthIdent(name, true);
        },
        else => return error.Syntax,
    };

    self.input.discardWhitespace();
    if (!self.input.empty()) return error.Syntax;
    return result;
}

fn integerValue(value: f64, type_flag: token.NumberType) ?i32 {
    if (type_flag != .integer or !std.math.isFinite(value)) return null;
    if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
    return @intFromFloat(value);
}

inline fn item2Token(item: *const Item) ?Token {
    return switch (item.*) {
        .token => |tk| tk,
        .component_value => null,
    };
}

fn parseNthIdent(self: *Parser, name: CssString, after_plus: bool) ParserError!Nth {
    if (name.eqlAscii("n"))
        return .{ .a = 1, .b = try self.parseNthOffset(false) };
    if (!after_plus and name.eqlAscii("-n"))
        return .{ .a = -1, .b = try self.parseNthOffset(false) };
    if (name.eqlAscii("n-"))
        return .{ .a = 1, .b = try self.parseNthOffset(true) };
    if (!after_plus and name.eqlAscii("-n-"))
        return .{ .a = -1, .b = try self.parseNthOffset(true) };
    if (parseNDashDigits(name, false)) |b| return .{ .a = 1, .b = b };
    if (!after_plus) if (parseNDashDigits(name, true)) |b| return .{ .a = -1, .b = b };
    return error.Syntax;
}

fn parseNthDimension(
    self: *Parser,
    value: f64,
    type_flag: token.NumberType,
    unit: CssString,
) ParserError!Nth {
    const a = integerValue(value, type_flag) orelse return error.Syntax;
    if (unit.eqlAscii("n"))
        return .{ .a = a, .b = try self.parseNthOffset(false) };
    if (unit.eqlAscii("n-"))
        return .{ .a = a, .b = try self.parseNthOffset(true) };
    if (parseNDashDigits(unit, false)) |b|
        return .{ .a = a, .b = b };
    return error.Syntax;
}

fn parseNthOffset(self: *Parser, signless: bool) ParserError!i32 {
    self.input.discardWhitespace();
    const tk = item2Token(self.input.consumeToken()) orelse return if (signless) error.Syntax else 0;
    if (tk == .eof) return if (signless) error.Syntax else 0;

    if (tk == .number) {
        const number = tk.number;
        const value = integerValue(number.value, number.type_flag) orelse return error.Syntax;
        if (signless) {
            if (number.sign != null) return error.Syntax;
            return std.math.negate(value) catch return error.Syntax;
        }
        if (number.sign == null) return error.Syntax;
        return value;
    }

    if (!signless and tk == .delim and (tk.delim == '+' or tk.delim == '-')) {
        const negative = tk.delim == '-';
        self.input.discardWhitespace();
        const number = switch (item2Token(self.input.consumeToken()) orelse return error.Syntax) {
            .number => |number| number,
            else => return error.Syntax,
        };
        if (number.sign != null) return error.Syntax;
        const value = integerValue(number.value, number.type_flag) orelse return error.Syntax;
        // Use negate to catch overflow error.
        return if (negative) std.math.negate(value) catch return error.Syntax else value;
    }

    return error.Syntax;
}

fn parseNDashDigits(value: CssString, leading_dash: bool) ?i32 {
    const prefix_len: usize = if (leading_dash) 3 else 2;
    if (value.len() <= prefix_len) return null;
    if (leading_dash and value.codePoint(0) != '-') return null;

    const n_index: usize = if (leading_dash) 1 else 0;
    const n = value.codePoint(n_index) orelse return null;
    if (n != 'n' and n != 'N') return null;
    if (value.codePoint(n_index + 1) != '-') return null;

    var result: i32 = 0;
    var i = prefix_len;
    while (i < value.len()) : (i += 1) {
        const cp = value.codePoint(i) orelse return null;
        if (cp < '0' or cp > '9') return null;
        result = std.math.mul(i32, result, 10) catch return null;
        result = std.math.add(i32, result, @intCast(cp - '0')) catch return null;
    }
    return std.math.negate(result) catch null;
}
