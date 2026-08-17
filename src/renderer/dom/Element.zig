const Element = @This();

const namespace_ = @import("namespace.zig");
const Namespace = namespace_.Namespace;
const namespaceToStr = namespace_.namespaceToStr;
const Node = @import("Node.zig");
const std = @import("std");
const token = @import("../html/tokenizer/token.zig");
const ln = @import("local_name");
const Document = @import("Document.zig");
const NamedNodeMap = @import("NamedNodeMap.zig");
const Attr = @import("Attr.zig");
const Attribute = token.Attribute;
const Attrs = @import("Attrs.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const CustomElementDefinition = @import("CustomElementDefinition.zig");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

pub const CustomElementState = enum {
    CES_Undefined,
    CES_Failed,
    CES_Uncustomized,
    CES_Precustomized,
    CES_Custom,
};

node: Node,
// namespace
ns: Namespace,
// ns_prefix:
local_name: LocalName,
custom_element_registry: ?*CustomElementRegistry,
custom_element_state: CustomElementState,
custom_element_definition: ?*CustomElementDefinition,
// TODO: Since it stand for custom name, might need to changed to Strale.
is: ?LocalName,
// shadow_root:
attr_list: NamedNodeMap,
attrs: Attrs,

pub const dom_type = .DOM_Element;

pub fn init(alloc: std.mem.Allocator, ns: Namespace, local: LocalName, document: *Document) Element {
    return .{
        .node = Node.init(.DOM_Element, document),
        .ns = ns,
        .local_name = local,
        .custom_element_registry = null,
        .custom_element_state = .CES_Undefined,
        .custom_element_definition = null,
        .is = null,
        .attr_list = NamedNodeMap.init(null),
        .attrs = Attrs.init(alloc),
    };
}

pub inline fn asNode(self: *Element) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *Element {
    return @fieldParentPtr("node", node);
}

/// Check if the local name of the element is included in the given elements.
pub fn in(self: Element, elems: []const LocalTag) bool {
    for (elems) |elem| {
        if (self.local_name.is(elem)) return true;
    }
    return false;
}

pub inline fn isMathMLTextIntegrationPoint(self: *const Element) bool {
    if (self.ns != .NS_MathML) return false;

    return self.local_name.is(.mi) or
        self.local_name.is(.mo) or
        self.local_name.is(.mn) or
        self.local_name.is(.ms) or
        self.local_name.is(.mtext);
}

pub fn isHtmlIntegrationPoint(self: *const Element, tk: token.Tag) bool {
    if (self.ns == .NS_SVG) {
        return self.local_name.is(.foreignObject) or
            self.local_name.is(.desc) or
            self.local_name.is(.title);
    }

    if (self.isMathMLAnnotationXml()) {
        if (tk.kind == .StartTag) {
            return tk.hasAttr("encoding", "text/html", false) or
                tk.hasAttr("encoding", "application/xhtml+xml", false);
        }
    }

    return false;
}

pub inline fn isMathMLAnnotationXml(self: *const Element) bool {
    return self.ns == .NS_MathML and self.local_name.is(.annotation_xml);
}

pub fn appendAttrs(self: *Element, attrs: []Attribute) !void {
    for (attrs) |attr| {
        try self.attrs.append(.{
            .ns = null,
            .local_name = attr.name,
            .value = attr.value.clone(),
            .element = null,
        });
    }
}

pub fn isXmlnsXLinkValid(self: *const Element) bool {
    for (self.attrs.data) |attr| {
        if (attr.namespace == .NS_Xmlns and attr.local_name.is(.xmlns) and std.mem.eql(u8, attr.value.slice(), namespaceToStr(.NS_Xmlns))) return false;
        if (attr.namespace == .NS_Xmlns and attr.local_name.is(.xlink) and std.mem.eql(u8, attr.value.slice(), namespaceToStr(.NS_XLink))) return false;
    }
    return true;
}

// https://html.spec.whatwg.org/multipage/forms.html#category-reset
pub fn isResettable(self: *const Element) bool {
    return switch (self.local_name) {
        .input, .output, .select, .textarea => true,
        else => false,
    };
}

pub fn isFormAssociatedCustomElement(self: *const Element) bool {
    _ = self;
    return false;
}

pub fn isFormAssociatedElement(self: *const Element) bool {
    _ = self;
    return false;
}
