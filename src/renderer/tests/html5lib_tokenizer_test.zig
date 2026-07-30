const std = @import("std");

const TokenIngester = @import("../html/tokenizer/TokenIngester.zig");
const Tokenizer = @import("../html/tokenizer/Tokenizer.zig");
const token = @import("../html/tokenizer/token.zig");
const TestIngester = @import("../html/tokenizer/TestIngester.zig");
const state = @import("../html/tokenizer/state.zig");
const ErrorIngester = @import("../html/tokenizer/ErrorIngester.zig");
const TestErrorIngester = @import("../html/tokenizer/TestErrorIngester.zig");

const Token = token.Token;
const Attribute = token.Attribute;

const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;
const BufferDeque = strale.BufferDeque;
const testing = std.testing;
const config = @import("config");

pub fn printFailedMessage(path: []const u8, idx: usize, desc: []const u8, init_state: []const u8) void {
    std.debug.print(
        "\n[Failed] Test Failed in File: {s}\nCase #{d}: {s}\nInitial state: {s}\n",
        .{ path, idx, desc, init_state },
    );
}

/// Parse one token from an html5lib tokenizer test JSON value.
pub fn parseJsonToken(
    allocator: std.mem.Allocator,
    json_item: std.json.Value,
) !Token {
    const arr = switch (json_item) {
        .array => |v| v,
        else => return error.InvalidJsonToken,
    };

    if (arr.items.len == 0 or arr.items[0] != .string) return error.InvalidJsonToken;
    const token_type = arr.items[0].string;

    if (std.mem.eql(u8, token_type, "StartTag")) {
        if (arr.items.len < 3) return error.InvalidJsonToken;

        const tag_name = arr.items[1].string;

        if (arr.items[2] != .object) return error.InvalidJsonToken;

        var attrs: std.ArrayList(Attribute) = .empty;
        errdefer {
            for (attrs.items) |*attr| {
                attr.name.deinit();
                attr.value.deinit();
            }
            attrs.deinit(allocator);
        }

        var attr_iter = arr.items[2].object.iterator();
        while (attr_iter.next()) |entry| {
            if (entry.value_ptr.* != .string) return error.InvalidJsonToken;

            try attrs.append(allocator, .{
                .name = try StraleUtf8Global.initSlice(entry.key_ptr.*),
                .value = try StraleUtf8Global.initSlice(entry.value_ptr.string),
            });
        }

        const self_closing = if (arr.items.len > 3 and arr.items[3] == .bool)
            arr.items[3].bool
        else
            false;

        return .{
            .TagToken = .{
                .kind = .StartTag,
                .name = try StraleUtf8Global.initSlice(tag_name),
                .self_closing = self_closing,
                .attrs = attrs,
            },
        };
    }

    if (std.mem.eql(u8, token_type, "EndTag")) {
        if (arr.items.len < 2) return error.InvalidJsonToken;
        const tag_name = arr.items[1].string;

        return .{
            .TagToken = .{
                .kind = .EndTag,
                .name = try StraleUtf8Global.initSlice(tag_name),
                .self_closing = false,
                .attrs = .empty,
            },
        };
    }

    if (std.mem.eql(u8, token_type, "Character")) {
        if (arr.items.len < 2) return error.InvalidJsonToken;

        return .{
            .CharacterToken = try StraleUtf8Global.initSlice(arr.items[1].string),
        };
    }

    if (std.mem.eql(u8, token_type, "Comment")) {
        if (arr.items.len < 2) return error.InvalidJsonToken;

        return .{
            .CommentToken = try StraleUtf8Global.initSlice(
                arr.items[1].string,
            ),
        };
    }

    if (std.mem.eql(u8, token_type, "DOCTYPE")) {
        if (arr.items.len < 5) return error.InvalidJsonToken;

        const name_str = if (arr.items[1] == .null)
            ""
        else
            arr.items[1].string;

        const public_id_str = if (arr.items[2] == .null)
            ""
        else
            arr.items[2].string;

        const system_id_str = if (arr.items[3] == .null)
            ""
        else
            arr.items[3].string;

        const correct = if (arr.items[4] == .bool)
            arr.items[4].bool
        else
            true;

        return .{
            .DoctypeToken = .{
                .name = try StraleUtf8Global.initSlice(name_str),
                .public_id = try StraleUtf8Global.initSlice(public_id_str),
                .system_id = try StraleUtf8Global.initSlice(system_id_str),
                .force_quirks = !correct,
            },
        };
    }

    return error.UnknownJsonTokenType;
}

