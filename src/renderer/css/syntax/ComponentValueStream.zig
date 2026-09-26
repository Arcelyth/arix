const ComponentValueStream = @This();

const String = @import("../String.zig");
const ComponentValue = @import("parsing_results.zig").ComponentValue;
const PreservedToken = @import("parsing_results.zig").PreservedToken;

values: []const ComponentValue,
index: usize = 0,

pub fn init(values: []const ComponentValue) ComponentValueStream {
    return .{ .values = values };
}

// https://drafts.csswg.org/css-syntax/#token-stream
/// Component values contain no EOF variant; null denotes exhaustion.
pub inline fn peek(self: *const ComponentValueStream) ?*const ComponentValue {
    return if (self.index < self.values.len) &self.values[self.index] else null;
}

pub inline fn peekToken(self: *const ComponentValueStream) ?*const PreservedToken {
    const value = self.peek() orelse return null;
    return if (value.* == .preserved_token) &value.preserved_token else null;
}

pub inline fn consume(self: *ComponentValueStream) ?*const ComponentValue {
    const value = self.peek() orelse return null;
    self.index += 1;
    return value;
}

pub inline fn advance(self: *ComponentValueStream) void {
    if (!self.empty()) self.index += 1;
}

/// Restore an index.
pub inline fn restore(self: *ComponentValueStream, index: usize) void {
    self.index = index;
}

pub inline fn empty(self: *const ComponentValueStream) bool {
    return self.index >= self.values.len;
}

pub inline fn discardWhitespace(self: *ComponentValueStream) void {
    while (self.peek()) |value| {
        if (value.* != .preserved_token or value.preserved_token != .whitespace) return;
        self.index += 1;
    }
}

pub inline fn consumeIdent(self: *ComponentValueStream) ?String {
    const value = self.peek() orelse return null;
    if (value.* != .preserved_token or value.preserved_token != .ident) return null;
    self.index += 1;
    return value.preserved_token.ident;
}

pub inline fn isDelimAt(self: *const ComponentValueStream, offset: usize, cp: u21) bool {
    if (offset >= self.values.len - self.index) return false;
    const value = self.values[self.index + offset];
    return value == .preserved_token and value.preserved_token == .delim and value.preserved_token.delim == cp;
}

pub inline fn consumeDelim(self: *ComponentValueStream, cp: u21) bool {
    if (!isDelimAt(self, 0, cp)) return false;
    self.advance();
    return true;
}
