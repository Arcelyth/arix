const std = @import("std");
const types = @import("types.zig");
const String = @import("../String.zig");
const Case = String.Case;
const namespace = @import("../namespace.zig");
const Element = @import("../../dom/Element.zig");
const Node = @import("../../dom/Node.zig");
const Namespace = @import("../../dom/namespace.zig").Namespace;
const Component = types.ComplexSelector.Component;
const SelectorList = types.SelectorList;
const SimpleSelector = types.SimpleSelector;
const AttributeSelector = types.AttributeSelector;

pub const Context = struct {
    namespaces: *const namespace.Context = &.{},

    fn defaultNamespace(self: Context) namespace.Resolved {
        return if (self.namespaces.default_namespace) |name| namespace.Resolved.fromName(name) else .any;
    }
};

pub fn matchSelectorList(selectors: *const SelectorList, element: *const Element, context: Context) bool {
    for (selectors.selectors) |selector| {
        if (matchComplex(selector.components, element, context)) return true;
    }
    return false;
}

pub fn matchComplex(components: []const Component, element: *const Element, context: Context) bool {
    // Scan from right to left.
    var end = components.len;
    var current = element;

    while (end != 0) {
        var start = end;
        while (start != 0 and components[start - 1] != .combinator) : (start -= 1) {}
        if (!matchCompound(components[start..end], current, context)) return false;
        if (start == 0) return true;
        end = start - 1;
        if (end == 0) @panic("TODO: relative selector matching requires an anchor");
        switch (components[end].combinator) {
            .child => current = current.parentElement() orelse return false,
            .next_sibling => current = current.previousElement() orelse return false,
            .descendant, .subsequent_sibling => |cb| {
                var candidate = if (cb == .descendant) current.parentElement() else current.previousElement();
                while (candidate) |related| {
                    // Retry the entire left side for every candidate, not just
                    // its rightmost compound. A nearer match can be a dead end.
                    if (matchComplex(components[0..end], related, context)) return true;
                    candidate = if (cb == .descendant) related.parentElement() else related.previousElement();
                }
                return false;
            },
            .column => @panic("TODO: column combinator matching requires the HTML table model"),
        }
    }
    return false;
}

pub fn matchCompound(components: []const Component, element: *const Element, context: Context) bool {
    if (components.len == 0) return false;
    var i = components.len;
    while (i != 0) {
        i -= 1;
        if (components[i] == .pseudo_element) @panic("TODO: pseudo-element matching (Selectors §17.4)");
        if (!matchSimple(components[i].simple, element, context)) return false;
    }
    // The default namespace also restricts an implicit universal selector.
    return components[0].simple == .type_selector or components[0].simple == .universal or
        matchNamespace(.omitted, element.ns, context.defaultNamespace(), context);
}

pub fn matchSimple(selector: SimpleSelector, element: *const Element, context: Context) bool {
    return switch (selector) {
        .type_selector => |name| matchNamespace(name.namespace, element.ns, context.defaultNamespace(), context) and
            name.name.eqlUtf8WithCase(element.local_name.slice(), if (element.isHtml()) .selector_lower else .exact),
        .universal => |prefix| matchNamespace(prefix, element.ns, context.defaultNamespace(), context),
        else => matchSubclass(selector, element, context),
    };
}

pub fn matchSubclass(selector: SimpleSelector, element: *const Element, context: Context) bool {
    return switch (selector) {
        .id => |value| matchId(value, element),
        .class => |value| matchClass(value, element),
        .attribute => |attr| matchAttribute(attr, element, context),
        .pseudo_class => @panic("TODO: pseudo-class matching"),
        else => unreachable,
    };
}

pub fn matchId(value: String, element: *const Element) bool {
    if (value.len() == 0) return false;
    const attr = element.attrs.getFromNamespaceAndLocalName(null, .id) orelse return false;
    const mode: Case = if (element.node.node_doc.mode == .DM_Quirks) .ignore_ascii else .exact;
    return value.eqlUtf8WithCase(attr.value.slice(), mode);
}

