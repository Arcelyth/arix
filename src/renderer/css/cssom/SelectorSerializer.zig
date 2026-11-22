//! CSSOM selector parsing and serialization.
//! https://drafts.csswg.org/cssom/#serializing-selectors
const SelectorSerializer = @This();
const std = @import("std");
const types = @import("../selectors/types.zig");
const parsing = @import("../selectors/parse.zig");
const ns = @import("../namespace.zig");
const String = @import("../String.zig");
const syntax = @import("../syntax.zig");
const Value = @import("../syntax/parsing_results.zig").ComponentValue;
const Token = @import("../syntax/token.zig").Token;
const serialize = @import("serialize.zig");
const parseGroup = @import("parsing_selectors.zig").parseGroup;

const Error = error{
    OutOfMemory,
    WriteFailed,
    InvalidUtf8,
    UndeclaredPrefix,
    InvalidSelector,
    UnsupportedPseudoFunction,
};

allocator: std.mem.Allocator,
writer: *std.Io.Writer,
namespaces: *const ns.Context = &.{},

/// Writes a comma-separated selector list.
/// https://drafts.csswg.org/cssom/#serialize-a-group-of-selectors
pub fn group(self: SelectorSerializer, list: types.SelectorList) Error!void {
    for (list.selectors, 0..) |entry, i| {
        if (i != 0) try self.writer.writeAll(", ");
        try self.selector(entry);
    }
}

/// Writes a selector in source order.
/// https://drafts.csswg.org/cssom/#serialize-a-selector
pub fn selector(self: SelectorSerializer, entry: types.ComplexSelector) Error!void {
    for (entry.components, 0..) |component, i| switch (component) {
        .combinator => |op| {
            if (i != 0) try self.writer.writeByte(' ');
            try self.writer.writeAll(switch (op) {
                .descendant => "",
                .child => "> ",
                .next_sibling => "+ ",
                .subsequent_sibling => "~ ",
                .column => "|| ",
            });
        },
        .simple => |simple| {
            if (simple == .universal and i + 1 < entry.components.len and
                entry.components[i + 1] != .combinator and
                try self.typePrefix(simple.universal) == .omitted) continue;
            try self.simpleSelector(simple);
        },
        .pseudo_element => |element| try self.pseudo("::", element.name, element.arguments),
    };
}

// https://drafts.csswg.org/cssom/#serialize-a-simple-selector
fn simpleSelector(self: SelectorSerializer, simple: types.SimpleSelector) Error!void {
    switch (simple) {
        .type_selector => |name| {
            try self.prefix(try self.typePrefix(name.namespace));
            try self.text(name.name, .identifier);
        },
        .universal => |p| {
            try self.prefix(try self.typePrefix(p));
            try self.writer.writeByte('*');
        },
        .attribute => |attr| try self.attribute(attr),
        inline .class, .id => |name, tag| {
            try self.writer.writeByte(if (tag == .class) '.' else '#');
            try self.text(name, .identifier);
        },
        .pseudo_class => |p| try self.pseudo(":", p.name, p.arguments),
    }
}

// An omitted type prefix uses the default namespace, or any namespace if none is declared.
fn typePrefix(self: SelectorSerializer, p: ns.Prefix) Error!ns.Prefix {
    if (p == .omitted) return .omitted;
    const resolved = try self.namespaces.resolve(p, .any);
    const default = self.namespaces.default_namespace;
    return switch (resolved) {
        .any => if (default == null) .omitted else .any,
        .none => if (default != null and default.?.len() == 0) .omitted else .none,
        .named => |uri| if (default != null and default.?.eql(uri)) .omitted else p,
    };
}

fn prefix(self: SelectorSerializer, p: ns.Prefix) Error!void {
    switch (p) {
        .omitted => return,
        .none => {},
        .any => try self.writer.writeByte('*'),
        .named => |name| try self.text(name, .identifier),
    }
    try self.writer.writeByte('|');
}

