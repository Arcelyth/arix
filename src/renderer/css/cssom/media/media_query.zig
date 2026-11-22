//! Parses media types, conditions, and features.
const std = @import("std");
const syntax = @import("../../syntax.zig");
const String = @import("../../String.zig");
const MediaQuery = @import("MediaQuery.zig");

const Condition = MediaQuery.Condition;
const Value = MediaQuery.Value;
const Feature = MediaQuery.Feature;
const Stream = syntax.TokenStream;
const Output = std.Io.Writer.Allocating;
const Allocator = std.mem.Allocator;
const Queries = std.ArrayList(MediaQuery);

const ParseError = error{
    InvalidQuery,
    NestingLimit,
    OutOfMemory,
    WriteFailed,
};

const Keyword = enum {
    not,
    only,
    @"and",
    @"or",
    layer,
};

/// Parses comma-separated queries. Each invalid entry becomes "not all".
pub fn parseList(allocator: Allocator, text: []const u8) !Queries {
    var buffer = try syntax.Buffer.init(allocator, text);
    defer buffer.deinit();
    var input = buffer.stream(allocator);
    input.discardWhitespace();

    var result: Queries = .empty;
    if (input.empty()) return result;
    errdefer {
        for (result.items) |*entry| entry.deinit();
        result.deinit(allocator);
    }
    while (true) {
        const start = input.index;
        while (!input.empty() and input.peek() != .comma) try input.skipComponent();
        var entry = input.view(start, input.index);
        try result.ensureUnusedCapacity(allocator, 1);
        result.appendAssumeCapacity(try parseEntry(allocator, &entry));
        if (input.empty()) break;
        input.discardToken();
    }
    return result;
}

/// Returns null for an empty list or a list of multiple queries.
pub fn parseOne(allocator: Allocator, text: []const u8) !?MediaQuery {
    var list = try parseList(allocator, text);
    defer list.deinit(allocator);
    if (list.items.len == 1) return list.items[0];
    for (list.items) |*entry| entry.deinit();
    return null;
}

fn parseEntry(allocator: Allocator, input: *Stream) !MediaQuery {
    var query = MediaQuery{ .arena = .init(allocator) };
    errdefer query.deinit();
    input.discardWhitespace();
    parseQuery(&query, input) catch |err| switch (err) {
        error.InvalidQuery => {
            query.deinit();
            return .{
                .arena = .init(allocator),
                .modifier = .not,
            };
        },
        else => return err,
    };
    return query;
}

fn keyword(input: *const Stream) ?Keyword {
    const token = input.peek();
    if (token != .ident) return null;
    inline for (@typeInfo(Keyword).@"enum".field_names) |name| {
        if (token.ident.eqlAscii(name)) return @field(Keyword, name);
    }
    return null;
}

fn advance(input: *Stream) void {
    input.discardToken();
    input.discardWhitespace();
}

