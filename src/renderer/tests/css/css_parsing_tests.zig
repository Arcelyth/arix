const std = @import("std");
const Tokenizer = @import("../../css/Tokenizer.zig");
const TokenStream = @import("../../css/TokenStream.zig");
const Parser = @import("../../css/Parser.zig");
const css = @import("../../css/parsing_results.zig");
const token = @import("../../css/token.zig");
const Token = token.Token;
const cloneToken = token.cloneToken;
const String = @import("../../css/String.zig");
const testing = std.testing;

fn normalize(value: *std.json.Value) void {
    switch (value.*) {
        .array => |*array| for (array.items) |*item| normalize(item),
        .string => |text| {
            if (std.mem.eql(u8, text, "empty") or std.mem.eql(u8, text, "extra-input"))
                value.* = .{ .string = "invalid" };
        },
        else => {},
    }
}

fn tokenize(allocator: std.mem.Allocator, input: []const u8, unicode_ranges_allowed: bool) ![]TokenStream.Item {
    var tokenizer = Tokenizer.init(allocator, input);
    defer tokenizer.deinit();
    var items: std.ArrayList(TokenStream.Item) = .empty;
    while (true) {
        const tk = tokenizer.consume(unicode_ranges_allowed);
        if (tk == .eof) break;
        try items.append(allocator, .{ .token = try cloneToken(allocator, tk) });
    }
    return items.toOwnedSlice(allocator);
}

fn expectString(expected: []const u8, actual: String) !void {
    switch (actual.value) {
        .borrowed => |value| try std.testing.expectEqualStrings(expected, value),
        .owned => |value| {
            var encoded: std.ArrayList(u8) = .empty;
            defer encoded.deinit(std.testing.allocator);
            for (value) |cp| {
                var bytes: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(cp, &bytes);
                try encoded.appendSlice(std.testing.allocator, bytes[0..len]);
            }
            try std.testing.expectEqualStrings(expected, encoded.items);
        },
    }
}

fn expectNumber(expected: std.json.Value, actual: f64) !void {
    const value: f64 = switch (expected) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => return error.InvalidFixture,
    };
    try std.testing.expectApproxEqAbs(value, actual, 1e-12);
}

fn expectToken(expected: std.json.Value, actual: css.PreservedToken) !void {
    if (expected == .string) {
        const text = expected.string;
        if (text.len == 1) return switch (actual) {
            .delim => |cp| try std.testing.expectEqual(@as(u21, text[0]), cp),
            .whitespace => try std.testing.expectEqualStrings(" ", text),
            .colon => try std.testing.expectEqualStrings(":", text),
            .semicolon => try std.testing.expectEqualStrings(";", text),
            .comma => try std.testing.expectEqualStrings(",", text),
            .right_brace => try std.testing.expectEqualStrings("}", text),
            .right_bracket => try std.testing.expectEqualStrings("]", text),
            .right_paren => try std.testing.expectEqualStrings(")", text),
            else => error.UnexpectedToken,
        };
        return switch (actual) {
            .whitespace => try std.testing.expectEqualStrings(" ", text),
            .cdo => try std.testing.expectEqualStrings("<!--", text),
            .cdc => try std.testing.expectEqualStrings("-->", text),
            else => error.UnexpectedToken,
        };
    }

    const array = expected.array.items;
    const kind = array[0].string;

    if (std.mem.eql(u8, kind, "error")) return;
    if (std.mem.eql(u8, kind, "ident")) return switch (actual) {
        .ident => |value| expectString(array[1].string, value),
        else => error.UnexpectedToken,
    };
    if (std.mem.eql(u8, kind, "at-keyword")) return switch (actual) {
        .at_keyword => |value| expectString(array[1].string, value),
        else => error.UnexpectedToken,
    };
    if (std.mem.eql(u8, kind, "string")) return switch (actual) {
        .string => |value| expectString(array[1].string, value),
        else => error.UnexpectedToken,
    };
    if (std.mem.eql(u8, kind, "url")) return switch (actual) {
        .url => |value| expectString(array[1].string, value),
        else => error.UnexpectedToken,
    };
    if (std.mem.eql(u8, kind, "hash")) {
        const value = switch (actual) {
            .hash => |value| value,
            else => return error.UnexpectedToken,
        };
        try expectString(array[1].string, value.value);
        try std.testing.expectEqualStrings(array[2].string, @tagName(value.type_flag));
        return;
    }
    if (std.mem.eql(u8, kind, "number")) {
        const value = switch (actual) {
            .number => |value| value,
            else => return error.UnexpectedToken,
        };
        try expectNumber(array[2], value.value);
        try std.testing.expectEqualStrings(array[3].string, @tagName(value.type_flag));
        return;
    }
    if (std.mem.eql(u8, kind, "percentage")) return switch (actual) {
        .percentage => |value| expectNumber(array[2], value.value),
        else => error.UnexpectedToken,
    };
    if (std.mem.eql(u8, kind, "dimension")) {
        const value = switch (actual) {
            .dimension => |value| value,
            else => return error.UnexpectedToken,
        };
        try expectNumber(array[2], value.value);
        try std.testing.expectEqualStrings(array[3].string, @tagName(value.type_flag));
        try expectString(array[4].string, value.unit);
        return;
    }
    if (std.mem.eql(u8, kind, "unicode-range")) {
        const value = switch (actual) {
            .unicode_range => |value| value,
            else => return error.UnexpectedToken,
        };
        try std.testing.expectEqual(@as(u32, @intCast(array[1].integer)), value.start);
        try std.testing.expectEqual(@as(u32, @intCast(array[2].integer)), value.end);
        return;
    }
    return error.UnsupportedFixtureToken;
}

