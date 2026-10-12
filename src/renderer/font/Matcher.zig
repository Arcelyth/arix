const Matcher = @This();
const std = @import("std");
const backend = @import("platform.zig").backend;
const matching = @import("matching.zig");
const font_family = @import("../css/values/specified/font_family.zig");
const ComputedValues = @import("../css/properties/registry.zig").ComputedValues;

pub const GenericFamily = struct {
    generic: font_family.Generic,
    families: []const []const u8,
};

/// Borrowed UA preferences. Callers choose names appropriate to language and platform.
generic_families: []const GenericFamily = &.{},
fallback_families: []const []const u8 = &.{},

/// Returns an owned font, or null when none of the requested/configured families exists.
pub fn match(self: Matcher, allocator: std.mem.Allocator, style: *const ComputedValues) !?backend.Font {
    // font-width is not a computed property yet; use its initial normal width.
    const request: matching.Attributes = .{ .weight = style.font_weight, .style = style.font_style };
    for (style.font_family.families) |family| {
        const result = switch (family) {
            .name => |name| try matchFamily(allocator, name, request, style.font_size),
            .generic => |generic| try self.matchGeneric(allocator, generic, request, style.font_size),
        };
        if (result) |font| return font;
    }
    return matchNames(allocator, self.fallback_families, request, style.font_size);
}

fn matchGeneric(self: Matcher, allocator: std.mem.Allocator, generic: font_family.Generic, request: matching.Attributes, size: f64) !?backend.Font {
    for (self.generic_families) |mapping| {
        if (mapping.generic == generic)
            if (try matchNames(allocator, mapping.families, request, size)) |font| return font;
    }
    return null;
}

fn matchNames(allocator: std.mem.Allocator, names: []const []const u8, request: matching.Attributes, size: f64) !?backend.Font {
    for (names) |name| {
        if (try matchFamily(allocator, name, request, size)) |font| return font;
    }
    return null;
}

fn matchFamily(allocator: std.mem.Allocator, name: []const u8, request: matching.Attributes, size: f64) !?backend.Font {
    const family = try backend.Family.init(name) orelse return null;
    defer family.deinit();
    const descriptor = try family.match(allocator, request) orelse return null;
    defer descriptor.deinit();
    return try backend.Font.initWithDescriptor(descriptor, size);
}