/// Run one html5lib tokenizer test file.
pub fn runHtml5LibTestFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    io: std.Io,
) !void {
    const content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .unlimited,
    );
    defer allocator.free(content);
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        content,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidTestFile;

    const root = parsed.value.object;
    const tests_value = root.get("tests") orelse return error.MissingTestsField;

    if (tests_value != .array) return error.InvalidTestsField;
    for (tests_value.array.items, 0..) |test_case_value, test_case_index| {
        if (test_case_value != .object) {
            return error.InvalidTestCase;
        }

        const test_case = test_case_value.object;
        const input_value = test_case.get("input") orelse {
            return error.MissingInputField;
        };

        // Get tests' input string.
        if (input_value != .string) return error.InvalidInputField;
        const input = input_value.string;

        // Get tests' output array.
        const expected_output_value = test_case.get("output") orelse return error.MissingOutputField;
        if (expected_output_value != .array) return error.InvalidOutputField;

        // Get tests' error array.
        const errors = test_case.get("errors") orelse null;
        if (errors) |errs| if (errs != .array) return error.InvalidErrorsField;

        // Get tests' initial states.
        var default_states = [_][]const u8{"Data state"};
        var state_strings: []const []const u8 = undefined;

        var allocated_states: ?[][]const u8 = null;
        defer if (allocated_states) |s| allocator.free(s);

        if (test_case.get("initialStates")) |is_val| {
            if (is_val == .array and is_val.array.items.len > 0) {
                const list = try allocator.alloc([]const u8, is_val.array.items.len);
                for (is_val.array.items, 0..) |item, i| {
                    list[i] = item.string;
                }
                allocated_states = list;
                state_strings = list;
            } else {
                state_strings = &default_states;
            }
        } else {
            state_strings = &default_states;
        }

        // Get tests' last start states.
        const l = if (test_case.get("lastStartTag")) |last| blk: {
            const s = try StraleUtf8Global.initSlice(last.string);
            break :blk s;
        } else null;

        for (state_strings) |initial_state| {
            const st = try state.stringToTokenizeState(initial_state);
            // Initialize Token Ingester.
            var test_ingester = TestIngester.init(allocator);
            defer test_ingester.deinit();

            const ingester = TokenIngester.init(&test_ingester, TestIngester.handleToken);

            // Initialize Error Ingester.
            var err_ingester = TestErrorIngester.init(allocator);
            defer err_ingester.deinit();

            const ec = ErrorIngester.init(&err_ingester, TestErrorIngester.handleError);

            var tokenizer = Tokenizer.init(allocator, ingester, ec, .{ .inital_state = st, .last_state_tag_name = l });
            defer tokenizer.deinit();

            strale.setGlobalAlloc(allocator);

            var buffer = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
            defer buffer.deinit();

            const description = if (test_case.get("description")) |d|
                if (d == .string)
                    d.string
                else
                    "No description"
            else
                "No description";

            try buffer.pushBackSlice(input);
            if (config.debug) {
                std.debug.print("===== {s} =====\n", .{description});
            }
            try tokenizer.step_E(&buffer);
            var actual_index: usize = 0;
            var err_actual_index: usize = 0;

            for (expected_output_value.array.items) |expected_json_token| {
                // Skip EOF tokens.
                const t_len = test_ingester.tokens.items.len;
                while (actual_index < t_len and
                    std.meta.activeTag(test_ingester.tokens.items[actual_index]) == .EofToken)
                {
                    actual_index += 1;
                }

                if (actual_index >= test_ingester.tokens.items.len) {
                    printFailedMessage(path, test_case_index, description, initial_state);

                    std.debug.print("Expected {} tokens, but tokenizer only emit {} tokens.\n", .{ expected_output_value.array.items.len, t_len });
                    return error.MissingActualToken;
                }

                var expected_token = try parseJsonToken(
                    allocator,
                    expected_json_token,
                );
                defer expected_token.deinit(allocator);

                const actual_token = test_ingester.tokens.items[actual_index];

                token.expectToken(
                    expected_token,
                    actual_token,
                ) catch |err| {
                    printFailedMessage(path, test_case_index, description, initial_state);

                    std.debug.print("Token index: {d}\n", .{actual_index});
                    return err;
                };

                actual_index += 1;
            }

            while (actual_index < test_ingester.tokens.items.len and
                std.meta.activeTag(test_ingester.tokens.items[actual_index]) == .EofToken)
            {
                actual_index += 1;
            }

            if (actual_index != test_ingester.tokens.items.len) {
                printFailedMessage(path, test_case_index, description, initial_state);

                std.debug.print("Tokenizer emitted unexpected extra tokens.\n", .{});

                for (test_ingester.tokens.items, 0..) |t, i| {
                    std.debug.print("[{d}] {f}\n", .{ i, t });
                }
                return error.UnexpectedExtraTokens;
            }

            if (errors) |errs| {
                for (errs.array.items) |expected_error| {
                    const e_len = err_ingester.errors.items.len;
                    if (err_actual_index >= e_len) {
                        printFailedMessage(path, test_case_index, description, initial_state);

                        std.debug.print("Expected {} errors, but tokenizer only emit {} errors.\n", .{ errs.array.items.len, e_len });
                        return error.MissingActualError;
                    }

                    if (expected_error != .object) return error.InvalidTestsField;
                    const code = expected_error.object.get("code") orelse return error.InvalidTestsField;
                    const line = expected_error.object.get("line") orelse return error.InvalidTestsField;

                    err_ingester.expectError(
                        err_actual_index,
                        code.string,
                        @as(usize, @intCast(line.integer)),
                    ) catch |err| {
                        printFailedMessage(path, test_case_index, description, initial_state);

                        std.debug.print("Error index: {d}\n", .{err_actual_index});
                        return err;
                    };

                    err_actual_index += 1;
                }
            }
        }
    }
}

test "html5lib escapeFlag" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/escapeFlag.test", testing.io);
}

test "html5lib contentModelFlags" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/contentModelFlags.test", testing.io);
}

test "html5lib entities" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/entities.test", testing.io);
}

test "html5lib namedEntities" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/namedEntities.test", testing.io);
}

test "html5lib numericEntities" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/numericEntities.test", testing.io);
}

test "html5lib pendingSpecChanges" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/pendingSpecChanges.test", testing.io);
}

test "html5lib test1" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/test1.test", testing.io);
}

test "html5lib test2" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/test2.test", testing.io);
}

test "html5lib test3" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/test3.test", testing.io);
}

test "html5lib test4" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/test4.test", testing.io);
}

test "html5lib unicodeChars" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tokenizer/unicodeChars.test", testing.io);
}
