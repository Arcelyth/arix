const Tokenizer = @This();

const std = @import("std");
const InputStream = @import("InputStream.zig");
const ascii = @import("../utils/ascii.zig");
const token = @import("token.zig");
const Token = token.Token;

// Result for 4.3.13.
const ConsumedNumber = struct {
    value: f64,
    sign: ?token.Sign = null,
    type_flag: token.NumberType = .integer,
};

allocator: std.mem.Allocator,
stream: InputStream,

/// Fixed 3-code-point Ring-buffer lookahead.
lookahead: [3]u21 = undefined,
/// UTF-8 byte length of each buffered code point.
lookahead_byte_len: [3]u3 = undefined,
lookahead_head: u2 = 0,
lookahead_len: u2 = 0,
current: ?u21 = null,
reconsume_current: bool = false,
/// Reused for decoded escapes and replacement characters. Common tokens
/// borrow the original input and never touch this buffer.
scratch: std.ArrayList(u8) = .empty,

pub fn init(alloc: std.mem.Allocator, input_stream: []const u8) Tokenizer {
    return .{
        .allocator = alloc,
        .stream = InputStream.init(input_stream),
    };
}

pub fn deinit(self: *Tokenizer) void {
    self.scratch.deinit(self.allocator);
}

pub inline fn resetScratch(self: *Tokenizer) void {
    self.scratch.clearRetainingCapacity();
}

/// Consume the next filtered input code point.
pub inline fn next(self: *Tokenizer) ?u21 {
    if (self.reconsume_current) {
        self.reconsume_current = false;
        return self.current;
    }

    const code_point = if (self.lookahead_len == 0)
        self.stream.next()
    else blk: {
        const buffered = self.lookahead[self.lookahead_head];
        self.lookahead_head += 1;
        if (self.lookahead_head == 3) self.lookahead_head = 0;
        self.lookahead_len -= 1;
        break :blk buffered;
    };
    self.current = code_point;
    return code_point;
}

/// Return one of the next three input code points without consuming it.
pub fn peek(self: *Tokenizer, comptime offset: u2) ?u21 {
    comptime if (offset > 2) @compileError("lookahead is limited to offsets 0...2");

    const buffered_offset: u2 = if (self.reconsume_current) blk: {
        if (offset == 0) return self.current;
        break :blk offset - 1;
    } else offset;

    while (self.lookahead_len <= buffered_offset) {
        const before = self.stream.pos;
        const cp = self.stream.next() orelse return null;
        const index = ringIndex(self.lookahead_head, self.lookahead_len);
        self.lookahead[index] = cp;
        self.lookahead_byte_len[index] = @intCast(self.stream.pos - before);
        self.lookahead_len += 1;
    }
    return self.lookahead[ringIndex(self.lookahead_head, buffered_offset)];
}

pub inline fn reconsume(self: *Tokenizer) void {
    self.reconsume_current = true;
}

/// Logical byte position, excluding code points buffered by lookahead.
pub fn position(self: *const Tokenizer) usize {
    var buffered_bytes: usize = 0;
    var offset: u2 = 0;
    while (offset < self.lookahead_len) : (offset += 1) {
        buffered_bytes += self.lookahead_byte_len[ringIndex(self.lookahead_head, offset)];
    }
    return self.stream.pos - buffered_bytes;
}

inline fn ringIndex(head: u2, offset: u2) usize {
    var index: u3 = @as(u3, head) + @as(u3, offset);
    if (index >= 3) index -= 3;
    return index;
}

