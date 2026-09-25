//! Implementation of CSS Namespaces Level 3.
//! See https://www.w3.org/TR/css-namespaces-3/

const std = @import("std");
const String = @import("String.zig");

pub const Prefix = union(enum) {
    omitted,        // X 
    none,           // |X
    any,            // *|X
    named: String,  // toto|X
};

pub const QualifiedName = struct {
    namespace: Prefix = .omitted, 
    name: String,
};

pub const WildcardName = struct {
    namespace: Prefix = .omitted,
    /// null represents the '*' local name, not an omitted local name.
    name: ?String,
};

/// A namespace declaration from an `@namespace` rule.
pub const Declaration = struct {
    prefix: ?String,
    name: String,
};

/// Used when matching a qualified name.
pub const Resolved = union(enum) {
    any,
    none,
    named: String,

    pub fn fromName(name: String) Resolved {
        return if (name.len() == 0) .none else .{ .named = name };
    }
};
