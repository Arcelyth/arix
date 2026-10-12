const Family = @This();

const std = @import("std");
const core = @import("core_foundation_zig");
const cf = core.core_foundation;
const ct = core.core_text;
const matching = @import("../../matching.zig");
const opentype = @import("../../opentype.zig");
const Font = @import("Font.zig");

descriptors: cf.CFArray(Font.Descriptor),

pub fn init(name: []const u8) !?Family {
    const collection = ct.CTFontCollection.initFromAvailableFonts(null);
    defer collection.deinit();
    const descriptors = try collection.createMatchingFontDescriptorsForFamily(name, null) orelse return null;
    return .{ .descriptors = descriptors };
}

pub fn deinit(self: Family) void {
    self.descriptors.deinit();
}

/// Returns the closest static face.
pub fn match(self: Family, allocator: std.mem.Allocator, request: matching.Attributes) !?Font.Descriptor {
    var best: ?Font.Descriptor = null;
    var best_attributes: matching.Attributes = undefined;
    for (0..self.descriptors.len()) |i| {
        const descriptor = self.descriptors.get(i).?;
        const attributes = try faceAttributes(allocator, descriptor);
        if (best == null or matching.compare(request, attributes, best_attributes) == .lt) {
            best = descriptor;
            best_attributes = attributes;
        }
    }
    return if (best) |descriptor| descriptor.retain() else null;
}

fn faceAttributes(allocator: std.mem.Allocator, descriptor: Font.Descriptor) !matching.Attributes {
    const native = ct.CTFont.initWithDescriptor(descriptor, 0);
    defer native.deinit();

    const classification = try readClassification(allocator, native);
    const angle = try readSlant(allocator, native);
    const symbolic = native.getSymbolicTraits();
    // For legacy faces, map Core Text's categorical traits to CSS keyword values.
    return .{
        .weight = if (classification) |value| value.weight else if (symbolic.bold) 700 else 400,
        .width = if (classification) |value| value.width else if (symbolic.condensed) 75 else if (symbolic.expanded) 125 else 100,
        .style = faceStyle(classification, symbolic.italic, angle),
    };
}

fn faceStyle(classification: ?opentype.Classification, italic: bool, angle: f64) matching.Style {
    if (classification) |value| {
        if (value.oblique) return .{ .oblique = angle };
        if (value.italic) return if (angle < 0) .right else .italic;
    }
    if (italic) return if (angle < 0) .right else .italic;
    return if (angle == 0) .normal else .{ .oblique = angle };
}

fn readClassification(allocator: std.mem.Allocator, native: ct.CTFont) !?opentype.Classification {
    const data = native.copyTable(core.raw.kCTFontTableOS2, core.raw.kCTFontTableOptionNoOptions) orelse return null;
    defer data.deinit();
    const bytes = try data.toSlice(allocator);
    defer allocator.free(bytes);
    return opentype.classification(bytes);
}

fn readSlant(allocator: std.mem.Allocator, native: ct.CTFont) !f64 {
    const data = native.copyTable(core.raw.kCTFontTablePost, core.raw.kCTFontTableOptionNoOptions) orelse return 0;
    defer data.deinit();
    const bytes = try data.toSlice(allocator);
    defer allocator.free(bytes);
    return opentype.slant(bytes) orelse 0;
}
