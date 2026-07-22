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

        if (input_value != .string) return error.InvalidInputField;

        const input = input_value.string;
        const expected_output_value = test_case.get("output") orelse return error.MissingOutputField;

        if (expected_output_value != .array) return error.InvalidOutputField;

        const initial_states = test_case.get("initialStates") orelse return error.MissingOutputField;

        const l = if (test_case.get("lastStartTag")) |last| blk: {
            const s = try StraleUtf8Global.initSlice(last.string);
            break :blk s;
        } else null;

        for (initial_states.array.items) |initial_state| {
            const st = try state.stringToTokenizeState(initial_state.string);
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

            try buffer.pushBackSlice(input);
            try tokenizer.step_E(&buffer);

            var actual_index: usize = 0;

            const description = if (test_case.get("description")) |d|
                if (d == .string)
                    d.string
                else
                    "No description"
            else
                "No description";

            for (expected_output_value.array.items) |expected_json_token| {
                // Skip EOF tokens.
                while (actual_index < test_ingester.tokens.items.len and
                    std.meta.activeTag(test_ingester.tokens.items[actual_index]) == .EofToken)
                {
                    actual_index += 1;
                }

                if (actual_index >= test_ingester.tokens.items.len) {
                    std.debug.print(
                        "\n[Failed] Test Failed in File: {s}, Case #{d}: {s}\n",
                        .{
                            path,
                            test_case_index,
                            description,
                        },
                    );

                    std.debug.print("Expected more tokens, but tokenizer ended early.\n", .{});
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
                    std.debug.print(
                        "\n[Failed] Test Failed in File: {s}, Case #{d}: {s}\n",
                        .{
                            path,
                            test_case_index,
                            description,
                        },
                    );

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
                std.debug.print(
                    "\n[Failed] Test Failed in File: {s}, Case #{d}: {s}\n",
                    .{
                        path,
                        test_case_index,
                        description,
                    },
                );

                std.debug.print("Tokenizer emitted unexpected extra tokens.\n", .{});

                return error.UnexpectedExtraTokens;
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
