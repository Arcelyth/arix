const Decoder = @This();
const std = @import("std");
const Encoding = @import("encoding.zig").Encoding;
const IoQueue = @import("queue.zig").IoQueue;
const ascii = @import("../utils/ascii.zig");
const indexes = @import("indexes.zig");

pub const ErrorMode = enum { replacement, fatal };

/// Item storage must remain valid until processItem has appended it to output.
pub const HandlerResult = union(enum) {
    finished,
    items: []const u21,
    err,
    continue_,
};

pub const ProcessResult = enum { finished, continue_ };

const Iso2022JpState = enum { ascii, roman, katakana, leading, trailing, escape_start, escape };

encoding: Encoding,
// The encoding selects the active state; it must not change during decoding.
state: union {
    utf8: struct {
        code_point: u21 = 0,
        bytes_seen: u8 = 0,
        bytes_needed: u8 = 0,
        lower: u8 = 0x80,
        upper: u8 = 0xBF,
    },
    utf16: struct { leading_byte: ?u8 = null, leading_surrogate: ?u16 = null },
    gb18030: struct { first: u8 = 0, second: u8 = 0, third: u8 = 0 },
    euc_jp: struct { leading: u8 = 0, jis0212: bool = false },
    iso2022_jp: struct {
        state: Iso2022JpState = .ascii,
        output_state: Iso2022JpState = .ascii,
        leading: u8 = 0,
        output: bool = false,
    },
    leading: u8,
    replacement_error_returned: bool,
    none: void,
},
// HandlerResult borrows this slot until processItem appends it to the output.
code_point: u21 = 0,

inline fn emit(self: *Decoder, cp: u21) HandlerResult {
    self.code_point = cp;
    return .{ .items = @as(*const [1]u21, &self.code_point) };
}

pub fn init(encoding: Encoding) Decoder {
    return .{
        .encoding = encoding,
        .state = switch (encoding) {
            .utf8 => .{ .utf8 = .{} },
            .utf16le, .utf16be => .{ .utf16 = .{} },
            .gbk, .gb18030 => .{ .gb18030 = .{} },
            .eucjp => .{ .euc_jp = .{} },
            .iso2022jp => .{ .iso2022_jp = .{} },
            .big5, .shift_jis, .euckr => .{ .leading = 0 },
            .replacement => .{ .replacement_error_returned = false },
            else => .{ .none = {} },
        },
    };
}

// https://encoding.spec.whatwg.org/#concept-encoding-run
/// NeedInput suspends an unfinished stream; the caller retains both queues and
/// the decoder to resume.
/// Fatal decoding errors return InvalidSequence.
pub fn processQueue(
    self: *Decoder,
    allocator: std.mem.Allocator,
    input: *IoQueue(u8),
    output: *IoQueue(u21),
    mode: ErrorMode,
) !ProcessResult {
    while (true) {
        const result = try self.processItem(allocator, try input.read(), input, output, mode);
        if (result != .continue_) return result;
    }
}

// https://encoding.spec.whatwg.org/#concept-encoding-process
pub fn processItem(
    self: *Decoder,
    allocator: std.mem.Allocator,
    item: ?u8,
    input: *IoQueue(u8),
    output: *IoQueue(u21),
    mode: ErrorMode,
) !ProcessResult {
    const result = try self.handler(allocator, input, item);
    return processResult(allocator, output, result, mode);
}

// Decoder error policy is independent of the encoding-specific handler.
fn processResult(allocator: std.mem.Allocator, output: *IoQueue(u21), result: HandlerResult, mode: ErrorMode) !ProcessResult {
    switch (result) {
        .finished => {
            try output.push(allocator, null);
            return .finished;
        },
        .items => |items| {
            for (items) |cp| std.debug.assert(cp <= 0x10FFFF and !ascii.isSurrogate(u21, cp));
            try output.pushSlice(allocator, items);
        },
        .err => switch (mode) {
            .replacement => try output.push(allocator, 0xFFFD),
            .fatal => return error.InvalidSequence,
        },
        .continue_ => {},
    }
    return .continue_;
}