fn anyValue(input: *Stream) error{NestingLimit}!bool {
    while (!input.empty()) switch (input.peek()) {
        .right_brace, .right_bracket, .right_paren, .bad_string, .bad_url => return false,
        .left_brace, .left_bracket, .left_paren, .function => {
            var block = try input.block();
            if (!try anyValue(&block)) return false;
        },
        else => input.discardToken(),
    };
    return true;
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-media-query
fn parseQuery(query: *MediaQuery, input: *Stream) !void {
    const allocator = query.arena.allocator();
    var typed = input.*;
    const modifier = keyword(&typed);
    if (modifier == .not or modifier == .only) advance(&typed);
    if (typed.peek() != .ident) {
        query.condition = try parseCondition(allocator, input, true);
        return;
    }
    if (keyword(&typed) != null) return error.InvalidQuery;
    if (modifier == .not) query.modifier = .not;
    if (modifier == .only) query.modifier = .only;
    query.media_type = try lowerName(allocator, typed.peek().ident);
    advance(&typed);

    if (typed.empty()) return;
    if (keyword(&typed) != .@"and") return error.InvalidQuery;
    advance(&typed);
    query.condition = try parseCondition(allocator, &typed, false);
}

fn lowerName(allocator: Allocator, name: String) ![]const u8 {
    var bytes: Output = .init(allocator);
    defer bytes.deinit();
    switch (name.value) {
        .borrowed => |value| try bytes.writer.writeAll(value),
        .owned => |points| for (points) |cp| try bytes.writer.print("{u}", .{cp}),
    }
    for (bytes.written()) |*byte|
        byte.* = std.ascii.toLower(byte.*);
    return bytes.toOwnedSlice();
}

fn child(allocator: Allocator, condition: Condition) !*const Condition {
    const node = try allocator.create(Condition);
    node.* = condition;
    return node;
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-media-condition
fn parseCondition(allocator: Allocator, input: *Stream, allow_or: bool) ParseError!Condition {
    if (keyword(input) == .not) {
        advance(input);
        const inner = try parseParens(allocator, input);
        if (!input.empty()) return error.InvalidQuery;
        return .{
            .not = try child(allocator, inner),
        };
    }
    const first = try parseParens(allocator, input);
    if (input.empty()) return first;
    const op = keyword(input);
    if (op != .@"and" and !(allow_or and op == .@"or")) return error.InvalidQuery;
    var terms: std.ArrayList(Condition) = .empty;
    try terms.append(allocator, first);

    while (!input.empty()) {
        if (keyword(input) != op) return error.InvalidQuery;
        advance(input);
        try terms.append(allocator, try parseParens(allocator, input));
    }
    return if (op == .@"and")
        .{ .@"and" = terms.items }
    else
        .{ .@"or" = terms.items };
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-media-in-parens
fn parseParens(allocator: Allocator, input: *Stream) ParseError!Condition {
    const start = input.index;
    const opening = input.peek();
    if (opening != .left_paren and opening != .function) return error.InvalidQuery;
    var block = try input.block();
    const end = input.index;
    input.discardWhitespace();

    if (opening == .left_paren) {
        block.discardWhitespace();
        var contents = block;
        if (parseCondition(allocator, &contents, true)) |inner| {
            return .{
                .group = try child(allocator, inner),
            };
        } else |err| if (err != error.InvalidQuery) return err;
        contents = block;
        if (try parseFeature(allocator, &contents)) |feature| return .{
            .feature = feature,
        };
    }
    if (!try anyValue(&block)) return error.InvalidQuery;
    return .{
        .general_enclosed = try allocator.dupe(u8, input.originalText(start, end).?),
    };
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-media-feature
fn parseFeature(allocator: Allocator, input: *Stream) !?Feature {
    if (input.peek() == .ident) {
        const name = input.peek().ident;
        if (name.startsWith("--")) return null;
        var rest = input.*;
        advance(&rest);
        if (rest.empty()) return .{
            .name = try lowerName(allocator, name),
            .form = .boolean,
        };
        if (rest.peek() == .colon) {
            advance(&rest);
            const value = try parseValue(allocator, &rest) orelse return null;
            if (!rest.empty()) return null;
            return .{
                .name = try lowerName(allocator, name),
                .form = .{
                    .plain = value,
                },
            };
        }
    }
    return parseRange(allocator, input);
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-mf-value
fn parseValue(allocator: Allocator, input: *Stream) !?Value {
    const value: Value = switch (input.peek()) {
        .ident => |name| .{ .ident = try lowerName(allocator, name) },
        .dimension => |dim| .{
            .dimension = .{
                .number = dim.value,
                .unit = try lowerName(allocator, dim.unit),
            },
        },
        .number => |number| blk: {
            advance(input);
            if (!atDelimiter(input, '/')) return .{
                .number = number.value,
            };
            advance(input);
            if (input.peek() != .number) return null;
            break :blk .{
                .ratio = .{
                    .numerator = number.value,
                    .denominator = input.peek().number.value,
                },
            };
        },
        .function => {
            const start = input.index;
            var body = try input.block();
            if (!try anyValue(&body)) return null;
            const text = input.originalText(start, input.index).?;
            input.discardWhitespace();
            return .{
                .function = try allocator.dupe(u8, text),
            };
        },
        else => return null,
    };
    advance(input);
    return value;
}

fn atDelimiter(input: *const Stream, ch: u8) bool {
    const token = input.peek();
    return token == .delim and token.delim == ch;
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-mf-comparison
fn comparison(input: *Stream) ?MediaQuery.Comparison {
    const token = input.peek();
    if (token != .delim) return null;
    const op = token.delim;
    if (op != '<' and op != '>' and op != '=') return null;
    input.discardToken();

    const equals = op != '=' and atDelimiter(input, '=');
    if (equals) input.discardToken();
    input.discardWhitespace();
    return switch (op) {
        '<' => if (equals) .@"<=" else .@"<",
        '>' => if (equals) .@">=" else .@">",
        else => .@"=",
    };
}

// https://drafts.csswg.org/mediaqueries-5/#typedef-mf-range
fn parseRange(allocator: Allocator, input: *Stream) !?Feature {
    const left = try parseValue(allocator, input) orelse return null;
    const op = comparison(input) orelse return null;
    const middle = try parseValue(allocator, input) orelse return null;
    if (input.empty() and left == .ident)
        return .{
            .name = left.ident,
            .form = .{
                .range = .{
                    .after = .{
                        .operator = op,
                        .value = middle,
                    },
                },
            },
        };
    if (middle != .ident) return null;
    var feature = Feature{
        .name = middle.ident,
        .form = .{
            .range = .{
                .before = .{
                    .operator = op,
                    .value = left,
                },
            },
        },
    };
    if (input.empty()) return feature;
    const next = comparison(input) orelse return null;
    if (op == .@"=" or @tagName(op)[0] != @tagName(next)[0]) return null;
    feature.form.range.after = .{
        .operator = next,
        .value = try parseValue(allocator, input) orelse return null,
    };
    return if (input.empty()) feature else null;
}

test "CSSOM parses media query lists" {
    const allocator = std.testing.allocator;
    for ([_][2][]const u8{
        .{ "not screen and (min-WIDTH:5px) AND (max-width:40px)", "not screen and (min-width: 5px) and (max-width: 40px)" },
        .{ "(4px<WIDTH<=10px) OR (COLOR)", "(4px < width <= 10px) or (color)" },
        .{ "screen and ((color) or (grid))", "screen and ((color) or (grid))" },
        .{ "all and (color) and (color", "(color) and (color)" },
        .{ "screen or print", "not all" },
        .{ "not (color) and (grid)", "not all" },
        .{ "future(x,y)", "future(x,y)" },
        .{ "(foo])", "not all" },
    }) |case| {
        var result = (try parseOne(allocator, case[0])).?;
        defer result.deinit();
        const text = try result.toString(allocator);
        defer allocator.free(text);
        try std.testing.expectEqualStrings(case[1], text);
    }
    try std.testing.expect(try parseOne(allocator, " , ") == null);
}
