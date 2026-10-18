const Font = @This();
const std = @import("std");
const dw = @import("dwrite_zig");
const Metrics = @import("../../Metrics.zig");

pub const Descriptor = dw.Font;

native: dw.FontFace,
descriptor: Descriptor,
size: f64,

/// Loads an installed face by PostScript name, without font substitution.
pub fn initWithName(name: []const u8, size: f64) !Font {
    try validateSize(size);
    const factory = try dw.Factory.init(dw.raw.DWRITE_FACTORY_TYPE_SHARED);
    defer factory.deinit();
    const collection = try factory.getSystemFontCollection(false);
    defer collection.deinit();
    const descriptor = try collection.findFontByPostScriptName(std.heap.page_allocator, name) orelse return error.FontNotFound;
    defer descriptor.deinit();

    return initWithDescriptor(descriptor, size);
}

/// Borrows the descriptor and creates an independently owned font.
pub fn initWithDescriptor(descriptor: Descriptor, size: f64) !Font {
    try validateSize(size);
    return .{
        .native = try descriptor.createFontFace(),
        .descriptor = descriptor.retain(),
        .size = size,
    };
}

pub fn deinit(self: Font) void {
    self.native.deinit();
    self.descriptor.deinit();
}

pub fn retain(self: Font) Font {
    return .{
        .native = self.native.retain(),
        .descriptor = self.descriptor.retain(),
        .size = self.size,
    };
}

pub fn familyName(self: Font, allocator: std.mem.Allocator) ![]u8 {
    const family = try self.descriptor.getFontFamily();
    defer family.deinit();
    const names = try family.getFamilyNames();
    defer names.deinit();

    return localizedName(names, allocator);
}

pub fn postScriptName(self: Font, allocator: std.mem.Allocator) ![]u8 {
    const names = try self.descriptor.getInformationalStrings(dw.raw.DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME) orelse return error.MissingFontName;
    defer names.deinit();
    return localizedName(names, allocator);
}

fn localizedName(names: dw.LocalizedStrings, allocator: std.mem.Allocator) ![]u8 {
    if (names.getCount() == 0) return error.MissingFontName;
    const index = try names.findLocaleName(allocator, "en-us") orelse 0;
    return names.getString(allocator, index);
}

pub fn metrics(self: Font) Metrics {
    const value = self.native.getMetrics();
    if (self.size == 0 or value.designUnitsPerEm == 0) return std.mem.zeroes(Metrics);
    const scale = self.size / @as(f64, @floatFromInt(value.designUnitsPerEm));
    return .{
        .ascent = @as(f64, @floatFromInt(value.ascent)) * scale,
        .descent = @as(f64, @floatFromInt(value.descent)) * scale,
        .leading = @as(f64, @floatFromInt(value.lineGap)) * scale,
        .x_height = @as(f64, @floatFromInt(value.xHeight)) * scale,
        .cap_height = @as(f64, @floatFromInt(value.capHeight)) * scale,
    };
}

fn validateSize(size: f64) !void {
    if (!std.math.isFinite(size) or size < 0 or size > std.math.floatMax(f32)) return error.InvalidFontSize;
    if (size != 0 and @as(f32, @floatCast(size)) == 0) return error.InvalidFontSize;
}
