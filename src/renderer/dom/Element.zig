const Element = @This();

const Namespace = @import("namespace.zig").Namespace;
const Node = @import("Node.zig");
const std = @import("std");
const token = @import("../html/tokenizer/token.zig");
const ln = @import("local_name");
const Document = @import("Document.zig");
const DocumentFragment = @import("DocumentFragment.zig");
const NamedNodeMap = @import("NamedNodeMap.zig");
const Attr = @import("Attr.zig");
const Attribute = token.Attribute;
const Attrs = @import("Attrs.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const CustomElementDefinition = @import("CustomElementDefinition.zig");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;
const ShadowRoot = @import("ShadowRoot.zig");

pub const CustomElementState = enum {
    CES_Undefined,
    CES_Failed,
    CES_Uncustomized,
    CES_Precustomized,
    CES_Custom,
};

const ScriptElementType = enum { SET_Classic, SET_Module, SET_Importmap, SET_Speculationrules };

const ScriptResult = union(enum) {
    SR_Uninitialized,
    // TODO:
};

node: Node,
// namespace
ns: ?Namespace,
// namespace prefix
prefix: ?LocalName,
local_name: LocalName,
custom_element_registry: ?*CustomElementRegistry,
custom_element_state: CustomElementState,
custom_element_definition: ?*CustomElementDefinition,
is: ?[]const u8,
shadow_root: ?*ShadowRoot,
attr_list: NamedNodeMap,
attrs: Attrs,
// -- Script element's field:
// Parser document.
parser_doc: ?*Document,
prep_time_doc: ?*Document,
force_async: bool,
from_ext_file: bool,
// ready to be parser-executed
parser_exec_ready: bool,
already_started: bool,
delaying_the_load_event: bool,
ty: ?ScriptElementType,
result: ?ScriptResult,
// --
// -- Template element's field:
temp_contents: ?*DocumentFragment,

pub const dom_type = .DOM_Element;

pub fn init(alloc: std.mem.Allocator, ns: Namespace, local: LocalName, document: *Document) Element {
    return .{
        .node = Node.init(dom_type, document),
        .ns = ns,
        .prefix = null,
        .local_name = local,
        .custom_element_registry = null,
        .custom_element_state = .CES_Undefined,
        .custom_element_definition = null,
        .is = null,
        .shadow_root = null,
        .attr_list = NamedNodeMap.init(null),
        .attrs = Attrs.init(alloc),
        .parser_doc = null,
        .prep_time_doc = null,
        .force_async = true,
        .from_ext_file = false,
        .parser_exec_ready = false,
        .already_started = false,
        .delaying_the_load_event = false,
        .ty = null,
        .result = .SR_Uninitialized,
        .temp_contents = null,
    };
}

// https://dom.spec.whatwg.org/#concept-create-element
pub fn create(document: *Document, local: LocalName, namespace: ?Namespace, prefix: ?LocalName, is: ?[]const u8, sce: bool, registry: ?*CustomElementRegistry) *Element {
    const def = lookingUpCustomElementDefinition(registry, namespace, local, is);
    if (def) |d| {
        if (!d.*.name.eql(d.*.local_name)) {
            const interface = getInterface(local, .NS_Html);
            var result = createInternal(document, interface, local, namespace, prefix, .CES_Undefined, is, registry);
            if (sce) {
                result.upgrade(d) catch {
                    @panic("TODO: Handle exceptions.");
                };
            } else {
                result.enqueueUpgradeReaction(d);
            }
            return result;
        } else {
            if (sce) {} else {}
            if (true) @panic("TODO");
        }
    } else {
        const interface = getInterface(local, .NS_Html);
        var result = createInternal(document, interface, local, namespace, prefix, .CES_Undefined, is, registry);
        if (namespace == .NS_Html and (local.isValidCustomElementName() or is != null))
            result.custom_element_state = .CES_Undefined;

        return result;
    }
}

pub fn upgrade(self: *Element, def: *CustomElementDefinition) !void {
    _ = self;
    _ = def;
}

pub fn enqueueUpgradeReaction(self: *Element, def: *CustomElementDefinition) void {
    _ = self;
    _ = def;
}

// https://dom.spec.whatwg.org/#create-an-element-internal
pub fn createInternal(document: *Document, interface: bool, local: LocalName, namespace: ?Namespace, prefix: ?LocalName, state: CustomElementState, is: ?[]const u8, registry: ?*CustomElementRegistry) *Element {
    _ = interface;
    var node = Node.create(document);
    var element = node.downcast(Element);
    element.ns = namespace;
    element.prefix = prefix;
    element.local_name = local;
    element.custom_element_registry = registry;
    element.custom_element_state = state;
    element.custom_element_definition = null;
    element.is = is;
    std.debug.assert(element.attrs.isEmpty());
    return element;
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
    if (self.ns != .NS_Math) return false;

    return self.local_name.is(.mi) or
        self.local_name.is(.mo) or
        self.local_name.is(.mn) or
        self.local_name.is(.ms) or
        self.local_name.is(.mtext);
}

pub fn isHtmlIntegrationPoint(self: *const Element, tk: token.Token) bool {
    if (self.ns == .NS_Svg) {
        return self.local_name.is(.foreignObject) or
            self.local_name.is(.desc) or
            self.local_name.is(.title);
    }

    if (self.isMathMLAnnotationXml()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag)
                    return tag.hasAttr("encoding", "text/html", false) or
                        tag.hasAttr("encoding", "application/xhtml+xml", false);
            },
            else => {},
        }
    }

    return false;
}

