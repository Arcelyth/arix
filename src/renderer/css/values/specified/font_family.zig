const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");
const String = @import("../../String.zig");
const Function = @import("../../syntax/parsing_results.zig").Function;
const custom_ident = @import("custom_ident.zig");

/// https://www.w3.org/TR/css-fonts-4/#typedef-generic-font-family
pub const Generic = enum {
    serif,
    @"sans-serif",
    @"system-ui",
    cursive,
    fantasy,
    math,
    monospace,

    @"ui-serif",
    @"ui-sans-serif",
    @"ui-monospace",
    @"ui-rounded",

    fangsong,
    kai,
    @"khmer-mul",
    nastaliq,

    /// These names require generic(name) in CSS.
    fn isScriptSpecific(self: Generic) bool {
        return switch (self) {
            .fangsong, .kai, .@"khmer-mul", .nastaliq => true,
            else => false,
        };
    }
};

pub const Family = union(enum) {
    name: []const u8,
    generic: Generic,
};

pub const FontFamily = struct {
    families: []const Family,

    pub fn deinit(self: FontFamily, allocator: std.mem.Allocator) void {
        for (self.families) |family| freeFamily(allocator, family);
        allocator.free(self.families);
    }
};

pub fn parse(allocator: std.mem.Allocator, input: *Stream) !?FontFamily {
    var families: std.ArrayList(Family) = .empty;
    defer families.deinit(allocator);

    var success = false;
    defer if (!success) {
        for (families.items) |family| freeFamily(allocator, family);
    };

    while (true) {
        const family = (try parseFamily(allocator, input)) orelse return null;
        try appendFamily(allocator, &families, family);
        input.discardWhitespace();
        if (!input.isToken(.comma)) break;
        input.advance();
        input.discardWhitespace();
    }
    const result = try families.toOwnedSlice(allocator);
    success = true;
    return .{ .families = result };
}

fn appendFamily(
    allocator: std.mem.Allocator,
    families: *std.ArrayList(Family),
    family: Family,
) !void {
    errdefer freeFamily(allocator, family);
    try families.append(allocator, family);
}

fn freeFamily(allocator: std.mem.Allocator, family: Family) void {
    if (family == .name) allocator.free(family.name);
}

fn parseFamily(allocator: std.mem.Allocator, input: *Stream) !?Family {
    if (parseGeneric(input)) |generic| return .{ .generic = generic };
    return parseName(allocator, input);
}

fn parseGeneric(input: *Stream) ?Generic {
    const value = input.peek() orelse return null;
    const result: Generic = if (value.* == .function)
        parseGenericFunction(value.function) orelse return null
    else result: {
        const token = input.peekToken() orelse return null;
        if (token.* != .ident) return null;
        break :result keyword(token.ident, false) orelse return null;
    };
    input.advance();
    return result;
}

fn parseGenericFunction(function: Function) ?Generic {
    if (!function.name.eqlAscii("generic")) return null;
    var arguments = Stream.init(function.value);
    arguments.discardWhitespace();
    const name = arguments.consumeIdent() orelse return null;
    arguments.discardWhitespace();
    if (!arguments.empty()) return null;
    return keyword(name, true);
}

fn keyword(name: String, functional: bool) ?Generic {
    inline for (std.enums.values(Generic)) |value| {
        if (value.isScriptSpecific() == functional and name.eqlAscii(@tagName(value)))
            return value;
    }
    return null;
}

/// Font family names other than generic families or system font families
/// must either be given quoted as string, or unquoted as identifier .
fn parseName(allocator: std.mem.Allocator, input: *Stream) !?Family {
    var name: std.ArrayList(u8) = .empty;
    defer name.deinit(allocator);
    const token = input.peekToken() orelse return null;
    if (token.* == .string) {
        input.advance();
        try appendString(allocator, &name, token.string);
    } else if (!try appendIdentifiers(allocator, input, &name)) return null;
    return .{ .name = try name.toOwnedSlice(allocator) };
}

/// Require at least one identifier, then join the rest with single spaces.
fn appendIdentifiers(allocator: std.mem.Allocator, input: *Stream, name: *std.ArrayList(u8)) !bool {
    const first = custom_ident.parse(input) orelse return false;
    try appendString(allocator, name, first);
    input.discardWhitespace();
    while (input.isToken(.ident)) {
        const part = custom_ident.parse(input) orelse return false;
        try name.append(allocator, ' ');
        try appendString(allocator, name, part);
        input.discardWhitespace();
    }
    return true;
}

fn appendString(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: String) !void {
    switch (value.value) {
        .borrowed => |bytes| try output.appendSlice(allocator, bytes),
        .owned => |points| for (points) |point| {
            var bytes: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(point, &bytes) catch unreachable;
            try output.appendSlice(allocator, bytes[0..len]);
        },
    }
}
