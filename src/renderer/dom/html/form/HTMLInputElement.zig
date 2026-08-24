const HTMLInputElement = @This();

const std = @import("std");
const HTMLElement = @import("../HTMLElement.zig");
const Node = @import("../../Node.zig");
const Element = @import("../../Element.zig");
const type_ = @import("../../type.zig");
const File = @import("input_type/File.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

html_element: HTMLElement,
allocator: std.mem.Allocator,
input_text: StraleUtf8Global,
dirty_value: bool,
checkedness: bool,
dirty_checkedness: bool,
user_validity: bool,
selected_files: std.ArrayList(File),

pub const dom_type = .DOM_HTMLInputElement;

pub fn fromNode(node: *Node) *HTMLInputElement {
    const element: *Element = @fieldParentPtr("node", node);
    const html_element: *HTMLElement = @fieldParentPtr("element", element);
    return @fieldParentPtr("html_element", html_element);
}

pub inline fn asNode(self: *HTMLInputElement) *Node {
    return &self.html_element.element.node;
}

pub inline fn asElement(self: *HTMLInputElement) *Element {
    return &self.html_element.element;
}

pub inline fn asHTMLElement(self: *HTMLInputElement) *HTMLElement {
    return &self.html_element;
}

pub fn reset(self: *HTMLInputElement) void {
    self.user_validity = false;
    self.dirty_value = false;
    self.dirty_checkedness = false;

    const el = self.asElement();
    if (el.attrs.getFromLocalName(.value)) |v|
        self.input_text = v.value.clone()
    else
        self.input_text.clear();

    if (el.attrs.getFromLocalName(.checked)) |_|
        self.checkedness = true
    else
        self.checkedness = false;

    self.selected_files.clearAndFree(self.allocator);
    if (el.isTypeDefineVSA()) @panic("[TODO]: value sanitization algorithm");
}
