const Font = @This();
const std = @import("std");
const ft = @import("freetype_zig");
const fc = @import("fontconfig_zig");
const hb = @import("harfbuzz_zig");
const utils = @import("utils.zig");
const Metrics = @import("../../Metrics.zig");

pub const Descriptor = fc.Pattern;

native: ft.Face,
descriptor: Descriptor,
size: f64,
state: *State,

const State = struct {
    references: std.atomic.Value(usize) = .init(1),
    library: ft.Library,
    shaper: hb.Font,
    metrics: Metrics,
};

/// Loads an installed face by PostScript name, without substitution.
pub fn initWithName(name: []const u8, size: f64) !Font {
    try validateSize(size);
    const fonts = try utils.list(fc.raw.FC_POSTSCRIPT_NAME, name);
    defer fonts.deinit();

    for (0..fonts.len()) |i| {
        const descriptor = fonts.get(i).?;
        const actual = try descriptor.getString(fc.raw.FC_POSTSCRIPT_NAME, 0) orelse continue;
        if (std.mem.eql(u8, actual, name)) return initWithDescriptor(descriptor, size);
    }

    return error.FontNotFound;
}

/// Creates a face with independent FreeType size and glyph-slot state.
pub fn initWithDescriptor(descriptor: Descriptor, size: f64) !Font {
    try validateSize(size);
    const library = try ft.Library.init();
    errdefer library.deinit();
    const face = try utils.open(library, descriptor);
    errdefer face.deinit();

    try face.selectCharmap(ft.raw.FT_ENCODING_UNICODE);
    try setSize(face, size);
    const path = try descriptor.getString(fc.raw.FC_FILE, 0) orelse return error.MissingFontFile;
    const index = try descriptor.getInteger(fc.raw.FC_INDEX, 0) orelse return error.MissingFontIndex;
    if (index < 0) return error.InvalidFontIndex;
    const shaper = try hb.Font.init(path, @intCast(index));
    errdefer shaper.deinit();

    const value = try readMetrics(face, size);
    const state = try std.heap.page_allocator.create(State);
    state.* = .{
        .library = library,
        .shaper = shaper,
        .metrics = value,
    };

    return .{
        .native = face,
        .descriptor = descriptor.retain(),
        .size = size,
        .state = state,
    };
}

pub fn deinit(self: Font) void {
    if (self.state.references.fetchSub(1, .acq_rel) != 1) return;
    self.state.shaper.deinit();
    self.native.deinit();
    self.state.library.deinit();
    self.descriptor.deinit();
    std.heap.page_allocator.destroy(self.state);
}

/// Retains the complete face/library lifetime; mutable native state is shared.
pub fn retain(self: Font) Font {
    _ = self.state.references.fetchAdd(1, .monotonic);
    return self;
}

pub fn familyName(self: Font, allocator: std.mem.Allocator) ![]u8 {
    const name = self.native.getFamilyName() orelse
        (try self.descriptor.getString(fc.raw.FC_FAMILY, 0) orelse return error.MissingFontName);

    return allocator.dupe(u8, name);
}

pub fn postScriptName(self: Font, allocator: std.mem.Allocator) ![]u8 {
    const name = self.native.getPostScriptName() orelse
        (try self.descriptor.getString(fc.raw.FC_POSTSCRIPT_NAME, 0) orelse return error.MissingFontName);

    return allocator.dupe(u8, name);
}

pub fn metrics(self: Font) Metrics {
    return self.state.metrics;
}

pub fn shapingFont(self: Font) hb.Font {
    return self.state.shaper;
}

pub fn sizedFace(self: Font, library: ft.Library, size: f64) !ft.Face {
    try validateSize(size);
    const face = try utils.open(library, self.descriptor);
    errdefer face.deinit();
    try setSize(face, size);

    return face;
}

fn validateSize(size: f64) !void {
    if (!std.math.isFinite(size) or size < 0 or size * 64 > std.math.maxInt(i32)) return error.InvalidFontSize;
}

fn setSize(face: ft.Face, size: f64) !void {
    if (face.getMetrics().units_per_em != 0 or face.ref.*.num_fixed_sizes <= 0)
        return face.setCharSize(0, @intFromFloat(@max(1, @round(size * 64))), 72, 72);

    const strikes = face.ref.*.available_sizes[0..@intCast(face.ref.*.num_fixed_sizes)];
    var nearest: usize = 0;
    for (strikes, 0..) |strike, i| {
        if (@abs(@as(f64, @floatFromInt(strike.y_ppem)) / 64 - size) <
            @abs(@as(f64, @floatFromInt(strikes[nearest].y_ppem)) / 64 - size))
            nearest = i;
    }

    const strike = strikes[nearest];
    if (strike.x_ppem <= 0 or strike.y_ppem <= 0) return error.InvalidPixelSize;
    try face.setPixelSizes(
        @intCast(@divTrunc(strike.x_ppem + 32, 64)),
        @intCast(@divTrunc(strike.y_ppem + 32, 64)),
    );
}

fn readMetrics(face: ft.Face, size: f64) !Metrics {
    if (size == 0) return std.mem.zeroes(Metrics);
    const design = face.getMetrics();
    if (design.units_per_em == 0) {
        const scaled = face.getSizeMetrics() orelse return error.MissingFontMetrics;
        if (scaled.y_ppem == 0) return error.MissingFontMetrics;
        const scale = size / (@as(f64, @floatFromInt(scaled.y_ppem)) * 64);
        const ascent = @as(f64, @floatFromInt(scaled.ascender)) * scale;
        return .{
            .ascent = ascent,
            .descent = -@as(f64, @floatFromInt(scaled.descender)) * scale,
            .leading = @as(f64, @floatFromInt(scaled.height - scaled.ascender + scaled.descender)) * scale,
            .x_height = ascent / 2,
            .cap_height = ascent,
        };
    }

    const scale = size / @as(f64, @floatFromInt(design.units_per_em));
    var x_height: f64 = 0;
    var cap_height: f64 = 0;
    if (face.getOS2Table()) |os2| {
        if (os2.version >= 2) {
            x_height = @floatFromInt(@max(0, os2.sxHeight));
            cap_height = @floatFromInt(@max(0, os2.sCapHeight));
        }
    }
    if (x_height == 0) x_height = try glyphHeight(face, 'x');
    if (cap_height == 0) cap_height = try glyphHeight(face, 'H');

    return .{
        .ascent = @as(f64, @floatFromInt(design.ascent)) * scale,
        .descent = -@as(f64, @floatFromInt(design.descent)) * scale,
        .leading = (@as(f64, @floatFromInt(design.height)) - @as(f64, @floatFromInt(design.ascent)) + @as(f64, @floatFromInt(design.descent))) * scale,
        .x_height = x_height * scale,
        .cap_height = cap_height * scale,
    };
}

fn glyphHeight(face: ft.Face, codepoint: u21) !f64 {
    const index = face.getCharIndex(codepoint) orelse return 0;
    const slot = try face.loadGlyph(index, ft.raw.FT_LOAD_NO_SCALE | ft.raw.FT_LOAD_NO_HINTING | ft.raw.FT_LOAD_NO_BITMAP);

    return @floatFromInt(slot.getMetrics().height);
}
