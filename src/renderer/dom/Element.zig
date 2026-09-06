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
const ElementInterface = @import("element_interface.zig").ElementInterface;

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
// FIXME: For template's ownership.
temp_contents_owned: bool,
// --
// Include extra fields for specific element.
interface: ?ElementInterface,

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
        .temp_contents_owned = false,
        .interface = null,
    };
}

// https://dom.spec.whatwg.org/#concept-create-element
pub fn create(document: *Document, local: LocalName, namespace: ?Namespace, prefix: ?LocalName, is: ?[]const u8, sce: bool, registry: ?*CustomElementRegistry) *Element {
    const def = lookingUpCustomElementDefinition(registry, namespace, local, is);
    if (def) |d| {
        if (!d.*.name.eql(d.*.local_name)) {
            const interface = getInterface(local, namespace);
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
        const interface = getInterface(local, namespace);
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
pub fn createInternal(document: *Document, interface: ?ElementInterface, local: LocalName, namespace: ?Namespace, prefix: ?LocalName, state: CustomElementState, is: ?[]const u8, registry: ?*CustomElementRegistry) *Element {
    const element = document.allocator.create(Element) catch @panic("out of memory");
    element.* = Element.init(document.allocator, namespace orelse .NS_Html, local, document);
    element.ns = namespace;
    element.prefix = prefix;
    element.local_name = local;
    element.interface = interface;
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

pub fn isHtmlIntegrationPoint(self: *const Element) bool {
    if (self.ns == .NS_Svg) {
        return self.local_name.is(.foreignObject) or
            self.local_name.is(.desc) or
            self.local_name.is(.title);
    }

    if (self.isMathMLAnnotationXml()) {
        const encoding = self.attrs.getFromLocalName(.encoding) orelse return false;
        return encoding.value.eqlIgnoreCase("text/html") or
            encoding.value.eqlIgnoreCase("application/xhtml+xml");
    }

    return false;
}

pub inline fn isMathMLAnnotationXml(self: *const Element) bool {
    return self.ns == .NS_Math and self.local_name.is(.@"annotation-xml");
}

pub fn appendAttrs(self: *Element, attrs: []Attribute) !void {
    for (attrs) |attr| {
        try self.attrs.append(.{
            .ns = attr.namespace,
            .prefix = if (attr.prefix) |prefix| prefix.clone() else null,
            .local_name = attr.name.clone(),
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

pub fn isForeignIntegrationBoundary(el: *Element) bool {
    return el.ns == .NS_Html or el.isMathMLTextIntegrationPoint() or el.isHtmlIntegrationPoint();
}

// FIXME: Preliminary implementation currently, see: https://dom.spec.whatwg.org/#concept-attach-a-shadow-root.
pub fn attachShadowRoot(self: *Element, mode: ShadowRoot.ShadowRootMode, clonable: bool, serializable: bool, delegates_focus: bool, slot_ass: ShadowRoot.ShadowRootSlotAssignment, registry: ?*CustomElementRegistry) !void {
    if (self.shadow_root != null) return error.ShadowRootAlreadyAttached;

    const shadow = try self.node.node_doc.allocator.create(ShadowRoot);
    shadow.* = ShadowRoot.init(self.node.node_doc);
    shadow.mode = mode;
    shadow.doc_frag.host = self;
    shadow.clonable = clonable;
    shadow.serialize = serializable;
    shadow.delegates_focus = delegates_focus;
    shadow.slot_assignment = slot_ass;
    shadow.custom_element_registry = registry;
    self.shadow_root = shadow;
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
        .DOM_Document => intended_parent.downcast(Document).custom_element_registry,
        .DOM_ShadowRoot => null,
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

// https://html.spec.whatwg.org/multipage/parsing.html#special
pub fn isSpecial(self: *const Element) bool {
    const tag = self.local_name.toTag() orelse return false;

    return switch (self.ns orelse return false) {
        .NS_Html => switch (tag) {
            .address, .applet, .area, .article, .aside, .base, .basefont, .bgsound, .blockquote, .body, .br, .button, .caption, .center, .col, .colgroup, .dd, .details, .dir, .div, .dl, .dt, .embed, .fieldset, .figcaption, .figure, .footer, .form, .frame, .frameset, .h1, .h2, .h3, .h4, .h5, .h6, .head, .header, .hgroup, .hr, .html, .iframe, .img, .input, .keygen, .li, .link, .listing, .main, .marquee, .menu, .meta, .nav, .noembed, .noframes, .noscript, .object, .ol, .p, .param, .plaintext, .pre, .script, .search, .section, .select, .source, .style, .summary, .table, .tbody, .td, .template, .textarea, .tfoot, .th, .thead, .title, .tr, .track, .ul, .wbr, .xmp => true,
            else => false,
        },

        .NS_Math => switch (tag) {
            .mi, .mo, .mn, .ms, .mtext, .@"annotation-xml" => true,
            else => false,
        },

        .NS_Svg => switch (tag) {
            .foreignObject, .desc, .title => true,
            else => false,
        },
        else => false,
    };
}

pub fn getInterface(local: LocalName, ns: ?Namespace) ?ElementInterface {
    if (ns != .NS_Html) return null;
    if (local.is(.option)) return .{ .option = .{} };
    if (local.is(.select)) return .{ .select = .{} };
    if (local.is(.selectedcontent)) return .{ .selectedcontent = .{} };
    return null;
}

/// Cloning steps defined by HTML for element interfaces represented by Element.
pub fn runCloningSteps(self: *Element, copy: *Element, subtree: bool) void {
    _ = self;
    _ = copy;
    _ = subtree;
}

// https://html.spec.whatwg.org/multipage/form-elements.html#maybe-clone-an-option-into-selectedcontent
pub fn maybeCloneIntoSelectedContent(self: *Element) void {
    const option = switch (self.interface orelse return) {
        .option => |*value| value,
        else => return,
    };

    const select = self.nearestAncestorSelect() orelse return;
    if (!option.selectedness) return;
    const selected_content = select.enabledSelectedContent() orelse return;
    self.cloneIntoSelectedContent(selected_content);
}

pub fn insertedIntoParent(self: *Element) void {
    const option = switch (self.interface orelse return) {
        .option => |*value| value,
        else => return,
    };
    if (option.selectedness) return;

    const select = self.nearestAncestorSelect() orelse return;
    option.selectedness = select.asNode().findDescendant(.option) == self;
}

// https://html.spec.whatwg.org/multipage/form-elements.html#select-enabled-selectedcontent
pub fn enabledSelectedContent(self: *Element) ?*Element {
    switch (self.interface orelse return null) {
        .select => {},
        else => return null,
    }
    if (self.attrs.getFromLocalName(.multiple) != null) return null;
    const sc = self.asNode().findDescendant(.selectedcontent) orelse return null;
    switch (sc.interface orelse return null) {
        .selectedcontent => |s| if (s.disabled) return null,
        else => {},
    }
    return sc;
}

// https://html.spec.whatwg.org/multipage/form-elements.html#option-element-nearest-ancestor-select
pub fn nearestAncestorSelect(self: *Element) ?*Element {
    var ancestor_optgroup: ?*Element = null;
    var ancestor = self.node.parent;

    while (ancestor) |node| : (ancestor = node.parent) {
        if (node.type_id != .DOM_Element) continue;
        const element = node.downcast(Element);
        if (element.ns != .NS_Html) continue;

        if (element.local_name.oneOf(&.{ .datalist, .hr, .option })) return null;
        if (element.local_name.is(.optgroup)) {
            if (ancestor_optgroup != null) return null;
            ancestor_optgroup = element;
        }
        if (element.local_name.is(.select)) return element;
    }
    return null;
}

// https://html.spec.whatwg.org/multipage/form-elements.html#clone-an-option-into-a-selectedcontent
pub fn cloneIntoSelectedContent(self: *Element, selected_content: *Element) void {
    const document = self.node.node_doc;
    const document_fragment = document.allocator.create(DocumentFragment) catch @panic("OutOfMemory");
    document_fragment.* = DocumentFragment.init(document);

    var child = self.node.first_child;
    while (child) |node| : (child = node.next_sibling)
        _ = node.clone(.{ .subtree = true, .parent = &document_fragment.node });

    Node.replaceAll(&document_fragment.node, selected_content.asNode());
    document.allocator.destroy(document_fragment);
}