fn attribute(self: SelectorSerializer, attr: types.AttributeSelector) Error!void {
    try self.writer.writeByte('[');
    const resolved = try self.namespaces.resolve(attr.name.namespace, .none);
    if (resolved != .none) try self.prefix(attr.name.namespace);
    try self.text(attr.name.name, .identifier);
    if (attr.comparison) |c| {
        try self.writer.writeAll(switch (c.matcher) {
            .equal => "=",
            .includes => "~=",
            .dash_match => "|=",
            .prefix => "^=",
            .suffix => "$=",
            .substring => "*=",
        });
        try self.text(c.value, .string);
        try self.writer.writeAll(switch (c.modifier) {
            .omitted => "",
            .insensitive => " i",
            .sensitive => " s",
        });
    }
    try self.writer.writeByte(']');
}

fn text(
    self: SelectorSerializer,
    value: String,
    kind: enum { identifier, string, lowercase },
) Error!void {
    var decoded: std.Io.Writer.Allocating = .init(self.allocator);
    defer decoded.deinit();
    const bytes = switch (value.value) {
        .borrowed => |source| source,
        .owned => |points| blk: {
            for (points) |cp| try decoded.writer.print("{u}", .{cp});
            break :blk decoded.written();
        },
    };
    switch (kind) {
        .identifier => try serialize.identifier(self.writer, bytes),
        .string => try serialize.string(self.writer, bytes),
        .lowercase => try serialize.lowercaseIdentifier(self.writer, bytes),
    }
}

fn pseudo(
    self: SelectorSerializer,
    colons: []const u8,
    name: String,
    args: ?[]const Value,
) Error!void {
    try self.writer.writeAll(colons);
    try self.text(name, .lowercase);
    const values = args orelse return;
    try self.writer.writeByte('(');
    if (name.eqlAscii("lang")) {
        try self.languages(values);
    } else if (name.eqlAscii("is") or name.eqlAscii("where")) {
        try self.nestedList(values, .{
            .real = true,
            .forgiving = true,
        });
    } else if (name.eqlAscii("has")) {
        try self.nestedList(values, .{
            .real = true,
            .relative = true,
        });
    } else if (name.eqlAscii("not") or
        name.eqlAscii("slotted") or
        name.eqlAscii("host") or
        name.eqlAscii("host-context"))
    {
        try self.nestedList(values, .{ .real = true });
    } else if (name.eqlAscii("nth-child") or name.eqlAscii("nth-last-child")) {
        try self.nth(values, true);
    } else if (name.eqlAscii("nth-of-type") or name.eqlAscii("nth-last-of-type")) {
        try self.nth(values, false);
    } else if (name.eqlAscii("dir") or name.eqlAscii("state") or name.eqlAscii("part")) {
        try self.names(values);
    } else return error.UnsupportedPseudoFunction;
    try self.writer.writeByte(')');
}

fn names(self: SelectorSerializer, values: []const Value) Error!void {
    var input = syntax.ComponentValueStream.init(values);
    input.discardWhitespace();
    while (true) {
        try self.text(input.consumeIdent() orelse return error.InvalidSelector, .identifier);
        input.discardWhitespace();
        if (input.empty()) return;
        try self.writer.writeByte(' ');
    }
}

fn languages(self: SelectorSerializer, values: []const Value) Error!void {
    var input = syntax.ComponentValueStream.init(values);
    while (true) {
        input.discardWhitespace();
        const token = input.peekToken() orelse return error.InvalidSelector;
        try self.text(switch (token.*) {
            .ident, .string => |language| language,
            else => return error.InvalidSelector,
        }, .string);
        input.advance();
        input.discardWhitespace();
        if (input.empty()) return;
        if (!input.isToken(.comma)) return error.InvalidSelector;
        input.advance();
        try self.writer.writeAll(", ");
    }
}

fn nestedList(self: SelectorSerializer, values: []const Value, comptime mode: types.Mode) Error!void {
    var input = syntax.ComponentValueStream.init(values);
    const list = try parsing.parseList(
        self.allocator,
        &input,
        mode,
        .{ .namespaces = self.namespaces },
    ) orelse return error.InvalidSelector;
    defer list.deinit(self.allocator);
    try self.group(list);
}