pub fn matchClass(value: String, element: *const Element) bool {
    const attr = element.attrs.getFromNamespaceAndLocalName(null, .class) orelse return false;
    const mode: Case = if (element.node.node_doc.mode == .DM_Quirks) .ignore_ascii else .exact;
    return containsWord(value, attr.value.slice(), mode);
}

/// Check if attribute value like "a b c" contains b.
fn containsWord(expected: String, actual: []const u8, mode: Case) bool {
    if (expected.len() == 0) return false;
    var words = std.mem.tokenizeAny(u8, actual, "\t\n\x0C\r ");
    while (words.next()) |word| if (expected.eqlUtf8WithCase(word, mode)) return true;
    return false;
}

pub fn matchAttribute(selector: AttributeSelector, element: *const Element, context: Context) bool {
    for (element.attrs.data.items) |attr| {
        if (!matchNamespace(selector.name.namespace, attr.ns, .none, context)) continue;
        const name_case: Case = if (element.isHtml() and attr.ns == null) .lower_self else .exact;
        if (!selector.name.name.eqlUtf8WithCase(attr.local_name.slice(), name_case)) continue;
        const comparison = selector.comparison orelse return true;
        const mode: Case = switch (comparison.modifier) {
            .insensitive => .ignore_ascii,
            .sensitive => .exact,
            .omitted => if (element.isHtml() and attr.ns == null and
                insensitive_attributes.has(attr.local_name.slice())) .ignore_ascii else .exact,
        };
        if (matchValue(comparison.matcher, comparison.value, attr.value.slice(), mode)) return true;
    }
    return false;
}

pub fn matchValue(matcher: AttributeSelector.Matcher, expected: String, actual: []const u8, mode: Case) bool {
    switch (matcher) {
        .equal => return expected.eqlUtf8WithCase(actual, mode),
        .includes => return containsWord(expected, actual, mode),
        .dash_match => {
            const end = expected.prefixLength(actual, mode) orelse return false;
            return end == actual.len or actual[end] == '-';
        },
        .prefix => return expected.len() != 0 and expected.prefixLength(actual, mode) != null,
        .suffix => return expected.len() != 0 and expected.isSuffixOfWithCase(actual, mode),
        .substring => return expected.len() != 0 and expected.isSubstringOfWithCase(actual, mode),
    }
}

pub fn matchNamespace(prefix: namespace.Prefix, actual: ?Namespace, unprefixed: namespace.Resolved, context: Context) bool {
    const resolved = context.namespaces.resolve(prefix, unprefixed) catch return false;
    return switch (resolved) {
        .any => true,
        .none => actual == null,
        .named => |name| if (actual) |ns| name.eql(String.fromSource(ns.toStr())) else false,
    };
}

// https://html.spec.whatwg.org/multipage/semantics-other.html#case-sensitivity-of-selectors
const insensitive_attributes = std.StaticStringMap(void).initComptime(.{
    .{"accept"},
    .{"accept-charset"},
    .{"align"},
    .{"alink"},
    .{"axis"},
    .{"bgcolor"},
    .{"charset"},
    .{"checked"},
    .{"clear"},
    .{"codetype"},
    .{"color"},
    .{"compact"},
    .{"declare"},
    .{"defer"},
    .{"dir"},
    .{"direction"},
    .{"disabled"},
    .{"enctype"},
    .{"face"},
    .{"frame"},
    .{"hreflang"},
    .{"http-equiv"},
    .{"lang"},
    .{"language"},
    .{"link"},
    .{"media"},
    .{"method"},
    .{"multiple"},
    .{"nohref"},
    .{"noresize"},
    .{"noshade"},
    .{"nowrap"},
    .{"readonly"},
    .{"rel"},
    .{"rev"},
    .{"rules"},
    .{"scope"},
    .{"scrolling"},
    .{"selected"},
    .{"shape"},
    .{"target"},
    .{"text"},
    .{"type"},
    .{"valign"},
    .{"valuetype"},
    .{"vlink"},
});