// https://drafts.csswg.org/css-syntax/#consume-token
pub fn consume(self: *Tokenizer, unicode_ranges_allowed: bool) Token {
    self.consumeComments();
    const cp = self.next() orelse return .eof;

    if (ascii.isCssWhitespace(cp)) {
        while (if (self.peek(0)) |next_cp| ascii.isCssWhitespace(next_cp) else false) _ = self.next();
        return .whitespace;
    }

    switch (cp) {
        '"', '\'' => return self.consumeString(cp),
        '#' => {
            if (ascii.isCssIdent_O(self.peek(0)) or validEscape(self.peek(0), self.peek(1))) {
                const type_flag: token.HashType = if (wouldStartIdentSequence(self.peek(0), self.peek(1), self.peek(2))) .id else .unrestricted;
                return .{ .hash = .{ .value = self.consumeIdentSequence(), .type_flag = type_flag } };
            }
            return .{ .delim = cp };
        },
        '(' => return .left_paren,
        ')' => return .right_paren,
        '+' => {
            if (wouldStartNumber(cp, self.peek(0), self.peek(1))) {
                self.reconsume();
                return self.consumeNumeric();
            }
            return .{ .delim = cp };
        },
        ',' => return .comma,
        '-' => {
            if (wouldStartNumber(cp, self.peek(0), self.peek(1))) {
                self.reconsume();
                return self.consumeNumeric();
            }
            if (self.peek(0) == '-' and self.peek(1) == '>') {
                _ = self.next();
                _ = self.next();
                return .cdc;
            }
            if (wouldStartIdentSequence(cp, self.peek(0), self.peek(1))) {
                self.reconsume();
                return self.consumeIdentLike();
            }
            return .{ .delim = cp };
        },
        '.' => {
            if (wouldStartNumber(cp, self.peek(0), self.peek(1))) {
                self.reconsume();
                return self.consumeNumeric();
            }
            return .{ .delim = cp };
        },
        ':' => return .colon,
        ';' => return .semicolon,
        '<' => {
            if (self.peek(0) == '!' and self.peek(1) == '-' and self.peek(2) == '-') {
                _ = self.next();
                _ = self.next();
                _ = self.next();
                return .cdo;
            }
            return .{ .delim = cp };
        },
        '@' => {
            if (wouldStartIdentSequence(self.peek(0), self.peek(1), self.peek(2)))
                return .{ .at_keyword = self.consumeIdentSequence() };
            return .{ .delim = cp };
        },
        '[' => return .left_bracket,
        '\\' => {
            if (validEscape(cp, self.peek(0))) {
                self.reconsume();
                return self.consumeIdentLike();
            }
            self.parseError();
            return .{ .delim = cp };
        },
        ']' => return .right_bracket,
        '{' => return .left_brace,
        '}' => return .right_brace,
        '0'...'9' => {
            self.reconsume();
            return self.consumeNumeric();
        },
        'U', 'u' => {
            if (unicode_ranges_allowed and wouldStartUnicodeRange(cp, self.peek(0), self.peek(1))) {
                self.reconsume();
                return self.consumeUnicodeRange();
            }
            self.reconsume();
            return self.consumeIdentLike();
        },
        else => {
            if (ascii.isCssIdentStart(cp)) {
                self.reconsume();
                return self.consumeIdentLike();
            }
            return .{ .delim = cp };
        },
    }
}

// https://drafts.csswg.org/css-syntax/#consume-comment
pub fn consumeComments(self: *Tokenizer) void {
    while (self.peek(0) == '/' and self.peek(1) == '*') {
        _ = self.next();
        _ = self.next();

        while (true) {
            const cp = self.next() orelse {
                self.parseError();
                return;
            };
            if (cp == '*' and self.peek(0) == '/') {
                _ = self.next();
                break;
            }
        }
    }
}

// https://drafts.csswg.org/css-syntax/#consume-numeric-token
pub fn consumeNumeric(self: *Tokenizer) Token {
    const number = self.consumeNumber();

    if (wouldStartIdentSequence(self.peek(0), self.peek(1), self.peek(2))) {
        return .{ .dimension = .{
            .value = number.value,
            .sign = number.sign,
            .type_flag = number.type_flag,
            .unit = self.consumeIdentSequence(),
        } };
    }

    if (self.peek(0) == '%') {
        _ = self.next();
        return .{ .percentage = .{
            .value = number.value,
            .sign = number.sign,
        } };
    }

    return .{ .number = .{
        .value = number.value,
        .sign = number.sign,
        .type_flag = number.type_flag,
    } };
}

