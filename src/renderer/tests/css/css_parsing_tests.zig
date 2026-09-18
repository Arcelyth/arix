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
const color = @import("../../css/color.zig");

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

fn tokenize(allocator: std.mem.Allocator, input: []const u8, unicode_ranges_allowed: bool) ![]Token {
    var tokenizer = Tokenizer.init(allocator, input);
    defer tokenizer.deinit();
    var items: std.ArrayList(Token) = .empty;
    while (true) {
        const tk = tokenizer.consume(unicode_ranges_allowed);
        if (tk == .eof) break;
        try items.append(allocator, try cloneToken(allocator, tk));
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
            .delim => |cp| if (text.len > 0 and text.len <= 4)
                try testing.expectEqual(try std.unicode.utf8Decode(text), cp)
            else
                error.UnexpectedToken,
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

fn expectRule(expected: std.json.Value, actual: css.Rule) anyerror!void {
    const array = expected.array.items;
    const kind = array[0].string;

    if (std.mem.eql(u8, kind, "at-rule")) {
        const rule = switch (actual) {
            .at_rule => |rule| rule,
            else => return error.UnexpectedRule,
        };
        try expectString(array[1].string, rule.name);
        try expectComponents(array[2].array.items, rule.prelude);
        if (array[3] == .null)
            try std.testing.expect(rule.declarations == null)
        else
            try expectDeclarations(array[3].array.items, rule.declarations orelse return error.UnexpectedRule);
        if (array[4] == .null)
            try std.testing.expect(rule.child_rules == null)
        else
            try expectRules(array[4].array.items, rule.child_rules orelse return error.UnexpectedRule);
        return;
    }

    if (std.mem.eql(u8, kind, "qualified rule")) {
        const rule = switch (actual) {
            .qualified_rule => |rule| rule,
            else => return error.UnexpectedRule,
        };
        try expectComponents(array[1].array.items, rule.prelude);
        try expectDeclarations(array[2].array.items, rule.declarations);
        try expectRules(array[3].array.items, rule.child_rules);
        return;
    }

    return error.InvalidFixture;
}

fn expectDeclarations(expected: []const std.json.Value, actual: []const css.Declaration) anyerror!void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_declaration, declaration|
        try expectDeclaration(expected_declaration, declaration);
}

fn expectRules(expected: []const std.json.Value, actual: []const css.Rule) anyerror!void {
    var actual_index: usize = 0;
    for (expected) |item| {
        if (isInvalid(item)) continue;
        if (actual_index == actual.len) return error.MissingRule;
        expectRule(item, actual[actual_index]) catch |err| return err;
        actual_index += 1;
    }
    try std.testing.expectEqual(actual.len, actual_index);
}

fn expectBlockItems(expected: []const std.json.Value, actual: []const css.BlockItem) anyerror!void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_item, actual_item| {
        const array = expected_item.array.items;
        const kind = array[0].string;
        if (std.mem.eql(u8, kind, "declarations")) {
            const declarations = switch (actual_item) {
                .declarations => |value| value,
                else => return error.UnexpectedBlockItem,
            };
            try expectDeclarations(array[1].array.items, declarations);
        } else {
            const rule = switch (actual_item) {
                .rule => |value| value,
                else => return error.UnexpectedBlockItem,
            };
            try expectRule(expected_item, rule);
        }
    }
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

fn parseRule(parser: *Parser, expected: std.json.Value) !void {
    if (isInvalid(expected))
        return std.testing.expectError(error.Syntax, parser.parseRule());
    try expectRule(expected, try parser.parseRule());
}

fn parseBlockContents(parser: *Parser, expected: std.json.Value) !void {
    try expectBlockItems(expected.array.items, try parser.parseBlockContents());
}

fn parseStylesheet(parser: *Parser, expected: std.json.Value) !void {
    try expectRules(expected.array.items, (try parser.parseStylesheet()).rules);
}

fn parseAnPlusB(parser: *Parser, expected: std.json.Value) !void {
    if (expected == .null)
        return std.testing.expectError(error.Syntax, parser.parseNth());

    const pair = expected.array.items;
    if (pair.len != 2 or pair[0] != .integer or pair[1] != .integer)
        return error.InvalidFixture;
    const result = try parser.parseNth();
    try std.testing.expectEqual(@as(i32, @intCast(pair[0].integer)), result.a);
    try std.testing.expectEqual(@as(i32, @intCast(pair[1].integer)), result.b);
}

// Decode the fixture's canonical serialization without using the color parser
// under test: in particular, do not clamp or normalize its expected values.
fn fixtureColor(text: []const u8) !color.Absolute {
    var parts = std.mem.tokenizeAny(u8, text, "(), /\t\r\n");
    const function = parts.next() orelse return error.InvalidFixture;
    const rgb = std.mem.eql(u8, function, "rgb") or std.mem.eql(u8, function, "rgba");
    const name = if (std.mem.eql(u8, function, "color"))
        parts.next() orelse return error.InvalidFixture
    else if (rgb) "srgb" else function;
    var key: [32]u8 = undefined;
    if (name.len > key.len) return error.InvalidFixture;
    for (name, key[0..name.len]) |byte, *out| out.* = if (byte == '-') '_' else byte;
    const space = std.meta.stringToEnum(color.Space, key[0..name.len]) orelse return error.InvalidFixture;
    var result: color.Absolute = .{ .space = space, .channels = .{ null, null, null } };
    for (&result.channels) |*channel| {
        const value = parts.next() orelse return error.InvalidFixture;
        if (std.mem.eql(u8, value, "none")) continue;
        const numeric = std.mem.trimEnd(u8, value, "%");
        channel.* = try std.fmt.parseFloat(f64, numeric);
        if (rgb) channel.* = channel.*.? / 255;
    }
    if (parts.next()) |alpha| {
        result.alpha = if (std.mem.eql(u8, alpha, "none")) null else try std.fmt.parseFloat(f64, alpha);
    }
    if (parts.next() != null) return error.InvalidFixture;
    return result;
}

fn parseColor(parser: *Parser, expected: std.json.Value) !void {
    const actual = try color.parse(parser.input);
    parser.input.discardWhitespace();
    if (expected == .null)
        return testing.expect(actual == null or !parser.input.empty());
    if (expected != .string) return error.InvalidFixture;
    try testing.expect(actual != null and actual.? == .absolute);
    try testing.expect(parser.input.empty());
    const want = try fixtureColor(expected.string);
    var got = actual.?.absolute;
    if (want.space == .srgb and (got.space == .hsl or got.space == .hwb)) {
        const hue = got.channels[0] orelse return error.UnexpectedMissingChannel;
        const second = got.channels[1] orelse return error.UnexpectedMissingChannel;
        const third = got.channels[2] orelse return error.UnexpectedMissingChannel;
        const rgb = if (got.space == .hsl) color.hslToRgb(hue, second, third) else color.hwbToRgb(hue, second, third);
        got.space = .srgb;
        got.channels = .{ rgb[0], rgb[1], rgb[2] };
    }
    try testing.expectEqual(want.space, got.space);
    for (want.channels ++ [1]?f64{want.alpha}, got.channels ++ [1]?f64{got.alpha}) |reference, channel| {
        if (reference) |value| {
            try testing.expect(channel != null);
            // Bundled fixture numbers are rounded to six decimal places.
            try testing.expectApproxEqAbs(value, channel.?, 0.000001);
        } else try testing.expect(channel == null);
    }
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

test "CSS css-parsing-tests: An+B" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/css-parsing-tests/An+B.json",
        testing.io,
        false,
        parseAnPlusB,
    );
}

