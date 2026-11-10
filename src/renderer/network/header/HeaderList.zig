//! An ordered list of HTTP headers. Duplicate names are allowed.
//! https://fetch.spec.whatwg.org/#concept-header-list
const HeaderList = @This();
const std = @import("std");
const header = @import("header.zig");
pub const Header = header.Header;

allocator: std.mem.Allocator,
entries: std.ArrayList(Header) = .empty,

pub fn init(allocator: std.mem.Allocator) HeaderList {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *HeaderList) void {
    self.entries.deinit(self.allocator);
}

/// Checks for a name without regard to ASCII case.
/// https://fetch.spec.whatwg.org/#header-list-contains
pub fn contains(self: *const HeaderList, name: []const u8) bool {
    return self.find(name) != null;
}

/// Joins matching values with ", ", or returns null when the name is absent.
/// Returned slice can be deallocated with this list's allocator.free.
/// If an arena-style allocator is used instead, such as std.heap.ArenaAllocator,
/// then no call to free is necessary.
/// https://fetch.spec.whatwg.org/#concept-header-list-get
pub fn get(self: *const HeaderList, name: []const u8) !?[]u8 {
    const first = self.find(name) orelse return null;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(self.allocator);

    try output.appendSlice(self.allocator, self.entries.items[first].value);
    for (self.entries.items[first + 1 ..]) |entry| {
        if (!std.ascii.eqlIgnoreCase(entry.name, name)) continue;
        try output.appendSlice(self.allocator, ", ");
        try output.appendSlice(self.allocator, entry.value);
    }
    return try output.toOwnedSlice(self.allocator);
}

/// Gets a header, decodes its bytes, and splits its value outside quoted strings.
/// Each string and the returned slice can be deallocated with this list's allocator.free.
/// If an arena-style allocator is used instead, such as std.heap.ArenaAllocator,
/// then no call to free is necessary.
/// https://fetch.spec.whatwg.org/#concept-header-list-get-decode-split
pub fn getDecodeAndSplit(self: *const HeaderList, name: []const u8) !?[][]u8 {
    const value = try self.get(name) orelse return null;
    defer self.allocator.free(value);
    return try header.getDecodeAndSplit(self.allocator, value);
}

/// Appends a header, reusing the first matching name's casing.
/// The value must already be normalized. Invalid names and values return errors.
/// https://fetch.spec.whatwg.org/#concept-header-list-append
pub fn append(self: *HeaderList, name: []const u8, value: []const u8) !void {
    try header.validate(name, value);
    const first = self.find(name);
    const entry_name = if (first) |index| self.entries.items[index].name else name;
    try self.appendHeader(entry_name, value);
}

/// Removes every header with this name, ignoring ASCII case.
/// https://fetch.spec.whatwg.org/#concept-header-list-delete
pub fn delete(self: *HeaderList, name: []const u8) void {
    const first = self.find(name) orelse return;
    // Keep the first name until all comparisons are done; name can refer to it.
    self.removeFollowing(first);
    _ = self.entries.orderedRemove(first);
}

/// Replaces the first matching value and removes later matches, keeping its position.
/// The value must already be normalized. Invalid names and values return errors.
/// https://fetch.spec.whatwg.org/#concept-header-list-set
pub fn set(self: *HeaderList, name: []const u8, value: []const u8) !void {
    try header.validate(name, value);
    const first = self.find(name) orelse return self.appendHeader(name, value);
    self.removeFollowing(first);
    self.entries.items[first].value = value;
}

/// Adds ", " and value to the first match, or appends a new header when absent.
/// Later matches stay in place. The value must already be normalized.
/// https://fetch.spec.whatwg.org/#concept-header-list-combine
pub fn combine(self: *HeaderList, name: []const u8, value: []const u8) !void {
    try header.validate(name, value);
    const first = self.find(name) orelse return self.appendHeader(name, value);
    const entry = &self.entries.items[first];
    const combined = try std.mem.concat(self.allocator, u8, &.{
        entry.value,
        ", ",
        value,
    });
    entry.value = combined;
}

/// Returns a new list sorted by lowercase name, with matching values joined.
/// Set-Cookie values stay separate and keep their order.
/// Lowercase names and joined values can be deallocated with this list's allocator.free.
/// Deallocate each distinct name once. If an arena-style allocator is used instead,
/// such as std.heap.ArenaAllocator, then no call to free is necessary.
/// Set-Cookie values keep their original slices. deinit only frees the entries array.
/// https://fetch.spec.whatwg.org/#concept-header-list-sort-and-combine
pub fn sortAndCombine(self: *const HeaderList) !HeaderList {
    var result = HeaderList.init(self.allocator);
    errdefer result.deinit();
    const names = try self.sortedLowercaseNames();
    defer self.allocator.free(names);
    errdefer {
        for (result.entries.items) |entry| {
            if (!std.mem.eql(u8, entry.name, "set-cookie")) self.allocator.free(entry.value);
        }
        for (names) |name| self.allocator.free(name);
    }
    for (names) |name| {
        if (std.mem.eql(u8, name, "set-cookie")) {
            for (self.entries.items) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.name, name)) try result.appendHeader(name, entry.value);
            }
        } else {
            const value = (try self.get(name)).?;
            errdefer self.allocator.free(value);
            // Joining empty values can produce edge spaces. This algorithm keeps them.
            try result.appendHeader(name, value);
        }
    }
    return result;
}

