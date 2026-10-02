const BoxTree = @This();

const std = @import("std");
const BlockFormattingContext = @import("flow.zig").BlockFormattingContext;
const LayoutBox = @import("LayoutBox.zig");
const LayoutBoxBase = @import("LayoutBoxBase.zig");
const flow = @import("flow.zig");
const inline_ = @import("inline.zig");
const InlineFormattingContext = inline_.InlineFormattingContext;
const StyledNode = @import("../style/StyledNode.zig");
const ComputedStyle = @import("../style/computed/ComputedStyle.zig");
const Element = @import("../dom/Element.zig");
const Text = @import("../dom/Text.zig");
const LocalTag = @import("local_name").LocalTag;
const FragmentTree = @import("fragment.zig").FragmentTree;

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

pub fn layout(self: *const BoxTree, allocator: std.mem.Allocator, viewport_width: f64, viewport_height: f64) !FragmentTree {
    return flow.layout(allocator, &self.root, viewport_width, viewport_height);
}

pub fn destroy(self: *BoxTree, allocator: std.mem.Allocator) void {
    switch (self.root.contents) {
        .block_level_boxes => |first| {
            var child = first;
            while (child) |box| {
                child = box.next_sibling();
                box.destroy(allocator);
            }
        },
        .inline_formatting_context => @panic("BoxTree root must contain block-level boxes"),
    }
    self.root.deinit(allocator);
    self.root = .{};
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
    var has_block = false;
    var child = parent.first_child();
    while (child) |box| : (child = box.next_sibling())
        has_block = has_block or box.isBlockLevel();

    const container = parent.container() orelse {
        if (has_block) @panic("TODO: block-in-inline splitting");
        return;
    };
    if (!has_block) {
        if (parent.first_child()) |first| container.* = .{
            .inline_formatting_context = InlineFormattingContext.init(
                &parent.base().?.style,
                first,
            ),
        };
        return;
    }
    child = parent.first_child();
    while (child) |first| {
        if (first.isBlockLevel()) {
            child = first.next_sibling();
            continue;
        }
        var end = first.next_sibling();
        while (end) |box| {
            if (box.isBlockLevel()) break;
            end = box.next_sibling();
        }
        if (isWhitespaceRun(first, end)) {
            // FIXME: Only white-space:normal is available in the current property registry.
            // Need to implement whitespace value.
            while (child != end) {
                const current = child.?;
                child = current.next_sibling();
                current.destroy(allocator);
            }
        } else {
            try wrapInlineRun(allocator, parent, first, end);
        }
        child = end;
    }
    container.* = .{ .block_level_boxes = parent.first_child() };
}

fn isWhitespaceRun(first: *LayoutBox, end: ?*LayoutBox) bool {
    var child: ?*LayoutBox = first;
    while (child != end) {
        const current = child.?;
        switch (current.content) {
            .block_level, .inline_level => return false,
            .text => |text| if (!text.isWhitespace()) return false,
        }
        child = current.next_sibling();
    }
    return true;
}

fn wrapInlineRun(allocator: std.mem.Allocator, parent: *LayoutBox, first: *LayoutBox, end: ?*LayoutBox) std.mem.Allocator.Error!void {
    const base = LayoutBoxBase.anonymous(&parent.base().?.style, .{ .outside = .block });
    const wrapper = try create(allocator, .{
        .block_level = .{
            .same_formatting_context = .{
                .base = base,
                .contents = .{ .inline_formatting_context = InlineFormattingContext.init(&base.style, first) },
            },
        },
    });

    parent.insertBefore(wrapper, first);
    var child: ?*LayoutBox = first;
    while (child != end) {
        const current = child.?;
        child = current.next_sibling();
        current.remove();
        wrapper.appendChild(current);
    }
}

test "layout BoxTree: document element and display:none" {
    const testing = std.testing;
    const Document = @import("../dom/Document.zig");
    const LocalName = @import("local_name").LocalName;
    const allocator = testing.allocator;

    const document = Document.init(allocator);
    defer document.destroy(allocator);
    const element = try allocator.create(Element);
    element.* = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), document);
    document.asNode().appendChild(element.asNode());

    // display: block;
    var styled = StyledNode.init(element.asNode(), .{
        .values = .{
            .display = .{
                .box = .{ .outside = .block },
            },
        },
    });
    const tree = try BoxTree.build(allocator, &styled);
    try testing.expect(tree.root.contents == .block_level_boxes);
    const box = tree.root.contents.block_level_boxes.?;
    defer box.destroy(allocator);

    try testing.expect(box.content.block_level == .independent);
    try testing.expect(box.base().?.source.principal == element);
    try testing.expectEqualDeep(styled.style, box.base().?.style);
    try testing.expect(box.parent() == null and box.first_child() == null);

    // display: none;
    styled.style.values.display = .none;
    const hidden = try BoxTree.build(allocator, &styled);
    try testing.expect(hidden.root.contents == .block_level_boxes);
    try testing.expect(hidden.root.contents.block_level_boxes == null);
}

test "layout BoxTree: layout a padded root and a centered block" {
    const testing = std.testing;
    const Rect = @import("../geometry/Rect.zig");
    const allocator = testing.allocator;
    const root_style: ComputedStyle = .{ .values = .{
        .display = .{ .box = .{ .outside = .block } },
        .padding_top = .{ .length = 10 },
        .padding_right = .{ .length = 10 },
        .padding_bottom = .{ .length = 10 },
        .padding_left = .{ .length = 10 },
    } };
    const root = try create(allocator, .{
        .block_level = .{
            .independent = .{
                .base = .{
                    .source = .anonymous,
                    .style = root_style,
                },
            },
        },
    });
    var tree: BoxTree = .{
        .root = .{
            .contents = .{ .block_level_boxes = root },
        },
    };
    defer tree.destroy(allocator);

    const child_style: ComputedStyle = .{ .values = .{
        .display = .{ .box = .{ .outside = .block } },
        .width = .{ .length_percentage = .{ .percentage = 50 } },
        .height = .{ .length_percentage = .{ .length = 50 } },
        .margin_left = .auto,
        .margin_right = .auto,
        .margin_top = .{ .length_percentage = .{ .length = 5 } },
        .margin_bottom = .{ .length_percentage = .{ .length = 5 } },
    } };
    const child = try create(allocator, .{
        .block_level = .{
            .same_formatting_context = .{
                .base = .{
                    .source = .anonymous,
                    .style = child_style,
                },
            },
        },
    });
    root.appendChild(child);
    root.container().?.* = .{ .block_level_boxes = child };

    var fragments = try tree.layout(allocator, 200, 100);
    defer fragments.destroy(allocator);

    const root_fragment = fragments.root.?;
    const child_fragment = root_fragment.first_child().?;

    try testing.expectEqualDeep(Rect{
        .x = 0,
        .y = 0,
        .width = 200,
        .height = 100,
    }, fragments.initial_containing_block);

    // width: 200 - 10 - 10 = 180px.
    // height: See its child's content and margin: 50 + 5 + 5 = 60.
    try testing.expectEqualDeep(Rect{
        .x = 10,
        .y = 10,
        .width = 180,
        .height = 60,
    }, root_fragment.content.box.base.rect);

    // witdth: 50% of 180px is 90px.
    // height: because of auto so it is 50px.
    try testing.expectEqualDeep(Rect{
        .x = 45,
        .y = 5,
        .width = 90,
        .height = 50,
    }, child_fragment.content.box.base.rect);
    try testing.expect(child_fragment.parent() == root_fragment and child_fragment.next_sibling() == null);
    try testing.expectEqualDeep(child_style, child.base().?.style);
}
