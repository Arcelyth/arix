//! Implementation of selector's structures.
//! See https://www.w3.org/TR/selectors-4/#structure
const std = @import("std");
const String = @import("../String.zig");
const ComponentValue = @import("../syntax/parsing_results.zig").ComponentValue;
const namespace = @import("../namespace.zig");

/// Represents `[attr]` or `[attr operator value modifier]`.
pub const AttributeSelector = struct {
    pub const Matcher = enum {
        equal, // `=`
        includes, // `~=`
        dash_match, // `|=`
        prefix, // `^=`
        suffix, // `$=`
        substring, // `*=`
    };

    pub const Modifier = enum {
        omitted,
        insensitive, // `i`
        sensitive, // `s`
    };

    name: namespace.QualifiedName,

    comparison: ?struct {
        matcher: Matcher,
        value: String,
        modifier: Modifier = .omitted,
    } = null,
};

pub const SimpleSelector = union(enum) {
    type_selector: namespace.QualifiedName,
    universal: namespace.Prefix,
    attribute: AttributeSelector,
    class: String,
    id: String,
    pseudo_class: PseudoClassSelector,
};

pub const PseudoClassSelector = struct {
    name: String,
    arguments: ?[]const ComponentValue = null,
};

pub const PseudoElementSelector = struct {
    name: String,
    arguments: ?[]const ComponentValue = null,
};

pub const CompoundSelector = struct {
    simple_selectors: []const SimpleSelector,
};

pub const PseudoCompoundSelector = struct {
    pseudo_element: PseudoElementSelector,
    pseudo_classes: []const PseudoClassSelector = &.{},
};

pub const Combinator = enum {
    descendant,
    child,
    next_sibling,
    subsequent_sibling,
    column,
};

pub const ComplexSelector = struct {
    components: []const Component,

    pub const Component = union(enum) {
        simple: SimpleSelector,
        pseudo_element: PseudoElementSelector,
        combinator: Combinator,
    };

    pub fn deinit(self: ComplexSelector, allocator: std.mem.Allocator) void {
        allocator.free(self.components);
    }
};

pub const SelectorList = struct {
    selectors: []const ComplexSelector,

    pub fn deinit(self: SelectorList, allocator: std.mem.Allocator) void {
        for (self.selectors) |selector| selector.deinit(allocator);
        allocator.free(self.selectors);
    }
};
pub const CompoundSelectorList = []const CompoundSelector;
pub const SimpleSelectorList = []const SimpleSelector;

pub const Mode = struct {
    kind: enum { complex, compound, simple } = .complex,
    real: bool = false,
    relative: bool = false,
    forgiving: bool = false,
};
