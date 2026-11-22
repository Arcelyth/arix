//! A style sheet's ordered collection of media queries.
//! https://drafts.csswg.org/cssom/#the-medialist-interface
const MediaList = @This();
const std = @import("std");
const query = @import("media_query.zig");
const MediaQuery = @import("MediaQuery.zig");
const Allocator = std.mem.Allocator;

queries: std.ArrayList(MediaQuery) = .empty,

/// Creates a media list from its CSS text.
/// https://drafts.csswg.org/cssom/#create-a-medialist-object
pub fn init(allocator: Allocator, text: []const u8) !MediaList {
    return .{
        .queries = try query.parseList(allocator, text),
    };
}

pub fn deinit(self: *MediaList, allocator: Allocator) void {
    for (self.queries.items) |*medium| medium.deinit();
    self.queries.deinit(allocator);
}

/// Writes the queries in list order.
/// https://drafts.csswg.org/cssom/#serialize-a-media-query-list
pub fn serialize(self: *const MediaList, writer: *std.Io.Writer) !void {
    for (self.queries.items, 0..) |medium, i| {
        if (i != 0) try writer.writeAll(", ");
        try medium.serialize(writer);
    }
}

/// Replaces the list. A null value clears it.
pub fn setMediaText(self: *MediaList, allocator: Allocator, text: ?[]const u8) !void {
    const replacement = try init(allocator, text orelse "");
    self.deinit(allocator);
    self.* = replacement;
}

/// Returns the number of queries.
/// https://drafts.csswg.org/cssom/#dom-medialist-length
pub fn length(self: *const MediaList) u32 {
    return @intCast(self.queries.items.len);
}

/// Returns the serialized query at index, or null if the index is out of range.
/// https://drafts.csswg.org/cssom/#dom-medialist-item
/// Free the result with allocator.free.
pub fn item(self: *const MediaList, allocator: Allocator, index: u32) !?[]u8 {
    if (index >= self.length()) return null;
    return try self.queries.items[index].toString(allocator);
}

/// Adds one query unless it already appears in the list.
/// https://drafts.csswg.org/cssom/#dom-medialist-appendmedium
pub fn appendMedium(self: *MediaList, allocator: Allocator, text: []const u8) !void {
    var medium = try query.parseOne(allocator, text) orelse return;
    errdefer medium.deinit();
    for (self.queries.items) |*entry| {
        if (try entry.matches(&medium)) {
            medium.deinit();
            return;
        }
    }
    try self.queries.append(allocator, medium);
}

/// Removes every matching query. A missing query raises NotFoundError.
/// https://drafts.csswg.org/cssom/#dom-medialist-deletemedium
pub fn deleteMedium(self: *MediaList, allocator: Allocator, text: []const u8) !void {
    var medium = try query.parseOne(allocator, text) orelse return;
    defer medium.deinit();

    // Finish all comparisons before removing entries so an allocation error leaves the list intact.
    const remove = try allocator.alloc(bool, self.queries.items.len);
    defer allocator.free(remove);
    for (self.queries.items, remove) |*entry, *matched| matched.* = try entry.matches(&medium);

    var kept: usize = 0;
    for (self.queries.items, remove) |*entry, matched| {
        if (matched) {
            entry.deinit();
        } else {
            self.queries.items[kept] = entry.*;
            kept += 1;
        }
    }
    if (kept == self.queries.items.len) return error.NotFoundError;
    self.queries.shrinkRetainingCapacity(kept);
}

test "CSSOM MediaList updates and serializes queries" {
    const allocator = std.testing.allocator;
    var media = try init(allocator, "SCREEN, all and (min-WIDTH:05PX), screen");
    defer media.deinit(allocator);
    try media.appendMedium(allocator, "Screen");
    try media.deleteMedium(allocator, "screen");
    try media.appendMedium(allocator, "print, speech");
    try media.appendMedium(allocator, "print");
    try std.testing.expectEqual(@as(u32, 2), media.length());
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try media.serialize(&output.writer);
    try std.testing.expectEqualStrings("(min-width: 5px), print", output.written());
    try std.testing.expectError(error.NotFoundError, media.deleteMedium(allocator, "screen"));
    try media.setMediaText(allocator, null);
    try std.testing.expect(try media.item(allocator, 0) == null);
}