pub inline fn isMathMLAnnotationXml(self: *const Element) bool {
    return self.ns == .NS_Math and self.local_name.is(.@"annotation-xml");
}

pub fn appendAttrs(self: *Element, attrs: []Attribute) !void {
    for (attrs) |attr| {
        try self.attrs.append(.{
            .ns = null,
            .prefix = null,
            .local_name = attr.name,
            .value = attr.value.clone(),
            .element = null,
        });
    }
}

pub fn isXmlnsXLinkValid(self: *const Element) bool {
    for (self.attrs.data.items) |attr| {
        if (attr.ns == .NS_Xmlns and attr.local_name.is(.xmlns) and std.mem.eql(u8, attr.value.slice(), Namespace.Xmlns)) return false;
        if (attr.ns == .NS_Xmlns and attr.local_name.is(.xlink) and std.mem.eql(u8, attr.value.slice(), Namespace.XLink)) return false;
    }
    return true;
}

// https://html.spec.whatwg.org/multipage/forms.html#category-reset
pub fn isResettable(self: *const Element) bool {
    const tag = self.local_name.toTag() orelse return false;
    return switch (tag) {
        .input, .output, .select, .textarea => true,
        else => false,
    };
}

// https://html.spec.whatwg.org/#form-associated-custom-element
pub fn isFormAssociatedCustomElement(self: *const Element) bool {
    if (self.custom_element_definition) |def|
        return def.form_associated;
    return false;
}

pub fn isFormAssociatedElement(self: *const Element) bool {
    _ = self;
    return false;
}

pub fn attachShadowRoot(self: *Element, mode: ShadowRoot.ShadowRootMode, clonable: bool, serializable: bool, delegates_focus: bool, slot_ass: ShadowRoot.ShadowRootSlotAssignment, registry: ?*CustomElementRegistry) !void {
    //TODO
    _ = self;
    _ = mode;
    _ = clonable;
    _ = delegates_focus;
    _ = slot_ass;
    _ = serializable;
    _ = registry;
}

/// If the type attribute define a value sanitization algorithm.
/// TODO:
pub fn isTypeDefineVSA(self: *Element) bool {
    _ = self;
    return false;
}

// https://html.spec.whatwg.org/#look-up-a-custom-element-registry
pub fn lookingUpCustomElementRegistry(intended_parent: *Node) ?*CustomElementRegistry {
    return switch (intended_parent.type_id) {
        .DOM_Element => intended_parent.downcast(Element).custom_element_registry,
        .DOM_Document => intended_parent.downcast(Element).custom_element_registry,
        .DOM_ShadowRoot => intended_parent.downcast(Element).custom_element_registry,
        else => null,
    };
}

// https://html.spec.whatwg.org/#look-up-a-custom-element-definition
pub fn lookingUpCustomElementDefinition(registry: ?*CustomElementRegistry, namespace: ?Namespace, local: LocalName, is: ?[]const u8) ?*CustomElementDefinition {
    if (registry) |reg| {
        if (namespace) |n| {
            if (n != .NS_Html) return null;
            if (reg.lookup(local.slice(), local)) |res| return res else if (is) |is_| {
                if (reg.lookup(is_, local)) |res| return res;
            }
        } else return null;
    }
    return null;
}

// TODO:
pub fn getInterface(local: LocalName, ns: Namespace) bool {
    _ = local;
    _ = ns;
    return true;
}