/// Returns distinct lowercase names in ascending byte order.
/// Each name and the returned slice can be deallocated with this list's allocator.free.
/// If an arena-style allocator is used instead, such as std.heap.ArenaAllocator,
/// then no call to free is necessary.
/// https://fetch.spec.whatwg.org/#convert-header-names-to-a-sorted-lowercase-set
pub fn sortedLowercaseNames(self: *const HeaderList) ![][]u8 {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| self.allocator.free(name);
        names.deinit(self.allocator);
    }
    for (self.entries.items, 0..) |entry, index| {
        if (self.find(entry.name).? != index) continue;
        const name = try std.ascii.allocLowerString(self.allocator, entry.name);
        errdefer self.allocator.free(name);
        try names.append(self.allocator, name);
    }
    std.mem.sort([]u8, names.items, {}, nameLessThan);

    return names.toOwnedSlice(self.allocator);
}

fn find(self: *const HeaderList, name: []const u8) ?usize {
    for (self.entries.items, 0..) |entry, index| {
        if (std.ascii.eqlIgnoreCase(entry.name, name)) return index;
    }
    return null;
}

fn appendHeader(self: *HeaderList, name: []const u8, value: []const u8) !void {
    try self.entries.append(self.allocator, .{
        .name = name,
        .value = value,
    });
}

// Removes later matches while keeping all other headers in order.
fn removeFollowing(self: *HeaderList, first: usize) void {
    const name = self.entries.items[first].name;
    var end = first + 1;
    for (self.entries.items[first + 1 ..]) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, name)) continue;
        self.entries.items[end] = entry;
        end += 1;
    }
    self.entries.shrinkRetainingCapacity(end);
}

fn nameLessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "network header list: append, get, set, combine, and delete" {
    const allocator = std.testing.allocator;
    var list = HeaderList.init(allocator);
    defer list.deinit();

    try list.append("X-Test", "first");
    try list.append("Other", "keep");
    try list.append("x-test", "second");
    try std.testing.expect(list.contains("X-TEST"));
    try std.testing.expectEqualStrings("X-Test", list.entries.items[2].name);
    const value = (try list.get("x-test")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("first, second", value);
    try std.testing.expectEqual(null, try list.get("missing"));

    try list.set("x-test", "replacement");
    try std.testing.expectEqual(@as(usize, 2), list.entries.items.len);
    try std.testing.expectEqualStrings("X-Test", list.entries.items[0].name);
    try std.testing.expectEqualStrings("replacement", list.entries.items[0].value);
    try std.testing.expectEqualStrings("Other", list.entries.items[1].name);

    try list.combine("X-TEST", "last");
    const combined = list.entries.items[0].value;
    defer allocator.free(combined);
    try std.testing.expectEqualStrings("replacement, last", combined);
    try list.append("x-test", "another");
    list.delete("X-TEST");
    try std.testing.expect(!list.contains("x-test"));
    try std.testing.expectEqual(@as(usize, 1), list.entries.items.len);
    try std.testing.expectEqualStrings("Other", list.entries.items[0].name);
}

test "network header list: names are lowercase, distinct, and sorted" {
    const allocator = std.testing.allocator;
    var list = HeaderList.init(allocator);
    defer list.deinit();
    try list.append("Zebra", "last");
    try list.append("Alpha", "first");
    try list.append("ALPHA", "second");
    try list.append("Bravo", "middle");

    const names = try list.sortedLowercaseNames();
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }
    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("alpha", names[0]);
    try std.testing.expectEqualStrings("bravo", names[1]);
    try std.testing.expectEqualStrings("zebra", names[2]);
    try std.testing.expectEqualStrings("Zebra", list.entries.items[0].name);
}

test "network header list: sort and combine keeps set-cookie values separate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var list = HeaderList.init(arena.allocator());
    defer list.deinit();
    try list.append("Z", "last");
    try list.append("Set-Cookie", "z=1");
    try list.append("A", "");
    try list.append("SET-COOKIE", "a=2; Expires=Wed, 09 Jun 2027 10:18:14 GMT");
    try list.append("a", "");
    try list.append("Set-Cookie2", "first");
    try list.append("SET-COOKIE2", "second");

    var sorted = try list.sortAndCombine();
    defer sorted.deinit();
    const expected = [_]Header{
        .{ .name = "a", .value = ", " },
        .{ .name = "set-cookie", .value = "z=1" },
        .{ .name = "set-cookie", .value = "a=2; Expires=Wed, 09 Jun 2027 10:18:14 GMT" },
        .{ .name = "set-cookie2", .value = "first, second" },
        .{ .name = "z", .value = "last" },
    };
    try std.testing.expectEqual(expected.len, sorted.entries.items.len);
    for (expected, sorted.entries.items) |want, actual| {
        try std.testing.expectEqualStrings(want.name, actual.name);
        try std.testing.expectEqualStrings(want.value, actual.value);
    }
    try std.testing.expectEqualStrings("Z", list.entries.items[0].name);
    try std.testing.expectEqual(@as(usize, 7), list.entries.items.len);
}
