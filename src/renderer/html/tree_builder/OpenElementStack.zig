const OpenElementStack = @This();

const std = @import("std");
const Element = @import("../../dom/Element.zig");
const Namespace = @import("../../dom/namespace.zig").Namespace;
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

pub inline fn pop(self: *OpenElementStack) ?*Element {
    return self.els.pop();
}

pub inline fn at(self: *OpenElementStack, idx: usize) *Element {
    return self.els.items[idx];
}

pub inline fn index(self: *const OpenElementStack, element: *Element) ?usize {
    return std.mem.indexOfScalar(*Element, self.els.items, element);
}

pub inline fn currentNode(self: *OpenElementStack) *Element {
    if (self.els.items.len == 0) @panic("Empty open elements stack.");
    return self.els.items[self.els.items.len - 1];
}

pub inline fn remove(self: *OpenElementStack, el: *Element) ?*Element {
    if (std.mem.indexOfScalar(*Element, self.els.items, el)) |idx|
        return self.els.orderedRemove(idx);
    return null;
}

// https://html.spec.whatwg.org/multipage/parsing.html#generate-implied-end-tags
pub fn generateImpliedEndTags(self: *OpenElementStack, exclude: ?LocalTag) void {
    while (self.els.items.len > 0) {
        const cur = self.currentNode();

        if (exclude) |ex|
            if (cur.local_name.is(ex)) break;

        if (cur.in(&.{ .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc }))
            _ = self.els.pop()
        else
            break;
    }
}

// https://html.spec.whatwg.org/multipage/parsing.html#generate-all-implied-end-tags-thoroughly
pub fn generateAllImpliedEndTagsThoroughly(self: *OpenElementStack) void {
    while (self.els.items.len > 0) {
        const cur = self.currentNode();

        if (cur.in(&.{ .caption, .colgroup, .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr }))
            _ = self.els.pop()
        else
            break;
    }
}

pub fn lastStackElement(self: *OpenElementStack, elem: LocalTag) ?*Element {
    var i = self.els.items.len - 1;
    while (i > 0) : (i -= 1)
        if (self.els.items[i].local_name.is(elem)) return self.els.items[i];

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
        if (node.ns == .NS_Html and node.local_name.oneOf(tags))
            break;

        _ = self.els.pop();
    }
}

pub inline fn hasElement(self: *const OpenElementStack, name: LocalTag) bool {
    for (self.els.items) |el|
        if (el.local_name.is(name)) return true;

    return false;
}

pub inline fn allElementsOneOf(self: *const OpenElementStack, tags: []const LocalTag) bool {
    for (self.els.items) |el| {
        var found = false;
        for (tags) |tag| {
            if (el.local_name.is(tag)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    return true;
}

/// https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-table-scope
pub fn hasElementInTableScope(self: *const OpenElementStack, target_tag: LocalTag) bool {
    var i: usize = self.len();
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
    var i: usize = self.len();
    while (i > 0) {
        i -= 1;
        const node = self.els.items[i];
        if (node.ns == .NS_Html and node.local_name.is(target_tag)) return true;

        if (node.ns == .NS_Html and (node.local_name.oneOf(&.{
            .applet,  .caption, .html,   .table,    .td, .th,
            .marquee, .object,  .select, .template,
        }) or node.local_name.oneOf(extra_html_tags))) return false;

        if (node.ns == .NS_Math and node.local_name.oneOf(&.{
            .mi, .mo, .mn, .ms, .mtext, .@"annotation-xml",
        })) return false;

        if (node.ns == .NS_Svg and node.local_name.oneOf(&.{
            .foreignObject, .desc, .title,
        })) return false;
    }
    return false;
}

// --- Tests ---
const testing = std.testing;
const Document = @import("../../dom/Document.zig");

test "generate implied end tags" {
    const allocator = std.testing.allocator;
    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var p = Element.init(allocator, .NS_Html, LocalName.fromTag(.p), doc);
    var li = Element.init(allocator, .NS_Html, LocalName.fromTag(.li), doc);

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&p);
    try stack.append(&li);

    stack.generateImpliedEndTags(null);

    try testing.expectEqual(2, stack.len());
    try testing.expect(stack.currentNode().local_name.is(.body));
}

test "generate implied end tags exclude" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var p = Element.init(allocator, .NS_Html, LocalName.fromTag(.p), doc);
    var li = Element.init(allocator, .NS_Html, LocalName.fromTag(.li), doc);

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&p);
    try stack.append(&li);

    stack.generateImpliedEndTags(.p);

    try testing.expectEqual(3, stack.len());
    try testing.expect(stack.currentNode().local_name.is(.p));
}

test "last stack element" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var first_p = Element.init(allocator, .NS_Html, LocalName.fromTag(.p), doc);
    var div = Element.init(allocator, .NS_Html, LocalName.fromTag(.div), doc);
    var second_p = Element.init(allocator, .NS_Html, LocalName.fromTag(.p), doc);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&first_p);
    try stack.append(&div);
    try stack.append(&second_p);

    const result = stack.lastStackElement(.p);
    const result2 = stack.lastStackElement(.li);

    try std.testing.expect(result.? == &second_p);
    try std.testing.expect(result2 == null);
}

test "pop until poped" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var div = Element.init(allocator, .NS_Html, LocalName.fromTag(.div), doc);
    var p = Element.init(allocator, .NS_Html, LocalName.fromTag(.p), doc);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&div);
    try stack.append(&p);

    stack.popUntilPopped(.body);

    try std.testing.expectEqual(1, stack.len());
    try std.testing.expect(stack.currentNode() == &html);
}

test "pop until" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var div = Element.init(allocator, .NS_Html, LocalName.fromTag(.div), doc);
    var p = Element.init(allocator, .NS_Html, LocalName.fromTag(.p), doc);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&div);
    try stack.append(&p);

    stack.popUntil(.body);

    try std.testing.expectEqual(2, stack.len());
    try std.testing.expect(stack.currentNode() == &body);
}

test "pop until one of popped" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var table = Element.init(allocator, .NS_Html, LocalName.fromTag(.table), doc);
    var div = Element.init(allocator, .NS_Html, LocalName.fromTag(.div), doc);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&table);
    try stack.append(&div);

    stack.popUntilOneOfPopped(&.{ .body, .table });

    try std.testing.expectEqual(3, stack.len());
    try std.testing.expect(stack.currentNode() == &table);
}

test "has element in table scope" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var table = Element.init(allocator, .NS_Html, LocalName.fromTag(.table), doc);
    var tr = Element.init(allocator, .NS_Html, LocalName.fromTag(.tr), doc);
    var td = Element.init(allocator, .NS_Html, LocalName.fromTag(.td), doc);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    try stack.append(&html);
    try stack.append(&table);
    try stack.append(&tr);
    try stack.append(&td);

    try std.testing.expect(stack.hasElementInTableScope(.td));
}

test "has element in scope custom" {
    const allocator = std.testing.allocator;

    const doc = Document.init(allocator);
    defer doc.destroy(allocator);

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), doc);
    var body = Element.init(allocator, .NS_Html, LocalName.fromTag(.body), doc);
    var ol = Element.init(allocator, .NS_Html, LocalName.fromTag(.ol), doc);
    var li = Element.init(allocator, .NS_Html, LocalName.fromTag(.li), doc);

    var stack = OpenElementStack.init(allocator);
    defer stack.deinit();

    try stack.append(&html);
    try stack.append(&body);
    try stack.append(&ol);
    try stack.append(&li);

    try std.testing.expect(stack.hasElementInScopeCustom(.li, &.{ .ol, .ul }));
}
