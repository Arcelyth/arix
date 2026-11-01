const Encoder = @This();
const std = @import("std");
const Encoding = @import("encoding.zig").Encoding;
const IoQueue = @import("queue.zig").IoQueue;
const indexes = @import("indexes.zig");
const ascii = @import("../utils/ascii.zig");

pub const HandlerResult = union(enum) {
    finished,
    items: []const u8,
    err: u21,
};

const Iso2022JpState = enum { ascii, roman, jis0208 };

encoding: Encoding,
iso2022jp_state: Iso2022JpState = .ascii,
// The handler's bytes stay valid until they are appended to the output queue.
bytes: [4]u8 = undefined,

/// Gets an encoder. Replacement and UTF-16 have no encoders.
/// https://encoding.spec.whatwg.org/#get-an-encoder
pub fn init(encoding: Encoding) Encoder {
    std.debug.assert(encoding != .replacement and encoding != .utf16le and encoding != .utf16be);
    return .{ .encoding = encoding };
}

/// Encodes until end-of-queue or an unencodable code point.
/// The encoder keeps its state when an error is returned.
/// https://encoding.spec.whatwg.org/#encode-or-fail
pub fn encodeOrFail(
    self: *Encoder,
    allocator: std.mem.Allocator,
    input: *IoQueue(u21),
    output: *IoQueue(u8),
) !?u21 {
    const potential_error = try self.processQueue(allocator, input, output);
    try output.push(allocator, null);
    return potential_error;
}

/// Processes a queue in fatal error mode, returning the offending code point.
/// https://encoding.spec.whatwg.org/#concept-encoding-run
pub fn processQueue(
    self: *Encoder,
    allocator: std.mem.Allocator,
    input: *IoQueue(u21),
    output: *IoQueue(u8),
) !?u21 {
    while (true) {
        switch (try self.handler(allocator, input, try input.read())) {
            .finished => {
                try output.push(allocator, null);
                return null;
            },
            .items => |bytes| try output.pushSlice(allocator, bytes),
            .err => |cp| return cp,
        }
    }
}

pub fn emit(self: *Encoder, bytes: []const u8) HandlerResult {
    @memcpy(self.bytes[0..bytes.len], bytes);
    return .{ .items = self.bytes[0..bytes.len] };
}

/// Runs the selected encoding's handler for one scalar or end-of-queue.
pub fn handler(
    self: *Encoder,
    allocator: std.mem.Allocator,
    input: *IoQueue(u21),
    item: ?u21,
) !HandlerResult {
    if (item) |cp| std.debug.assert(cp <= 0x10FFFF and !ascii.isSurrogate(u21, cp));
    if (self.encoding == .iso2022jp) return self.handleIso2022Jp(allocator, input, item);
    const cp = item orelse return .finished;
    return switch (self.encoding) {
        .utf8 => .{ .items = self.bytes[0..try std.unicode.utf8Encode(cp, &self.bytes)] },
        .gbk, .gb18030 => self.handleGb18030(cp),
        .big5 => self.handleBig5(cp),
        .eucjp => self.handleEucJp(cp),
        .shift_jis => self.handleShiftJis(cp),
        .euckr => self.handleEucKr(cp),
        .user_defined => self.handleUserDefined(cp),
        .replacement, .utf16le, .utf16be, .iso2022jp => unreachable,
        else => self.handleSingleByte(cp),
    };
}

/// https://encoding.spec.whatwg.org/#single-byte-encoder
pub fn handleSingleByte(self: *Encoder, cp: u21) HandlerResult {
    if (cp < 0x80) return self.emit(&.{@intCast(cp)});
    const pointer = indexes.pointer(indexes.singleByte(self.encoding), cp) orelse return .{ .err = cp };
    return self.emit(&.{@intCast(pointer + 0x80)});
}

/// https://encoding.spec.whatwg.org/#x-user-defined-encoder
pub fn handleUserDefined(self: *Encoder, cp: u21) HandlerResult {
    if (cp < 0x80) return self.emit(&.{@intCast(cp)});
    if (cp >= 0xF780 and cp <= 0xF7FF) return self.emit(&.{@intCast(cp - 0xF780 + 0x80)});
    return .{ .err = cp };
}

/// https://encoding.spec.whatwg.org/#gb18030-encoder
pub fn handleGb18030(self: *Encoder, cp: u21) HandlerResult {
    _ = self;
    _ = cp;
}

/// https://encoding.spec.whatwg.org/#big5-encoder
pub fn handleBig5(self: *Encoder, cp: u21) HandlerResult {
    _ = self;
    _ = cp;
}

/// https://encoding.spec.whatwg.org/#euc-jp-encoder
pub fn handleEucJp(self: *Encoder, original: u21) HandlerResult {
    _ = self;
    _ = original;
}

/// https://encoding.spec.whatwg.org/#shift_jis-encoder
pub fn handleShiftJis(self: *Encoder, original: u21) HandlerResult {
    _ = self;
    _ = original;
}

/// https://encoding.spec.whatwg.org/#euc-kr-encoder
pub fn handleEucKr(self: *Encoder, cp: u21) HandlerResult {
    _ = self;
    _ = cp;
}

/// Keeps ISO-2022-JP's ASCII, Roman, or JIS state across queue processing.
/// https://encoding.spec.whatwg.org/#iso-2022-jp-encoder
pub fn handleIso2022Jp(
    self: *Encoder,
    allocator: std.mem.Allocator,
    input: *IoQueue(u21),
    item: ?u21,
) !HandlerResult {
    _ = self;
    _ = allocator;
    _ = input;
    _ = item;
}

/// The compatibility rows in the gb18030 encoder's step.
pub const gb18030_compatibility = [_]struct { codepoint: u21, bytes: [2]u8 }{
    .{ .codepoint = 0xE78D, .bytes = .{ 0xA6, 0xD9 } },
    .{ .codepoint = 0xE78E, .bytes = .{ 0xA6, 0xDA } },
    .{ .codepoint = 0xE78F, .bytes = .{ 0xA6, 0xDB } },
    .{ .codepoint = 0xE790, .bytes = .{ 0xA6, 0xDC } },
    .{ .codepoint = 0xE791, .bytes = .{ 0xA6, 0xDD } },
    .{ .codepoint = 0xE792, .bytes = .{ 0xA6, 0xDE } },
    .{ .codepoint = 0xE793, .bytes = .{ 0xA6, 0xDF } },
    .{ .codepoint = 0xE794, .bytes = .{ 0xA6, 0xEC } },
    .{ .codepoint = 0xE795, .bytes = .{ 0xA6, 0xED } },
    .{ .codepoint = 0xE796, .bytes = .{ 0xA6, 0xF3 } },
    .{ .codepoint = 0xE81E, .bytes = .{ 0xFE, 0x59 } },
    .{ .codepoint = 0xE826, .bytes = .{ 0xFE, 0x61 } },
    .{ .codepoint = 0xE82B, .bytes = .{ 0xFE, 0x66 } },
    .{ .codepoint = 0xE82C, .bytes = .{ 0xFE, 0x67 } },
    .{ .codepoint = 0xE832, .bytes = .{ 0xFE, 0x6D } },
    .{ .codepoint = 0xE843, .bytes = .{ 0xFE, 0x7E } },
    .{ .codepoint = 0xE854, .bytes = .{ 0xFE, 0x90 } },
    .{ .codepoint = 0xE864, .bytes = .{ 0xFE, 0xA0 } },
};