fn expectComponent(expected: std.json.Value, actual: css.ComponentValue) anyerror!void {
    switch (actual) {
        .preserved_token => |tk| try expectToken(expected, tk),
        .function => |function| {
            const array = expected.array.items;
            try std.testing.expectEqualStrings("function", array[0].string);
            try expectString(array[1].string, function.name);
            try expectComponents(array[2..], function.value);
        },
        .simple_block => |block| {
            const array = expected.array.items;
            const name = switch (block.associated_token) {
                .left_brace => "{}",
                .left_bracket => "[]",
                .left_paren => "()",
            };
            try std.testing.expectEqualStrings(name, array[0].string);
            try expectComponents(array[1..], block.value);
        },
    }
}

fn expectComponents(expected: []const std.json.Value, actual: []const css.ComponentValue) anyerror!void {
    var expected_idx: usize = 0;
    var actual_idx: usize = 0;
    while (expected_idx < expected.len) : (expected_idx += 1) {
        const item = expected[expected_idx];
        if (item == .string and item.string.len == 2 and
            (std.mem.eql(u8, item.string, "~=") or
                std.mem.eql(u8, item.string, "|=") or
                std.mem.eql(u8, item.string, "^=") or
                std.mem.eql(u8, item.string, "$=") or
                std.mem.eql(u8, item.string, "*=") or
                std.mem.eql(u8, item.string, "||")))
        {
            if (actual_idx + 2 > actual.len) return error.MissingComponentValue;
            for (item.string, actual[actual_idx .. actual_idx + 2]) |cp, value| switch (value) {
                .preserved_token => |tk| switch (tk) {
                    .delim => |actual_cp| try std.testing.expectEqual(@as(u21, cp), actual_cp),
                    else => return error.UnexpectedToken,
                },
                else => return error.UnexpectedToken,
            };
            actual_idx += 2;
            continue;
        }
        if (item == .array and item.array.items.len == 2 and item.array.items[0] == .string and
            std.mem.eql(u8, item.array.items[0].string, "error"))
        {
            const detail = item.array.items[1].string;
            const expected_token: ?std.meta.Tag(css.PreservedToken) = if (std.mem.eql(u8, detail, "}"))
                .right_brace
            else if (std.mem.eql(u8, detail, "]"))
                .right_bracket
            else if (std.mem.eql(u8, detail, ")"))
                .right_paren
            else if (std.mem.eql(u8, detail, "bad-string"))
                .bad_string
            else if (std.mem.eql(u8, detail, "bad-url"))
                .bad_url
            else
                null;

            if (expected_token) |tag| {
                if (actual_idx >= actual.len) return error.MissingComponentValue;
                const actual_tag = switch (actual[actual_idx]) {
                    .preserved_token => |tk| std.meta.activeTag(tk),
                    else => return error.UnexpectedToken,
                };
                try std.testing.expectEqual(tag, actual_tag);
                actual_idx += 1;
            }
            continue;
        }
        if (actual_idx >= actual.len) return error.MissingComponentValue;
        expectComponent(item, actual[actual_idx]) catch |err| {
            const expected_kind = if (item == .array) item.array.items[0].string else item.string;
            const actual_kind = switch (actual[actual_idx]) {
                .preserved_token => |tk| @tagName(tk),
                inline else => |_, tag| @tagName(tag),
            };
            std.debug.print("component {d}: expected {s}, actual {s}\n", .{ expected_idx, expected_kind, actual_kind });
            return err;
        };
        actual_idx += 1;
    }
    try std.testing.expectEqual(actual.len, actual_idx);
}

fn expectDeclaration(expected: std.json.Value, actual: css.Declaration) !void {
    const array = expected.array.items;
    try std.testing.expectEqualStrings("declaration", array[0].string);
    try expectString(array[1].string, actual.name);
    try expectComponents(array[2].array.items, actual.value);
    try std.testing.expectEqual(array[3].bool, actual.important);
}

fn loadFixture(alloc: std.mem.Allocator, path: []const u8, io: std.Io) !std.json.Parsed(std.json.Value) {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(content);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, content, .{});
    normalize(&parsed.value);
    if (parsed.value != .array or parsed.value.array.items.len % 2 != 0)
        return error.InvalidTestFile;
    return parsed;
}