// https://encoding.spec.whatwg.org/#handler
fn handler(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) !HandlerResult {
    return switch (self.encoding) {
        .utf8 => self.handleUtf8(allocator, input, item),
        .ibm866,
        .iso88592,
        .iso88593,
        .iso88594,
        .iso88595,
        .iso88596,
        .iso88597,
        .iso88598,
        .iso88598_i,
        .iso885910,
        .iso885913,
        .iso885914,
        .iso885915,
        .iso885916,
        .koi8r,
        .koi8u,
        .macintosh,
        .windows874,
        .windows1250,
        .windows1251,
        .windows1252,
        .windows1253,
        .windows1254,
        .windows1255,
        .windows1256,
        .windows1257,
        .windows1258,
        .x_mac_cyrillic,
        => self.handleSingleByte(item),
        .gbk, .gb18030 => self.handleGb18030(allocator, input, item),
        .big5 => self.handleBig5(allocator, input, item),
        .eucjp => self.handleEucJp(allocator, input, item),
        .iso2022jp => self.handleIso2022Jp(allocator, input, item),
        .shift_jis => self.handleShiftJis(allocator, input, item),
        .euckr => self.handleEucKr(allocator, input, item),
        .replacement => self.handleReplacement(item),
        .utf16le, .utf16be => self.handleUtf16(allocator, input, item),
        .user_defined => self.handleUserDefined(item),
    };
}

// https://encoding.spec.whatwg.org/#utf-8-decoder
fn handleUtf8(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) !HandlerResult {
    const state = &self.state.utf8;
    const byte = item orelse {
        if (state.bytes_needed != 0) {
            state.bytes_needed = 0;
            return .err;
        }
        return .finished;
    };
    if (state.bytes_needed == 0) {
        switch (byte) {
            0x00...0x7F => return self.emit(byte),
            0xC2...0xDF => {
                state.bytes_needed = 1;
                state.code_point = byte & 0x1F;
            },
            0xE0...0xEF => {
                if (byte == 0xE0) state.lower = 0xA0;
                if (byte == 0xED) state.upper = 0x9F;
                state.bytes_needed = 2;
                state.code_point = byte & 0x0F;
            },
            0xF0...0xF4 => {
                if (byte == 0xF0) state.lower = 0x90;
                if (byte == 0xF4) state.upper = 0x8F;
                state.bytes_needed = 3;
                state.code_point = byte & 0x07;
            },
            else => return .err,
        }
        return .continue_;
    }
    if (byte < state.lower or byte > state.upper) {
        state.* = .{};
        try input.restore(allocator, byte);
        return .err;
    }
    state.lower = 0x80;
    state.upper = 0xBF;
    state.code_point = (state.code_point << 6) | (byte & 0x3F);
    state.bytes_seen += 1;
    if (state.bytes_seen != state.bytes_needed) return .continue_;
    const cp = state.code_point;
    state.code_point = 0;
    state.bytes_needed = 0;
    state.bytes_seen = 0;
    return self.emit(cp);
}

// https://encoding.spec.whatwg.org/#single-byte-decoder
fn handleSingleByte(self: *Decoder, item: ?u8) HandlerResult {
    const byte = item orelse return .finished;
    if (byte < 0x80) return self.emit(byte);
    const cp = indexes.codePoint(indexes.singleByte(self.encoding), byte - 0x80) orelse return .err;
    return self.emit(cp);
}

// https://encoding.spec.whatwg.org/#gb18030-decoder
fn handleGb18030(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) !HandlerResult {
    const state = &self.state.gb18030;
    const byte = item orelse {
        if (state.first == 0 and state.second == 0 and state.third == 0) return .finished;
        state.* = .{};
        return .err;
    };
    if (state.third != 0) {
        if (byte < 0x30 or byte > 0x39) {
            try input.restoreSlice(allocator, &.{ state.second, state.third, byte });
            state.* = .{};
            return .err;
        }
        const pointer = @as(u32, state.first - 0x81) * 12600 + @as(u32, state.second - 0x30) * 1260 + @as(u32, state.third - 0x81) * 10 + byte - 0x30;
        state.* = .{};
        return self.emit(indexes.gb18030RangeCodePoint(pointer) orelse return .err);
    }
    if (state.second != 0) {
        if (byte >= 0x81 and byte <= 0xFE) {
            state.third = byte;
            return .continue_;
        }
        try input.restoreSlice(allocator, &.{ state.second, byte });
        state.first = 0;
        state.second = 0;
        return .err;
    }
    if (state.first != 0) {
        if (byte >= 0x30 and byte <= 0x39) {
            state.second = byte;
            return .continue_;
        }
        const leading = state.first;
        state.first = 0;
        if ((byte >= 0x40 and byte <= 0x7E) or (byte >= 0x80 and byte <= 0xFE)) {
            const offset: u8 = if (byte < 0x7F) 0x40 else 0x41;
            const pointer = @as(usize, leading - 0x81) * 190 + byte - offset;
            if (indexes.codePoint(indexes.gb18030, pointer)) |cp| return self.emit(cp);
        }
        if (byte < 0x80) try input.restore(allocator, byte);
        return .err;
    }
    if (byte < 0x80) return self.emit(byte);
    if (byte == 0x80) return self.emit(0x20AC);
    if (byte >= 0x81 and byte <= 0xFE) {
        state.first = byte;
        return .continue_;
    }
    return .err;
}