// https://drafts.csswg.org/css-syntax/#consume-ident-like-token
pub fn consumeIdentLike(self: *Tokenizer) Token {
    const name = self.consumeIdentSequence();

    if (ascii.asciiCaseInsensitiveEq(name, "url") and self.peek(0) == '(') {
        _ = self.next();

        while (ascii.isCssWhitespace(self.peek(0)) and ascii.isCssWhitespace(self.peek(1)))
            _ = self.next();

        const first = self.peek(0);
        if (first == '"' or first == '\'' or
            (ascii.isCssWhitespace(first) and (self.peek(1) == '"' or self.peek(1) == '\'')))
        {
            return .{ .function = name };
        }

        return self.consumeUrl();
    }

    if (self.peek(0) == '(') {
        _ = self.next();
        return .{ .function = name };
    }

    return .{ .ident = name };
}

// https://drafts.csswg.org/css-syntax/#consume-string-token
pub fn consumeString(self: *Tokenizer, ending: u21) Token {
    self.resetScratch();

    while (true) {
        const cp = self.next() orelse {
            self.parseError();
            return .{ .string = self.scratch.items };
        };

        if (cp == ending) return .{ .string = self.scratch.items };

        if (ascii.isCssNewline(cp)) {
            self.parseError();
            self.reconsume();
            return .bad_string;
        }

        if (cp == '\\') {
            const following = self.peek(0) orelse continue;
            if (ascii.isCssNewline(following)) {
                _ = self.next();
                continue;
            }

            const escaped = self.consumeEscapedCodePoint();
            self.appendScratch(escaped);
            continue;
        }

        self.appendScratch(cp);
    }
}

// https://drafts.csswg.org/css-syntax/#consume-url-token
pub fn consumeUrl(self: *Tokenizer) Token {
    self.resetScratch();

    while (ascii.isCssWhitespace(self.peek(0))) _ = self.next();

    while (true) {
        const cp = self.next() orelse {
            self.parseError();
            return .{ .url = self.scratch.items };
        };

        switch (cp) {
            ')' => return .{ .url = self.scratch.items },
            ' ', '\t', '\n' => {
                while (ascii.isCssWhitespace(self.peek(0))) _ = self.next();

                if (self.peek(0) == ')') {
                    _ = self.next();
                    return .{ .url = self.scratch.items };
                }
                if (self.peek(0) == null) {
                    self.parseError();
                    return .{ .url = self.scratch.items };
                }

                self.consumeBadUrlRemnants();
                return .bad_url;
            },
            '"', '\'', '(' => {
                self.parseError();
                self.consumeBadUrlRemnants();
                return .bad_url;
            },
            '\\' => {
                if (validEscape(cp, self.peek(0))) {
                    const escaped = self.consumeEscapedCodePoint();
                    self.appendScratch(escaped);
                    continue;
                }

                self.parseError();
                self.consumeBadUrlRemnants();
                return .bad_url;
            },
            else => {
                if (ascii.isCssNonPrintable(cp)) {
                    self.parseError();
                    self.consumeBadUrlRemnants();
                    return .bad_url;
                }
                self.appendScratch(cp);
            },
        }
    }
}

// https://drafts.csswg.org/css-syntax/#consume-escaped-code-point
pub fn consumeEscapedCodePoint(self: *Tokenizer) u21 {
    const first = self.next() orelse {
        self.parseError();
        return 0xFFFD;
    };

    if (!ascii.isAsciiHexDigit(first)) return first;

    var value: u32 = ascii.toHexDigit(first);
    var count: u3 = 0;
    while (count < 5) : (count += 1) {
        const cp = self.peek(0) orelse break;
        if (!ascii.isAsciiHexDigit(cp)) break;
        _ = self.next();
        value = value * 16 + ascii.toHexDigit(cp);
    }

    if (ascii.isCssWhitespace(self.peek(0))) _ = self.next();

    if (value == 0 or value > ascii.maximum_code_point or ascii.isSurrogate(u21, value))
        return 0xFFFD;
    
    return @intCast(value);
}

// https://drafts.csswg.org/css-syntax/#starts-with-a-valid-escape
pub fn validEscape(first: ?u21, second: ?u21) bool {
    if (first != '\\') return false;
    const following = second orelse return false;
    return !ascii.isCssNewline(following);
}

