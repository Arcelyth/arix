const BoxTree = @This();

const std = @import("std");
const BlockFormattingContext = @import("flow.zig").BlockFormattingContext;
const LayoutBox = @import("LayoutBox.zig");
const LayoutBoxBase = @import("LayoutBoxBase.zig");
const flow = @import("flow.zig");
const StyledNode = @import("../style/StyledNode.zig");
const ComputedStyle = @import("../style/computed/ComputedStyle.zig");
const Element = @import("../dom/Element.zig");
const Text = @import("../dom/Text.zig");
const LocalTag = @import("local_name").LocalTag;

/// The initial containing block's BFC. Contains the document element's
/// principal box, or no box when the document element has display:none.
root: BlockFormattingContext = .{},

/// Build the formatting structure for the document element.
pub fn build(allocator: std.mem.Allocator, root: *const StyledNode) !BoxTree {
    if (root.node.type_id != .DOM_Element or root.node.parent() == null or
        root.node.parent().?.type_id != .DOM_Document)
        @panic("BoxTree.build requires the styled document element");
    if (root.style.values.display == .none) return .{};
    return .{
        .root = .{
            .contents = .{
                .block_level_boxes = try principal(allocator, root, true),
            },
        },
    };
}

pub fn create(allocator: std.mem.Allocator, content: LayoutBox.Content) !*LayoutBox {
    const box = try allocator.create(LayoutBox);
    box.* = LayoutBox.init(content);
    return box;
}

/// A principal box receives the generating element's computed style.
fn principal(allocator: std.mem.Allocator, node: *const StyledNode, is_root: bool) !*LayoutBox {
    const element = checkElement(node);
    const base: LayoutBoxBase = .{
        .source = .{ .principal = element },
        .style = node.style,
    };
    const content: LayoutBox.Content = switch (node.style.values.display) {
        .box => |display| content: {
            if (display.list_item) @panic("TODO: ::marker style and box construction");
            if (display.outside == .run_in) @panic("TODO: run-in box construction");
            switch (display.inside) {
                .flow, .flow_root => {},
                .table, .flex, .grid, .ruby => @panic("TODO: table, flex, grid and ruby box construction"),
            }
            if (is_root and display.outside != .block)
                @panic("document-root computed display must be blockified during styling");
            break :content switch (display.outside) {
                .block => if (is_root or display.inside == .flow_root)
                    .{ .block_level = .{ .independent = .{ .base = base } } }
                else
                    .{ .block_level = .{ .same_formatting_context = .{ .base = base } } },
                .@"inline" => if (display.inside == .flow_root)
                    .{ .inline_level = .{ .atomic = .{ .base = base } } }
                else
                    .{ .inline_level = .{ .inline_box = .{ .base = base } } },
                .run_in => unreachable,
            };
        },
        .internal => @panic("TODO: table and ruby internal box construction"),
        .contents => @panic("document-root display:contents must compute to block during styling"),
        .none => unreachable,
    };
    const box = try create(allocator, content);
    errdefer box.destroy(allocator);

    try appendChildren(allocator, box, node);
    try finishContainer(allocator, box);
    return box;
}

// These elements suppress their contents when display:contents is used.
// https://www.w3.org/TR/css-display-3/#unbox-html
const unusual_elements: []const LocalTag = &.{
    .br,     .wbr, .meter, .progress, .canvas,   .embed, .object,   .audio,
    .iframe, .img, .video, .frame,    .frameset, .input, .textarea, .select,
};

/// Special element formatting is not replaced with ordinary flow containers.
fn checkElement(node: *const StyledNode) *const Element {
    if (node.node.type_id != .DOM_Element) @panic("box-tree root must be an element");

    const element = node.node.downcast(Element);
    if (element.ns != .NS_Html) @panic("TODO: SVG and MathML box construction");

    if (element.local_name.oneOf(unusual_elements) or
        element.local_name.oneOf(&.{ .button, .details, .fieldset, .legend }))
        @panic("TODO: replaced content and special HTML element box construction");

    return element;
}

fn appendChildren(allocator: std.mem.Allocator, parent: *LayoutBox, node: *const StyledNode) std.mem.Allocator.Error!void {
    var child = node.first_child();
    while (child) |current| {
        switch (current.node.type_id) {
            .DOM_Text => {
                var last = current;
                var has_text = !current.node.downcast(Text).data.isEmpty();
                while (last.next_sibling()) |next| {
                    if (next.node.type_id != .DOM_Text) break;
                    has_text = has_text or !next.node.downcast(Text).data.isEmpty();
                    last = next;
                }
                if (has_text) parent.appendChild(try create(allocator, .{ .text = .{
                    .first = current,
                    .last = last,
                } }));
                child = last.next_sibling();
                continue;
            },
            .DOM_Element => switch (current.style.values.display) {
                .none => {},
                .contents => {
                    const element = current.node.downcast(Element);
                    if (element.ns != .NS_Html) @panic("TODO: SVG and MathML display:contents");

                    if (!element.local_name.oneOf(unusual_elements))
                        try appendChildren(allocator, parent, current);
                },
                else => parent.appendChild(try principal(allocator, current, false)),
            },
            else => {}, // Comments and other non-rendered DOM nodes are ignored.
        }
        child = current.next_sibling();
    }
}

/// Finish the parent’s formatting structure after its children have been built.
fn finishContainer(allocator: std.mem.Allocator, parent: *LayoutBox) !void {
    _ = allocator;
    _ = parent;
}
