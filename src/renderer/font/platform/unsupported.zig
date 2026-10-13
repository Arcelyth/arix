const std = @import("std");
const Metrics = @import("../Metrics.zig");
const ShapedText = @import("../ShapedText.zig");
const matching = @import("../matching.zig");

/// Placeholder until a font backend is available for this platform.
pub const Font = struct {
    size: f64,

    pub const Descriptor = struct {
        pub fn deinit(_: Descriptor) void {}
    };

    pub fn initWithName(_: []const u8, _: f64) !Font {
        return error.UnsupportedPlatform;
    }

    pub fn initWithDescriptor(_: Descriptor, _: f64) !Font {
        return error.UnsupportedPlatform;
    }

    pub fn deinit(_: Font) void {}

    pub fn retain(self: Font) Font {
        return self;
    }

    pub fn familyName(_: Font, _: std.mem.Allocator) ![]u8 {
        return error.UnsupportedPlatform;
    }

    pub fn postScriptName(_: Font, _: std.mem.Allocator) ![]u8 {
        return error.UnsupportedPlatform;
    }

    pub fn metrics(_: Font) Metrics {
        return std.mem.zeroes(Metrics);
    }
};

pub const Family = struct {
    pub fn init(_: []const u8) !?Family {
        return error.UnsupportedPlatform;
    }

    pub fn deinit(_: Family) void {}

    pub fn match(_: Family, _: std.mem.Allocator, _: matching.Attributes) !?Font.Descriptor {
        return error.UnsupportedPlatform;
    }
};

pub fn shape(_: std.mem.Allocator, _: []const u8, _: Font, _: ShapedText.Direction) !ShapedText {
    return error.UnsupportedPlatform;
}

pub fn lineBreaks(_: std.mem.Allocator, _: []const u8) ![]usize {
    return error.UnsupportedPlatform;
}