// https://drafts.csswg.org/css-syntax/#would-start-an-identifier
pub fn wouldStartIdentSequence(first: ?u21, second: ?u21, third: ?u21) bool {
    const first_cp = first orelse return false;
    return switch (first_cp) {
        '-' => (if (second) |cp| ascii.isCssIdentStart(cp) or cp == '-' else false) or
            validEscape(second, third),
        '\\' => validEscape(first, second),
        else => ascii.isCssIdentStart(first_cp),
    };
}

// https://drafts.csswg.org/css-syntax/#starts-with-a-number
fn wouldStartNumber(first: ?u21, second: ?u21, third: ?u21) bool {
    const first_cp = first orelse return false;
    return switch (first_cp) {
        '+', '-' => if (second) |second_cp|
            ascii.isAsciiDigit(second_cp) or
                (second_cp == '.' and if (third) |third_cp| ascii.isAsciiDigit(third_cp) else false)
        else
            false,
        '.' => if (second) |cp| ascii.isAsciiDigit(cp) else false,
        '0'...'9' => true,
        else => false,
    };
}

// https://drafts.csswg.org/css-syntax/#starts-a-unicode-range
fn wouldStartUnicodeRange(first: ?u21, second: ?u21, third: ?u21) bool {
    if (first != 'U' and first != 'u') return false;
    if (second != '+') return false;
    const third_cp = third orelse return false;
    return third_cp == '?' or ascii.isAsciiHexDigit(third_cp);
}

// https://drafts.csswg.org/css-syntax/#consume-name
pub fn consumeIdentSequence(self: *Tokenizer) []const u21 {
    _ = self;
    @panic("TODO CSS Syntax §4.3.12");
}

// https://drafts.csswg.org/css-syntax/#consume-number
pub fn consumeNumber(self: *Tokenizer) ConsumedNumber {
    _ = self;
    @panic("TODO CSS Syntax §4.3.13");
}

// https://drafts.csswg.org/css-syntax/#consume-unicode-range-token
pub fn consumeUnicodeRange(self: *Tokenizer) Token {
    _ = self;
    @panic("TODO CSS Syntax §4.3.14");
}

// https://drafts.csswg.org/css-syntax/#consume-remnants-of-bad-url
pub fn consumeBadUrlRemnants(self: *Tokenizer) Token {
    _ = self;
    @panic("TODO CSS Syntax §4.3.15");
}

pub fn parseError(self: *Tokenizer) void {
    _ = self;
}

inline fn appendScratch(self: *Tokenizer, cp: u21) void {
    self.scratch.append(self.allocator, cp) catch @panic("out of memory");
}

test "CSS Tokenizer: caches three-code-point lookahead" {
    const testing = std.testing;

    var tokenizer = Tokenizer.init(testing.allocator, "aé\r\nb");
    defer tokenizer.deinit();

    try testing.expectEqual(@as(u21, 'a'), tokenizer.peek(0).?);
    try testing.expectEqual(@as(u21, 'é'), tokenizer.peek(1).?);
    try testing.expectEqual(@as(u21, '\n'), tokenizer.peek(2).?);
    try testing.expectEqual(@as(usize, 0), tokenizer.position());
    try testing.expectEqual(@as(u21, 'a'), tokenizer.next().?);
    try testing.expectEqual(@as(usize, 1), tokenizer.position());
    tokenizer.reconsume();
    try testing.expectEqual(@as(u21, 'a'), tokenizer.peek(0).?);
    try testing.expectEqual(@as(u21, 'é'), tokenizer.peek(1).?);
    try testing.expectEqual(@as(u21, 'a'), tokenizer.next().?);
    try testing.expectEqual(@as(u21, 'é'), tokenizer.next().?);
    try testing.expectEqual(@as(u21, 'b'), tokenizer.peek(1).?);
    try testing.expectEqual(@as(u21, '\n'), tokenizer.next().?);
    try testing.expectEqual(@as(u21, 'b'), tokenizer.next().?);
    try testing.expect(tokenizer.peek(0) == null);
}
