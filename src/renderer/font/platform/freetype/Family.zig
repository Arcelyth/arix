const Family = @This();
const std = @import("std");
const fc = @import("fontconfig_zig");
const ft = @import("freetype_zig");
const utils = @import("utils.zig");
const Font = @import("Font.zig");
const matching = @import("../../matching.zig");
const opentype = @import("../../opentype.zig");

descriptors: fc.FontSet,

pub fn init(name: []const u8) !?Family {
    if (name.len == 0) return null;
    const descriptors = try utils.list(fc.raw.FC_FAMILY, name);
    if (descriptors.len() == 0) {
        descriptors.deinit();
        return null;
    }

    return .{ .descriptors = descriptors };
}

pub fn deinit(self: Family) void {
    self.descriptors.deinit();
}

/// Selects the closest static face using the shared CSS matching rules.
pub fn match(self: Family, allocator: std.mem.Allocator, request: matching.Attributes) !?Font.Descriptor {
    const library = try ft.Library.init();
    defer library.deinit();
    var best: ?Font.Descriptor = null;
    var best_attributes: matching.Attributes = undefined;
    for (0..self.descriptors.len()) |i| {
        const descriptor = self.descriptors.get(i).?;
        const attributes = try faceAttributes(allocator, library, descriptor);
        if (best == null or matching.compare(request, attributes, best_attributes) == .lt) {
            best = descriptor;
            best_attributes = attributes;
        }
    }

    return if (best) |descriptor| descriptor.retain() else null;
}

fn faceAttributes(allocator: std.mem.Allocator, library: ft.Library, descriptor: Font.Descriptor) !matching.Attributes {
    const face = try utils.open(library, descriptor);
    defer face.deinit();
    const os2 = try face.copyTable(allocator, 0x4f532f32);
    defer if (os2) |bytes| allocator.free(bytes);

    const classification = if (os2) |bytes| opentype.classification(bytes) else null;
    const post = try face.copyTable(allocator, 0x706f7374);
    defer if (post) |bytes| allocator.free(bytes);

    const slant = try descriptor.getInteger(fc.raw.FC_SLANT, 0) orelse fc.raw.FC_SLANT_ROMAN;
    const angle = if (post) |bytes| opentype.slant(bytes) orelse 0 else if (slant == fc.raw.FC_SLANT_OBLIQUE) @as(f64, 14) else 0;
    const style: matching.Style = blk: {
        if (classification) |value| {
            if (value.oblique) break :blk .{ .oblique = angle };
            if (value.italic) break :blk if (angle < 0) .right else .italic;
        }
        if (slant == fc.raw.FC_SLANT_ITALIC) break :blk if (angle < 0) .right else .italic;
        if (slant == fc.raw.FC_SLANT_OBLIQUE or angle != 0) break :blk .{ .oblique = angle };

        break :blk .normal;
    };

    return .{
        .weight = if (classification) |value| value.weight else @floatFromInt(fc.weightToOpenType(try descriptor.getInteger(fc.raw.FC_WEIGHT, 0) orelse fc.raw.FC_WEIGHT_REGULAR) orelse 400),
        .width = if (classification) |value| value.width else @floatFromInt(try descriptor.getInteger(fc.raw.FC_WIDTH, 0) orelse fc.raw.FC_WIDTH_NORMAL),
        .style = style,
    };
}
