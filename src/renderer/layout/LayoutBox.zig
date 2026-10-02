const LayoutBox = @This();

const std = @import("std");
const Tree = @import("../utils/tree.zig").Tree;
const LayoutBoxBase = @import("LayoutBoxBase.zig");
const flow = @import("flow.zig");
const BlockLevelBox = flow.BlockLevelBox;
const inline_ = @import("inline.zig");
const InlineLevelBox = inline_.InlineLevelBox;
const TextSequence = @import("TextSequence.zig");

/// An intrusive entry in the formatting structure. Specialized box payloads
/// own their base data and contexts. Text sequences are content, not CSS boxes.
pub const Content = union(enum) {
    block_level: BlockLevelBox,
    inline_level: InlineLevelBox,
    text: TextSequence,
};

content: Content,
tree: Tree(LayoutBox) = .{},

pub fn init(content: Content) LayoutBox {
    return .{ .content = content };
}

/// Text has no box base or computed display type.
pub fn base(self: *const LayoutBox) ?*const LayoutBoxBase {
    return switch (self.content) {
        .block_level => |*box| box.base(),
        .inline_level => |*box| box.base(),
        .text => null,
    };
}

/// Destroy owned tree entries and fragments without touching borrowed DOM or
/// styled nodes. Computed box styles are plain values and need no teardown.
pub fn destroy(self: *LayoutBox, allocator: std.mem.Allocator) void {
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
            .block_level => |*box| box.deinit(allocator),
            .inline_level => |*box| box.deinit(allocator),
            .text => {},
        }
        allocator.destroy(current);
        current = parent_node orelse return;
    }
}

// ----- Tree implementation -----
pub fn appendChild(self: *LayoutBox, child: *LayoutBox) void {
    self.tree.appendChild(child);
}

pub fn insertBefore(self: *LayoutBox, child: *LayoutBox, reference: *LayoutBox) void {
    self.tree.insertBefore(child, reference);
}

pub fn removeChild(self: *LayoutBox, child: *LayoutBox) void {
    self.tree.removeChild(child);
}

pub fn remove(self: *LayoutBox) void {
    self.tree.remove();
}

pub inline fn parent(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.parent;
}

pub inline fn first_child(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.first_child;
}

pub inline fn last_child(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.last_child;
}

pub inline fn next_sibling(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.next_sibling;
}

pub inline fn prev_sibling(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.prev_sibling;
}
