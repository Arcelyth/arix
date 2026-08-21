const OpenElementStack = @This();

const std = @import("std");
const Element = @import("../../dom/Element.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

allocator: std.mem.Allocator,
els: std.ArrayList(*Element),

pub fn init(alloc: std.mem.Allocator) OpenElementStack {
    return .{
        .allocator = alloc,
        .els = .empty,
    };
}

pub fn deinit(self: *OpenElementStack) void {
    self.els.deinit(self.allocator);
}

pub inline fn len(self: *const OpenElementStack) usize {
    return self.els.items.len;
}

pub inline fn append(self: *OpenElementStack, el: *Element) !void {
    try self.els.append(self.allocator, el);
}

pub inline fn at(self: *OpenElementStack, idx: usize) *Element {
    return self.els.items[idx];
}

pub inline fn currentNode(self: *OpenElementStack) *Element {
    if (self.els.items.len == 0) @panic("Empty open elements stack.");
    return self.els.items[self.els.items.len - 1];
}

// https://html.spec.whatwg.org/multipage/parsing.html#generate-implied-end-tags
pub fn generateImpliedEndTags(self: *OpenElementStack, exclude: ?LocalTag) void {
    while (self.els.items.len > 0) {
        const cur = self.currentNode();

        if (exclude) |ex| {
            if (cur.local_name.is(ex)) break;
        }

        if (cur.in(&.{ .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc })) {
            _ = self.els.pop();
        } else {
            break;
        }
    }
}

// https://html.spec.whatwg.org/multipage/parsing.html#generate-all-implied-end-tags-thoroughly
pub fn generateAllImpliedEndTagsThoroughly(self: *OpenElementStack) void {
    while (self.els.items.len > 0) {
        const cur = self.currentNode();

        if (cur.in(&.{ .caption, .colgroup, .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr })) {
            _ = self.els.pop();
        } else {
            break;
        }
    }
}

pub fn lastStackElement(self: *OpenElementStack, elem: LocalTag) ?Element {
    for (self.els.items..0) |idx| {
        if (self.els.items[idx].local_name.is(elem)) {
            return self.els.items[idx];
        }
    }
    return null;
}

pub inline fn htmlElement(self: *OpenElementStack) ?*Element {
    if (self.els.items.len == 0) return null;
    return self.els.items[0];
}

pub inline fn popUntilPopped(self: *OpenElementStack, tag: LocalTag) void {
    while (self.len() > 0) {
        const el = self.els.pop();
        if (el) |e| if (e.local_name.is(tag)) break;
    }
}

pub inline fn popUntil(self: *OpenElementStack, tag: LocalTag) void {
    while (self.len() > 0) {
        const node = self.currentNode();
        if (node.local_name.is(tag)) break;
        _ = self.els.pop();
    }
}

pub inline fn popUntilOneOfPopped(self: *OpenElementStack, tags: []const LocalTag) void {
    while (self.len() > 0) {
        const node = self.currentNode();
        if (node.local_name.oneOf(tags)) break;
        _ = self.els.pop();
    }
}

pub inline fn clearStackBack(self: *OpenElementStack, tags: []const LocalTag) void {
    while (self.len() > 0) {
        const node = self.currentNode();
        if (node.ns == .NS_Html and node.local_name.oneOf(tags)) {
            break;
        }
        _ = self.els.pop();
    }
}

pub inline fn hasElement(self: *const OpenElementStack, name: LocalTag) bool {
    for (self.els.items) |el| {
        if (el.local_name.is(name)) return true;
    }
    return false;
}

pub inline fn allElementsOneOf(self: *const OpenElementStack, tags: []const LocalTag) bool {
    for (self.els.items) |el| {
        for (tags) |tag| {
            if (!el.local_name.is(tag)) return false;
        }
    }
    return true;
}

/// https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-table-scope
pub fn hasElementInTableScope(self: *const OpenElementStack, target_tag: LocalTag) bool {
    var i: usize = self.els.len();
    while (i > 0) {
        i -= 1;
        const node = self.els.items[i];

        if (node.ns == .NS_Html and node.local_name.is(target_tag)) return true;

        if (node.ns == .NS_Html and node.local_name.oneOf(&.{ .html, .table, .template })) return false;
    }
    return false;
}

pub fn hasElementInScopeCustom(
    self: *const OpenElementStack,
    target_tag: LocalTag,
    comptime extra_html_tags: []const LocalTag,
) bool {
    var i: usize = self.els.len();
    while (i > 0) {
        i -= 1;
        const node = self.els.items[i];
        if (node.ns == .NS_Html and node.local_name.is(target_tag)) return true;

        if (node.ns == .NS_Html and (node.local_name.oneOf(&.{
            .applet,  .caption, .html,   .table,    .td, .th,
            .marquee, .object,  .select, .template,
        }) or node.local_name.oneOf(extra_html_tags))) return false;

        if (node.ns == .NS_MathML and node.local_name.oneOf(&.{
            .mi, .mo, .mn, .ms, .mtext, .@"annotation-xml",
        })) return false;

        if (node.ns == .NS_SVG and node.local_name.oneOf(&.{
            .foreignObject, .desc, .title,
        })) return false;
    }
    return false;
}
