const Element = @This();

const Namespace = @import("namespace.zig").Namespace;
const Node = @import("Node.zig");
const std = @import("std");
const token = @import("../html/tokenizer/token.zig");
const LocalName = @import("local_name").LocalName;

node: Node,
ns: Namespace,
local_name: LocalName,

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
