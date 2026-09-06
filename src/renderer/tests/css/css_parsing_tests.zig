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

fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]TokenStream.Item {
    var tokenizer = Tokenizer.init(allocator, input);
    defer tokenizer.deinit();
    var items: std.ArrayList(TokenStream.Item) = .empty;
    while (true) {
        const tk = tokenizer.consume(false);
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
        if (item == .array and item.array.items.len > 0 and item.array.items[0] == .string and
            std.mem.eql(u8, item.array.items[0].string, "error")) continue;
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

fn runOneComponentValueTest(
    alloc: std.mem.Allocator,
    path: []const u8,
    io: std.Io,
) !void {
    const content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        alloc,
        .unlimited,
    );
    defer alloc.free(content);
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        alloc,
        content,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidTestFile;

    const cases = parsed.value.array.items;

    var i: usize = 0;
    while (i < cases.len) : (i += 2) {
        if (cases[i] != .string) return error.InvalidTestFile;
        const items = try tokenize(alloc, cases[i].string);
        var stream = TokenStream.init(alloc, items);
        var parser = Parser.init(alloc, &stream);

        const expected = cases[i + 1];
        if (expected == .array and expected.array.items.len == 2 and
            expected.array.items[0] == .string and
            std.mem.eql(u8, expected.array.items[0].string, "error"))
        {
            // TODO: Need check errors.
            try std.testing.expectError(error.Syntax, parser.parseComponentValue());
            continue;
        }

        const actual = parser.parseComponentValue() catch |err| {
            std.debug.print("\ncss-parsing-tests input: {s}\n", .{cases[i].string});
            return err;
        };
        expectComponent(expected, actual) catch |err| {
            std.debug.print("\ncss-parsing-tests input: {s}\n", .{cases[i].string});
            return err;
        };
    }
}

//test "CSS css-parsing-tests: one component value" {
//    var arena = std.heap.ArenaAllocator.init(testing.allocator);
//    defer arena.deinit();
//    try runOneComponentValueTest(arena.allocator(), "src/renderer/tests/css/css-parsing-tests/one_component_value.json", testing.io);
//}