test "CSS css-parsing-tests: block contents" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/tests_patch/blocks_contents.json",
        testing.io,
        false,
        parseBlockContents,
    );
}

test "CSS css-parsing-tests: component value list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/tests_patch/component_value_list.json",
        testing.io,
        true,
        parseComponentValueList,
    );
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

test "CSS css-parsing-tests: one rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/tests_patch/one_rule.json",
        testing.io,
        false,
        parseRule,
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

test "CSS css-parsing-tests: colors" {
    const files = .{
        "css-parsing-tests/color_keywords_3.json",
        "css-parsing-tests/color_keywords_4.json",
        "css-parsing-tests/color_hexadecimal_3.json",
        "css-parsing-tests/color_hexadecimal_4.json",
        "css-parsing-tests/color_hsl_3.json",
        "tests_patch/color_hsl_4.json",
        "tests_patch/color_hwb_4.json",
        "tests_patch/color_lab_4.json",
        "tests_patch/color_lch_4.json",
        "tests_patch/color_oklab_4.json",
        "tests_patch/color_oklch_4.json",
        "css-parsing-tests/color_function_4.json",
    };
    inline for (files) |file| {
        errdefer std.debug.print("Fixture: {s} Failed\n", .{file});
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        try runParsingTests(arena.allocator(), "src/renderer/tests/css/" ++ file, testing.io, false, parseColor);
    }
}

test "CSS css-parsing-tests: declaration list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runParsingTests(
        arena.allocator(),
        "src/renderer/tests/css/tests_patch/declaration_list.json",
        testing.io,
        false,
        parseBlockContents,
    );
}
