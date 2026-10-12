const Fragment = @This();

const std = @import("std");
const Tree = @import("../../utils/tree.zig").Tree;
const BoxFragment = @import("BoxFragment.zig");
const BaseFragment = @import("BaseFragment.zig");
const TextFragment = @import("TextFragment.zig");

pub const Content = union(enum) {
    box: BoxFragment,
    text: TextFragment,
};

content: Content,
tree: Tree(Fragment) = .{},

pub fn init(content: Content) Fragment {
    return .{ .content = content };
}

pub fn base(self: *const Fragment) *const BaseFragment {
    return switch (self.content) {
        inline else => |*content| &content.base,
    };
}

pub fn destroy(self: *Fragment, allocator: std.mem.Allocator) void {
    self.remove();
    var current = self;
    while (true) {
        if (current.first_child()) |child| {
            current = child;
            continue;
        }
        const parent_node = current.parent();
        current.remove();
        switch (current.content) {
            .text => |text| text.deinit(allocator),
            else => {},
        }
        allocator.destroy(current);
        current = parent_node orelse return;
    }
}

// ----- Tree implementation -----
pub fn appendChild(self: *Fragment, child: *Fragment) void {
    self.tree.appendChild(child);
}

pub fn remove(self: *Fragment) void {
    self.tree.remove();
}

pub inline fn parent(self: *const Fragment) ?*Fragment {
    return self.tree.parent;
}

pub inline fn first_child(self: *const Fragment) ?*Fragment {
    return self.tree.first_child;
}

pub inline fn last_child(self: *const Fragment) ?*Fragment {
    return self.tree.last_child;
}

pub inline fn next_sibling(self: *const Fragment) ?*Fragment {
    return self.tree.next_sibling;
}

pub inline fn prev_sibling(self: *const Fragment) ?*Fragment {
    return self.tree.prev_sibling;
}