fn isInvalid(expected: std.json.Value) bool {
    return expected == .array and expected.array.items.len == 2 and
        expected.array.items[0] == .string and
        expected.array.items[1] == .string and
        std.mem.eql(u8, expected.array.items[0].string, "error") and
        std.mem.eql(u8, expected.array.items[1].string, "invalid");
}

const ParseTest = *const fn (*Parser, std.json.Value) anyerror!void;

fn parseComponentValue(parser: *Parser, expected: std.json.Value) !void {
    if (isInvalid(expected))
        return std.testing.expectError(error.Syntax, parser.parseComponentValue());
    try expectComponent(expected, try parser.parseComponentValue());
}

fn parseComponentValueList(parser: *Parser, expected: std.json.Value) !void {
    try expectComponents(expected.array.items, try parser.parseListOfComponentValues());
}

fn parseDeclaration(parser: *Parser, expected: std.json.Value) !void {
    if (isInvalid(expected))
        return std.testing.expectError(error.Syntax, parser.parseDeclaration());
    try expectDeclaration(expected, try parser.parseDeclaration());
}

fn expectRule(expected: std.json.Value, actual: css.Rule) !void {
    const array = expected.array.items;
    const kind = array[0].string;

    if (std.mem.eql(u8, kind, "at-rule")) {
        const rule = switch (actual) {
            .at_rule => |rule| rule,
            else => return error.UnexpectedRule,
        };
        try expectString(array[1].string, rule.name);
        try expectComponents(array[2].array.items, rule.prelude);
        if (array[3] == .null) {
            try std.testing.expect(rule.declarations == null);
            try std.testing.expect(rule.child_rules == null);
            return;
        }
        if (array[3] != .array or array[3].array.items.len != 0)
            return error.UnsupportedFixture;
        try std.testing.expectEqual(0, (rule.declarations orelse return error.UnexpectedRule).len);
        try std.testing.expectEqual(0, (rule.child_rules orelse return error.UnexpectedRule).len);
        return;
    }

    if (std.mem.eql(u8, kind, "qualified rule")) {
        const rule = switch (actual) {
            .qualified_rule => |rule| rule,
            else => return error.UnexpectedRule,
        };
        try expectComponents(array[1].array.items, rule.prelude);
        if (array[2] != .array or array[2].array.items.len != 0)
            return error.UnsupportedFixture;
        try std.testing.expectEqual(0, rule.declarations.len);
        try std.testing.expectEqual(0, rule.child_rules.len);
        return;
    }

    return error.UnsupportedFixture;
}

fn expectRules(expected: []const std.json.Value, actual: []const css.Rule) !void {
    var actual_index: usize = 0;
    for (expected) |item| {
        if (isInvalid(item)) continue;
        if (actual_index == actual.len) return error.MissingRule;
        expectRule(item, actual[actual_index]) catch |err| return err;
        actual_index += 1;
    }
    try std.testing.expectEqual(actual.len, actual_index);
}

fn parseStylesheet(parser: *Parser, expected: std.json.Value) !void {
    try expectRules(expected.array.items, (try parser.parseStylesheet()).rules);
}

fn runParsingTests(
    alloc: std.mem.Allocator,
    path: []const u8,
    io: std.Io,
    unicode_ranges_allowed: bool,
    parse: ParseTest,
) !void {
    const parsed = try loadFixture(alloc, path, io);
    defer parsed.deinit();

    const cases = parsed.value.array.items;
    var i: usize = 0;
    while (i < cases.len) : (i += 2) {
        if (cases[i] != .string) return error.InvalidTestFile;
        const input = cases[i].string;

        // Skip legacy fixtures that rely on the old treatment of U+0080/U+0081.
        if (std.mem.indexOf(u8, input, "\xC2\x80\xC2\x81") != null) continue;

        const items = try tokenize(alloc, input, unicode_ranges_allowed);
        var stream = TokenStream.init(alloc, items);
        defer stream.deinit();
        var parser = Parser.init(alloc, &stream);
        parse(&parser, cases[i + 1]) catch |err| {
            std.debug.print("\ncss-parsing-tests input: {s}\n", .{input});
            return err;
        };
    }
}

test "CSS css-parsing-tests: one component value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/css-parsing-tests/one_component_value.json",
        testing.io,
        true,
        parseComponentValue,
    );
}

test "CSS css-parsing-tests: component value list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/css-parsing-tests/component_value_list.json",
        testing.io,
        true,
        parseComponentValueList,
    );
}

test "CSS css-parsing-tests: one declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/css-parsing-tests/one_declaration.json",
        testing.io,
        false,
        parseDeclaration,
    );
}

test "CSS css-parsing-tests: stylesheet" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/tests_patch/stylesheet.json",
        testing.io,
        false,
        parseStylesheet,
    );
}
