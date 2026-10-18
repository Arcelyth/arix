const Family = @This();
const std = @import("std");
const dw = @import("dwrite_zig");
const Font = @import("Font.zig");
const matching = @import("../../matching.zig");
const opentype = @import("../../opentype.zig");

native: dw.FontFamily,

pub fn init(name: []const u8) !?Family {
    const factory = try dw.Factory.init(dw.raw.DWRITE_FACTORY_TYPE_SHARED);
    defer factory.deinit();
    const collection = try factory.getSystemFontCollection(false);
    defer collection.deinit();
    const index = try collection.findFamilyName(std.heap.page_allocator, name) orelse return null;

    return .{ .native = try collection.getFontFamily(index) };
}

pub fn deinit(self: Family) void {
    self.native.deinit();
}

/// Returns an owned closest static face, using the shared CSS matching rules.
pub fn match(self: Family, _: std.mem.Allocator, request: matching.Attributes) !?Font.Descriptor {
    var best: ?Font.Descriptor = null;
    errdefer if (best) |font| font.deinit();
    var best_attributes: matching.Attributes = undefined;
    for (0..self.native.getFontCount()) |i| {
        const font = try self.native.getFont(@intCast(i));
        defer font.deinit();
        if (font.getSimulations() != dw.raw.DWRITE_FONT_SIMULATIONS_NONE) continue;

        const attributes = try faceAttributes(font);
        if (best == null or matching.compare(request, attributes, best_attributes) == .lt) {
            if (best) |previous| previous.deinit();
            best = font.retain();
            best_attributes = attributes;
        }
    }
    return best;
}

fn faceAttributes(font: dw.Font) !matching.Attributes {
    const face = try font.createFontFace();
    defer face.deinit();
    const os2 = try face.tryGetFontTable(std.mem.readInt(u32, "OS/2", .little));
    defer if (os2) |table| table.deinit();

    const classification = if (os2) |table| opentype.classification(table.bytes) else null;
    const post = try face.tryGetFontTable(std.mem.readInt(u32, "post", .little));
    defer if (post) |table| table.deinit();

    const angle = if (post) |table| opentype.slant(table.bytes) orelse 0 else 0;
    const widths = [_]f64{ 100, 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200 };
    const stretch = font.getStretch();
    const style: matching.Style = blk: {
        if (classification) |value| {
            if (value.oblique) break :blk .{ .oblique = angle };
            if (value.italic) break :blk if (angle < 0) .right else .italic;
        }
        if (font.getStyle() == dw.raw.DWRITE_FONT_STYLE_ITALIC)
            break :blk if (angle < 0) .right else .italic;
        if (font.getStyle() == dw.raw.DWRITE_FONT_STYLE_OBLIQUE or angle != 0)
            break :blk .{ .oblique = angle };
        break :blk .normal;
    };

    return .{
        .weight = if (classification) |value| value.weight else @floatFromInt(font.getWeight()),
        .width = if (classification) |value| value.width else if (stretch < widths.len) widths[stretch] else 100,
        .style = style,
    };
}
