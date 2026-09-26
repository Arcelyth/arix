const std = @import("std");
const types = @import("types.zig");
const String = @import("../String.zig");
const namespace = @import("../namespace.zig");
const Element = @import("../../dom/Element.zig");
const Node = @import("../../dom/Node.zig");
const Namespace = @import("../../dom/namespace.zig").Namespace;
const Component = types.ComplexSelector.Component;

pub const Context = struct {
    namespaces: *const namespace.Context = &.{},

    fn defaultNamespace(self: Context) namespace.Resolved {
        return if (self.namespaces.default_namespace) |name| namespace.Resolved.fromName(name) else .any;
    }
};

pub fn matchSelectorList(selectors: *const types.SelectorList, element: *const Element, context: Context) bool {
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

pub fn matchSimple(selector: types.SimpleSelector, element: *const Element, context: Context) bool {
    _ = selector;
    _ = element;
    _ = context;
}

pub fn matchNamespace(prefix: namespace.Prefix, actual: ?Namespace, unprefixed: namespace.Resolved, context: Context) bool {
    const resolved = context.namespaces.resolve(prefix, unprefixed) catch return false;
    return switch (resolved) {
        .any => true,
        .none => actual == null,
        .named => |name| if (actual) |ns| name.eql(String.fromSource(ns.toStr())) else false,
    };
}
