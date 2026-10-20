const std = @import("std");
const fc = @import("fontconfig_zig");
const ft = @import("freetype_zig");

/// Exact installed-face lookup.
pub fn list(object: [*:0]const u8, name: []const u8) !fc.FontSet {
    if (!std.unicode.utf8ValidateSlice(name)) return error.InvalidUtf8;
    const config = try fc.Config.init();
    defer config.deinit();
    const query = try fc.Pattern.init();
    defer query.deinit();
    try query.addString(std.heap.page_allocator, object, name);
    const objects = try fc.ObjectSet.init(&.{
        fc.raw.FC_FILE,    fc.raw.FC_INDEX,  fc.raw.FC_FAMILY, fc.raw.FC_POSTSCRIPT_NAME,
        fc.raw.FC_CHARSET, fc.raw.FC_WEIGHT, fc.raw.FC_WIDTH,  fc.raw.FC_SLANT,
    });
    defer objects.deinit();

    return config.listFonts(query, objects);
}

pub fn open(library: ft.Library, descriptor: fc.Pattern) !ft.Face {
    const path = try descriptor.getString(fc.raw.FC_FILE, 0) orelse return error.MissingFontFile;
    const index = try descriptor.getInteger(fc.raw.FC_INDEX, 0) orelse return error.MissingFontIndex;
    if (index < 0) return error.InvalidFontIndex;

    return library.newFace(path, index);
}

pub fn sameFace(a: fc.Pattern, b: fc.Pattern) !bool {
    if (try a.getInteger(fc.raw.FC_INDEX, 0) != try b.getInteger(fc.raw.FC_INDEX, 0)) return false;
    const a_path = try a.getString(fc.raw.FC_FILE, 0) orelse return false;
    const b_path = try b.getString(fc.raw.FC_FILE, 0) orelse return false;

    return std.mem.eql(u8, a_path, b_path);
}
