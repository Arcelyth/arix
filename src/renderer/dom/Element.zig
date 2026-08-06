const Element = @This();

const Namespace = @import("namespace.zig").Namespace;
const Node = @import("Node.zig");
const std = @import("std");
const token = @import("../html/tokenizer/token.zig");
const ln = @import("local_name");
const Document = @import("Document.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

node: Node,
ns: Namespace,
local_name: LocalName,
custom_element_registry: ?*CustomElementRegistry,

pub const dom_type = .DOM_Element;

pub fn init(ns: Namespace, local: LocalName, document: *Document) Element {
    return .{
        .node = Node.init(.DOM_Element, document),
        .ns = ns,
        .local_name = local,
        .custom_element_registry = null,
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

pub inline fn isMathMLTextIntegrationPoint(self: Element) bool {
    if (self.ns != .NS_MathML) return false;

    return self.local_name.is(.mi) or
        self.local_name.is(.mo) or
        self.local_name.is(.mn) or
        self.local_name.is(.ms) or
        self.local_name.is(.mtext);
}

pub fn isHtmlIntegrationPoint(self: Element, tk: token.Tag) bool {
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

pub inline fn isMathMLAnnotationXml(self: Element) bool {
    return self.ns == .NS_MathML and self.local_name.is(.annotation_xml);
}
