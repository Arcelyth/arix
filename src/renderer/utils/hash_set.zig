const std = @import("std");

pub fn HashSet(comptime T: type) type {
    return struct {
        const Self = @This();

        map: std.AutoHashMap(T, void),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = std.AutoHashMap(T, void).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        /// Remove all elements while retaining the allocated capacity.
        pub fn clear(self: *Self) void {
            self.map.clearRetainingCapacity();
        }

        /// Remove all elements and frees all allocated memory.
        pub fn clearAndFree(self: *Self) void {
            self.map.clearAndFree();
        }

        /// Return the number of elements.
        pub fn len(self: *const Self) usize {
            return self.map.count();
        }

        /// Return whether the set is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.map.count() == 0;
        }

        /// Return true if the element already existed.
        pub fn contains(self: *const Self, key: T) bool {
            return self.map.contains(key);
        }

        /// Insert an element.
        /// Return true if a new element was inserted.
        pub fn insert(self: *Self, key: T) !bool {
            const gop = try self.map.getOrPut(key);
            if (!gop.found_existing) {
                gop.value_ptr.* = {};
            }
            return !gop.found_existing;
        }

        /// Remove an element.
        /// Return true if the element existed.
        pub fn remove(self: *Self, key: T) bool {
            return self.map.remove(key);
        }

        /// Ensure the set can hold at least `capacity` elements without reallocating.
        pub fn ensureCapacity(self: *Self, capacity: usize) !void {
            try self.map.ensureTotalCapacity(capacity);
        }

        pub const Iterator = struct {
            iter: std.AutoHashMap(T, void).KeyIterator,

            pub fn next(self: *Iterator) ?*const T {
                return self.iter.next();
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return .{
                .iter = self.map.keyIterator(),
            };
        }
    };
}

const testing = std.testing;

test "hash set" {
    const allocator = testing.allocator;

    var set = HashSet(i32).init(allocator);
    defer set.deinit();

    _ = try set.insert(10);
    _ = try set.insert(20);
    _ = try set.insert(30);

    try testing.expect(set.contains(20));
}
