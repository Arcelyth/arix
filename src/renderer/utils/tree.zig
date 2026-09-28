const std = @import("std");
const assert = @import("check.zig").assert;

pub fn Tree(comptime Node: type) type {
    return struct {
        const Self = @This();

        parent: ?*Node = null,
        first_child: ?*Node = null,
        last_child: ?*Node = null,
        next_sibling: ?*Node = null,
        prev_sibling: ?*Node = null,

        /// The child must not already have a parent.
        pub fn appendChild(self: *Self, child: *Node) void {
            const parent: *Node = @fieldParentPtr("tree", self);
            assert(child != parent);

            child.tree.parent = parent;
            child.tree.prev_sibling = self.last_child;
            if (self.last_child) |last|
                last.tree.next_sibling = child
            else
                self.first_child = child;
            self.last_child = child;
        }

        /// Insert `child` immediately before `reference`.
        /// `reference` must be a child of this node.
        pub fn insertBefore(
            self: *Self,
            child: *Node,
            reference: *Node,
        ) void {
            const parent: *Node = @fieldParentPtr("tree", self);
            assert(reference.tree.parent == parent);
            assert(child != parent and child != reference);

            child.tree.parent = parent;
            child.tree.next_sibling = reference;
            child.tree.prev_sibling = reference.tree.prev_sibling;
            if (reference.tree.prev_sibling) |previous|
                previous.tree.next_sibling = child
            else
                self.first_child = child;
            reference.tree.prev_sibling = child;
        }

        /// Remove `child` from this node.
        pub fn removeChild(self: *Self, child: *Node) void {
            const parent: *Node = @fieldParentPtr("tree", self);
            assert(child.tree.parent == parent);

            if (child.tree.prev_sibling) |previous|
                previous.tree.next_sibling = child.tree.next_sibling
            else
                self.first_child = child.tree.next_sibling;
            if (child.tree.next_sibling) |next|
                next.tree.prev_sibling = child.tree.prev_sibling
            else
                self.last_child = child.tree.prev_sibling;

            child.tree.parent = null;
            child.tree.prev_sibling = null;
            child.tree.next_sibling = null;
        }

        /// Remove this node from its parent.
        pub fn remove(self: *Self) void {
            const parent = self.parent orelse return;
            const node: *Node = @fieldParentPtr("tree", self);
            parent.tree.removeChild(node);
        }
    };
}

test "utils tree: insertion, removal, and moving a subtree" {
    const testing = std.testing;
    const Node = struct { tree: Tree(@This()) = .{} };
    var root: Node = .{};
    var other: Node = .{};
    var a: Node = .{};
    var b: Node = .{};
    var c: Node = .{};
    var d: Node = .{};
    root.tree.appendChild(&a);
    root.tree.appendChild(&c);
    root.tree.insertBefore(&b, &c);
    root.tree.insertBefore(&d, &a);
    try testing.expect(root.tree.first_child == &d and root.tree.last_child == &c);
    try testing.expect(d.tree.next_sibling == &a and a.tree.prev_sibling == &d);
    try testing.expect(a.tree.next_sibling == &b and b.tree.prev_sibling == &a);
    try testing.expect(b.tree.next_sibling == &c and c.tree.prev_sibling == &b);
    try testing.expect(b.tree.parent == &root);

    root.tree.removeChild(&b); // middle
    try testing.expect(a.tree.next_sibling == &c and c.tree.prev_sibling == &a);
    try testing.expect(b.tree.parent == null and b.tree.next_sibling == null and b.tree.prev_sibling == null);
    d.tree.remove(); // first
    c.tree.remove(); // last
    try testing.expect(root.tree.first_child == &a and root.tree.last_child == &a);
    try testing.expect(a.tree.prev_sibling == null and a.tree.next_sibling == null);
    a.tree.appendChild(&b);
    a.tree.remove(); // only child; retain its descendants
    a.tree.remove(); // already detached
    try testing.expect(root.tree.first_child == null and root.tree.last_child == null);
    other.tree.appendChild(&a);
    try testing.expect(a.tree.parent == &other and a.tree.first_child == &b and b.tree.parent == &a);
}
