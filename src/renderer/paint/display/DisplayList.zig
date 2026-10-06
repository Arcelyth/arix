const DisplayList = @This();

const std = @import("std");
const display_item = @import("display_item.zig");
const DisplayItem = display_item.DisplayItem;
const EdgeSizes = @import("../../geometry/EdgeSizes.zig");
const LineStyle = @import("../../css/values/computed/line_style.zig").LineStyle;
const fragment = @import("../../layout/fragment.zig");
const Fragment = fragment.Fragment;
const FragmentTree = fragment.FragmentTree;
const Rect = @import("../../geometry/Rect.zig");
const Element = @import("../../dom/Element.zig");
const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");
const BoxFragment = fragment.BoxFragment;
const BorderProperties = display_item.BorderProperties;
const CommonItemProperties = display_item.CommonItemProperties;

// Locates the fragment’s content-box origin on the canvas.
const Offset = struct { x: f64, y: f64 };

items: std.ArrayList(DisplayItem) = .empty,

pub fn deinit(self: *DisplayList, allocator: std.mem.Allocator) void {
    self.items.deinit(allocator);
    self.* = .{};
}

pub fn build(allocator: std.mem.Allocator, tree: *const FragmentTree) !DisplayList {
    var result: DisplayList = .{};
    errdefer result.deinit(allocator);
    const root = tree.root orelse return result;

    // The root’s background covers the entire canvas and
    // the root element does not paint this background again.
    const canvas_source = canvasBackground(root);
    try result.renderCanvasBackground(allocator, tree.initial_containing_block, canvas_source);

    try result.renderFragments(allocator, root, .{
        .x = tree.initial_containing_block.x,
        .y = tree.initial_containing_block.y,
    }, canvas_source);
    return result;
}

fn renderCanvasBackground(
    self: *DisplayList,
    allocator: std.mem.Allocator,
    viewport: Rect,
    source: ?*const Fragment,
) !void {
    // Paint the propagated background once, then skip it on its originating box.
    const node = source orelse return;
    try self.renderBackground(allocator, viewport, &node.content.box.style);
}

fn renderFragments(
    self: *DisplayList,
    allocator: std.mem.Allocator,
    root: *const Fragment,
    origin: Offset,
    canvas_source: ?*const Fragment,
) !void {
    const Pending = struct { node: *const Fragment, offset: Offset };
    var pending: std.ArrayList(Pending) = .empty;
    defer pending.deinit(allocator);

    try pending.append(allocator, .{ .node = root, .offset = origin });
    while (pending.pop()) |entry| {
        const content = entry.node.content.box.base.rect;
        const offset: Offset = .{
            .x = entry.offset.x + content.x,
            .y = entry.offset.y + content.y,
        };
        try self.renderFragment(allocator, entry.node, offset, entry.node != canvas_source);

        // Normal-flow block backgrounds paint parent before children, with
        // later siblings on top. Child rectangles are parent-content-relative.
        var child = entry.node.last_child();
        while (child) |node| : (child = node.prev_sibling())
            try pending.append(allocator, .{ .node = node, .offset = offset });
    }
}

fn renderFragment(
    self: *DisplayList,
    allocator: std.mem.Allocator,
    node: *const Fragment,
    offset: Offset,
    paint_background: bool,
) !void {
    switch (node.content) {
        .box => |*box| {
            const content = box.base.rect;
            const rect: Rect = .{
                .x = offset.x - box.padding.left - box.border.left,
                .y = offset.y - box.padding.top - box.border.top,
                .width = content.width + box.padding.left + box.padding.right + box.border.left + box.border.right,
                .height = content.height + box.padding.top + box.padding.bottom + box.border.top + box.border.bottom,
            };
            if (paint_background) try self.renderBackground(allocator, rect, &box.style);
            try self.renderBorder(allocator, rect, box);
        },
    }
}

fn renderBorder(self: *DisplayList, allocator: std.mem.Allocator, rect: Rect, box: *const BoxFragment) !void {
    if (rect.width <= 0 or rect.height <= 0) return;
    var border: BorderProperties = .{};

    inline for (.{ "top", "right", "bottom", "left" }) |side| {
        const dest = &@field(border, side);
        dest.style = @field(box.style.values, "border_" ++ side ++ "_style");
        if (@field(box.border, side) > 0) {
            dest.color = try @field(box.style.values, "border_" ++ side ++ "_color").toRgba(box.style.values.color);
        }
    }
    try self.pushBorder(
        allocator,
        .{ .clip_rect = rect },
        rect,
        box.border,
        border,
    );
}

fn renderBackground(
    self: *DisplayList,
    allocator: std.mem.Allocator,
    rect: Rect,
    style: *const ComputedStyle,
) !void {
    const color = try style.values.background_color.toRgba(style.values.color);
    try self.pushRect(allocator, .{ .clip_rect = rect }, rect, color);
}

pub fn pushRect(
    self: *DisplayList,
    allocator: std.mem.Allocator,
    common: CommonItemProperties,
    bounds: Rect,
    rgba: [4]f64,
) !void {
    if (rgba[3] <= 0 or bounds.intersection(common.clip_rect) == null) return;
    try self.items.append(allocator, .{
        .rect = .{ .common = common, .bounds = bounds, .color = rgba },
    });
}

pub fn pushBorder(
    self: *DisplayList,
    allocator: std.mem.Allocator,
    common: CommonItemProperties,
    bounds: Rect,
    widths: EdgeSizes,
    details: BorderProperties,
) !void {
    if (bounds.intersection(common.clip_rect) == null) return;
    var visible = false;
    inline for (.{ "top", "right", "bottom", "left" }) |side| {
        visible = visible or (@field(widths, side) > 0 and @field(details, side).isVisible());
    }

    if (!visible) return;
    try self.items.append(allocator, .{ .border = .{
        .common = common,
        .bounds = bounds,
        .widths = widths,
        .details = details,
    } });
}

/// Find the fragment whose background should be propagated to the canvas.
fn canvasBackground(root: *const Fragment) ?*const Fragment {
    const element = switch (root.content.box.source) {
        .principal => |element| element,
        else => return null,
    };
    const parent = element.node.parent() orelse return null;
    if (parent.type_id != .DOM_Document) return null;

    const background = root.content.box.style.values.background_color;
    const transparent = background == .absolute and (background.absolute.alpha orelse 0) == 0;

    // Use the root's background unless it is a transparent HTML <html> element.
    if (!transparent or element.ns != .NS_Html or !element.local_name.is(.html))
        return root;

    // Only the first HTML body child is eligible, even if it has no fragment.
    var child = element.node.first_child();
    while (child) |node| : (child = node.next_sibling()) {
        if (node.type_id != .DOM_Element) continue;
        const body = node.downcast(Element);
        if (body.ns != .NS_Html or !body.local_name.is(.body)) continue;

        var candidate = root.first_child();
        while (candidate) |item| : (candidate = item.next_sibling()) {
            if (item.content.box.source == .principal and
                item.content.box.source.principal == body)
                return item;
        }
        break;
    }
    return root;
}