// https://encoding.spec.whatwg.org/#big5-decoder
fn handleBig5(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) !HandlerResult {
    const byte = item orelse {
        if (self.state.leading == 0) return .finished;
        self.state.leading = 0;
        return .err;
    };
    if (self.state.leading != 0) {
        const leading = self.state.leading;
        self.state.leading = 0;
        if ((byte >= 0x40 and byte <= 0x7E) or (byte >= 0xA1 and byte <= 0xFE)) {
            const offset: u8 = if (byte < 0x7F) 0x40 else 0x62;
            const pointer = @as(usize, leading - 0x81) * 157 + byte - offset;
            switch (pointer) {
                1133 => return .{ .items = &.{ 0x00CA, 0x0304 } },
                1135 => return .{ .items = &.{ 0x00CA, 0x030C } },
                1164 => return .{ .items = &.{ 0x00EA, 0x0304 } },
                1166 => return .{ .items = &.{ 0x00EA, 0x030C } },
                else => {},
            }
            if (indexes.codePoint(indexes.big5, pointer)) |cp| return self.emit(cp);
        }
        if (byte < 0x80) try input.restore(allocator, byte);
        return .err;
    }
    if (byte < 0x80) return self.emit(byte);
    if (byte >= 0x81 and byte <= 0xFE) {
        self.state.leading = byte;
        return .continue_;
    }
    return .err;
}

// https://encoding.spec.whatwg.org/#euc-jp-decoder
fn handleEucJp(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) !HandlerResult {
    const state = &self.state.euc_jp;
    const byte = item orelse {
        if (state.leading == 0) return .finished;
        state.leading = 0;
        return .err;
    };
    if (state.leading == 0x8E and byte >= 0xA1 and byte <= 0xDF) {
        state.leading = 0;
        return self.emit(0xFF61 + @as(u21, byte - 0xA1));
    }
    if (state.leading == 0x8F and byte >= 0xA1 and byte <= 0xFE) {
        state.jis0212 = true;
        state.leading = byte;
        return .continue_;
    }
    if (state.leading != 0) {
        const leading = state.leading;
        state.leading = 0;
        var cp: ?u21 = null;
        if (leading >= 0xA1 and leading <= 0xFE and byte >= 0xA1 and byte <= 0xFE) {
            const index: []const u21 = if (state.jis0212) indexes.jis0212 else indexes.jis0208;
            cp = indexes.codePoint(index, @as(usize, leading - 0xA1) * 94 + byte - 0xA1);
        }
        state.jis0212 = false;
        if (cp) |value| return self.emit(value);
        if (byte < 0x80) try input.restore(allocator, byte);
        return .err;
    }
    if (byte < 0x80) return self.emit(byte);
    if (byte == 0x8E or byte == 0x8F or (byte >= 0xA1 and byte <= 0xFE)) {
        state.leading = byte;
        return .continue_;
    }
    return .err;
}

/// https://encoding.spec.whatwg.org/#iso-2022-jp-decoder
fn handleIso2022Jp(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) HandlerResult {
    // TODO: §12.2.1.
    _ = self;
    _ = allocator;
    _ = input;
    _ = item;
    @panic("TODO");
}

/// https://encoding.spec.whatwg.org/#shift_jis-decoder
fn handleShiftJis(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) HandlerResult {
    // TODO: §12.3.1.
    _ = self;
    _ = allocator;
    _ = input;
    _ = item;
    @panic("TODO");
}

/// https://encoding.spec.whatwg.org/#euc-kr-decoder
fn handleEucKr(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) HandlerResult {
    // TODO: §13.1.1.
    _ = self;
    _ = allocator;
    _ = input;
    _ = item;
    @panic("TODO");
}

/// https://encoding.spec.whatwg.org/#replacement-decoder
fn handleReplacement(self: *Decoder, item: ?u8) HandlerResult {
    // TODO: §14.1.1.
    _ = self;
    _ = item;
    @panic("TODO");
}

/// https://encoding.spec.whatwg.org/#shared-utf-16-decoder
fn handleUtf16(self: *Decoder, allocator: std.mem.Allocator, input: *IoQueue(u8), item: ?u8) HandlerResult {
    // TODO: §14.2.1
    _ = self;
    _ = allocator;
    _ = input;
    _ = item;
    @panic("TODO");
}

/// https://encoding.spec.whatwg.org/#x-user-defined-decoder
fn handleUserDefined(self: *Decoder, item: ?u8) HandlerResult {
    // TODO: §14.5.1.
    _ = self;
    _ = item;
    @panic("TODO");
}
