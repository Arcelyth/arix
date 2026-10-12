const Font = @This();

const std = @import("std");
const core = @import("core_foundation_zig");
const cf = core.core_foundation;
const ct = core.core_text;
const Metrics = @import("../../Metrics.zig");

pub const Descriptor = ct.CTFontDescriptor;

native: ct.CTFont,
/// Requested CSS size. Core Text uses a native default when this is zero.
size: f64,

/// Loads an installed face by PostScript name. The caller owns the font.
pub fn initWithName(name: []const u8, size: f64) !Font {
    try validateSize(size);
    const descriptor = try findByName(name, size);
    defer descriptor.deinit();
    return initWithDescriptor(descriptor, size);
}

/// Borrows the descriptor and creates an independently owned font.
pub fn initWithDescriptor(descriptor: Descriptor, size: f64) error{InvalidFontSize}!Font {
    try validateSize(size);
    return .{ .native = ct.CTFont.initWithDescriptor(descriptor, size), .size = size };
}

pub fn deinit(self: Font) void {
    self.native.deinit();
}

/// Returns owned UTF-8 bytes. Free them with allocator.free().
pub fn familyName(self: Font, allocator: std.mem.Allocator) ![]u8 {
    const name = self.native.copyFamilyName();
    defer name.deinit();
    return name.toSlice(allocator);
}

/// Returns owned UTF-8 bytes. Free them with allocator.free().
pub fn postScriptName(self: Font, allocator: std.mem.Allocator) ![]u8 {
    const name = self.native.copyPostScriptName();
    defer name.deinit();
    return name.toSlice(allocator);
}

pub fn metrics(self: Font) Metrics {
    if (self.size == 0) return std.mem.zeroes(Metrics);
    return .{
        .ascent = self.native.getAscent(),
        .descent = self.native.getDescent(),
        .leading = self.native.getLeading(),
        .x_height = self.native.getXHeight(),
        .cap_height = self.native.getCapHeight(),
    };
}

fn findByName(name: []const u8, size: f64) !Descriptor {
    const query = try Descriptor.initWithNameAndSize(name, size);
    defer query.deinit();
    const mandatory = try cf.CFSet(cf.CFString).init(&.{
        cf.CFString.fromRef(core.raw.kCTFontNameAttribute),
    });
    defer mandatory.deinit();
    return query.createMatchingFontDescriptor(mandatory) orelse error.FontNotFound;
}

fn validateSize(size: f64) error{InvalidFontSize}!void {
    if (!std.math.isFinite(size) or size < 0) return error.InvalidFontSize;
}
