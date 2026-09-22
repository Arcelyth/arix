/// Implementation of selector's structures.
/// See https://www.w3.org/TR/selectors-4/#structure
const String = @import("../String.zig");
const ComponentValue = @import("../syntax/parsing_results.zig").ComponentValue;

pub const SimpleSelector = union(enum) {
    type_selector: String,
    universal,
    attribute: []const ComponentValue,
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
};

pub const ComplexSelector = struct {
    parts: []const Part,

    pub const Part = struct {
        combinator: ?Combinator = null,
        selector: union(enum) {
            compound: CompoundSelector,
            pseudo_compound: PseudoCompoundSelector,
        },
    };
};

pub const SelectorList = []const ComplexSelector;
pub const CompoundSelectorList = []const CompoundSelector;
pub const SimpleSelectorList = []const SimpleSelector;