fn nth(self: SelectorSerializer, values: []const Value, allow_of: bool) Error!void {
    for (values, 0..) |v, i| {
        if (allow_of and v == .preserved_token and v.preserved_token == .ident and v.preserved_token.ident.eqlAscii("of")) {
            try self.formula(values[0..i]);
            try self.writer.writeAll(" of ");
            return self.nestedList(values[i + 1 ..], .{ .real = true });
        }
    }
    try self.formula(values);
}

// https://drafts.csswg.org/css-syntax-3/#serialize-an-a-n-plus-b-value
fn formula(self: SelectorSerializer, values: []const Value) Error!void {
    const tokens = try self.allocator.alloc(Token, values.len);
    defer self.allocator.free(tokens);
    for (values, tokens) |v, *token| {
        if (v != .preserved_token) return error.InvalidSelector;
        token.* = switch (v.preserved_token) {
            .dimension => |d| .{
                .dimension = .{
                    .value = d.value,
                    .unit = d.unit,
                    .type_flag = d.type_flag,
                    .sign = d.sign,
                },
            },
            .number => |n| .{
                .number = .{
                    .value = n.value,
                    .type_flag = n.type_flag,
                    .sign = n.sign,
                },
            },
            inline .ident, .delim, .whitespace => |value, tag| @unionInit(Token, @tagName(tag), value),
            else => return error.InvalidSelector,
        };
    }
    var input = syntax.TokenStream.init(self.allocator, tokens);
    var parser = syntax.Parser.init(self.allocator, &input);
    const n = parser.parseNth() catch return error.InvalidSelector;
    if (n.a == 0) return self.writer.print("{d}", .{n.b});
    switch (n.a) {
        1 => {},
        -1 => try self.writer.writeByte('-'),
        else => try self.writer.print("{d}", .{n.a}),
    }
    try self.writer.writeByte('n');
    if (n.b > 0) try self.writer.writeByte('+');
    if (n.b != 0) try self.writer.print("{d}", .{n.b});
}

test "CSSOM serializes parsed selectors" {
    const allocator = std.testing.allocator;
    var namespaces: ns.Context = .{
        .default_namespace = String.fromSource("html"),
    };
    defer namespaces.deinit(allocator);
    try namespaces.bindings.append(allocator, .{
        .prefix = String.fromSource("h"),
        .name = String.fromSource("html"),
    });
    try namespaces.bindings.append(allocator, .{
        .prefix = String.fromSource("v"),
        .name = String.fromSource("svg"),
    });
    const cases = [_][2][]const u8{
        .{ "h|*.foo>v|rect, *|*#id + |p:before", ".foo > v|rect, *|*#id + |p::before" },
        .{ "[*|foo=bar I][|x][h|n]", "[*|foo=\"bar\" i][x][h|n]" },
        .{ ".\\30 x ~ :not(.foo,#bar)", ".\\30 x ~ :not(.foo, #bar)" },
        .{ ":LANG(fr,'en-US'):nth-child(odd of p,.item)", ":lang(\"fr\", \"en-US\"):nth-child(2n+1 of p, .item)" },
        .{ "div:has(> .item,+p)", "div:has(> .item, + p)" },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        var buffer = try syntax.Buffer.init(allocator, case[0]);
        defer buffer.deinit();
        var tokens = buffer.stream(allocator);
        var parser = syntax.Parser.init(arena.allocator(), &tokens);
        var input = syntax.ComponentValueStream.init(try parser.parseListOfComponentValues());
        const list = (try parseGroup(allocator, &input, .{ .namespaces = &namespaces })).?;
        defer list.deinit(allocator);
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();
        const serializer: SelectorSerializer = .{
            .allocator = allocator,
            .writer = &output.writer,
            .namespaces = &namespaces,
        };
        try serializer.group(list);
        try std.testing.expectEqualStrings(case[1], output.written());
    }
}
