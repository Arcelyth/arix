//! Implementation of CSS Namespaces Level 3.
//! See https://www.w3.org/TR/css-namespaces-3/

const std = @import("std");
const String = @import("String.zig");
const Stream = @import("syntax/ComponentValueStream.zig");
const syntax = @import("syntax/parsing_results.zig");

pub const Prefix = union(enum) {
    omitted, // X
    none, // |X
    any, // *|X
    named: String, // toto|X
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

// https://www.w3.org/TR/css-namespaces-3/#syntax
pub fn parseNamespace(rule: *const syntax.AtRule) ?Declaration {
    if (!rule.name.eqlAscii("namespace")) return null;
    return parseNamespace_NOCHECK(rule);
}

/// Parse an @namespace rule without checking name. Use this if you have already checked before.
pub fn parseNamespace_NOCHECK(rule: *const syntax.AtRule) ?Declaration {
    if (rule.declarations != null or rule.child_rules != null) return null;
    var input = Stream.init(rule.prelude);
    input.discardWhitespace();
    const prefix = input.consumeIdent();
    input.discardWhitespace();
    const value = input.consume() orelse return null;
    const name = switch (value.*) {
        .preserved_token => |tk| switch (tk) {
            .string => tk.string,
            .url => tk.url,
            else => return null,
        },
        .function => |function| blk: {
            if (!function.name.eqlAscii("url")) return null;
            var args = Stream.init(function.value);
            args.discardWhitespace();
            const arg = args.consume() orelse return null;
            if (arg.* != .preserved_token or arg.preserved_token != .string) return null;
            args.discardWhitespace();
            if (!args.empty()) return null;
            break :blk arg.preserved_token.string;
        },
        else => return null,
    };
    input.discardWhitespace();
    if (!input.empty()) return null;
    return .{ .prefix = prefix, .name = name };
}

/// Consume qname or wqname.
pub fn consumeQualifiedName(input: *Stream, comptime wildcard_prefix: bool) ?QualifiedName {
    const start = input.index;
    const prefix = consumePrefix(input, wildcard_prefix);
    const name = input.consumeIdent() orelse {
        // On mismatch, leave the stream unchanged.
        input.restore(start);
        return null;
    };
    return .{ .namespace = prefix, .name = name };
}

/// Consume wqwname, allowing wildcard prefixes and wildcard local names.
pub fn consumeWildcardName(input: *Stream) ?WildcardName {
    const start = input.index;
    const prefix = consumePrefix(input, true);
    if (input.consumeIdent()) |name| return .{ .namespace = prefix, .name = name };
    if (input.isDelimAt(0, '*')) {
        input.advance();
        return .{ .namespace = prefix, .name = null };
    }
    input.restore(start);
    return null;
}

fn consumePrefix(input: *Stream, comptime wildcard: bool) Prefix {
    if (input.isDelimAt(0, '|') and !input.isDelimAt(1, '|')) {
        input.advance();
        return .none;
    }
    const value = input.peek() orelse return .omitted;
    if (value.* != .preserved_token) return .omitted;
    const tk = value.preserved_token;
    // Leave the host's || combinator and |= attribute matcher unconsumed.
    if ((tk == .ident or (wildcard and input.isDelimAt(0, '*'))) and
        input.isDelimAt(1, '|') and !input.isDelimAt(2, '|') and !input.isDelimAt(2, '='))
    {
        input.advance();
        input.advance();
        return if (tk == .ident) .{ .named = tk.ident } else .any;
    }
    return .omitted;
}
