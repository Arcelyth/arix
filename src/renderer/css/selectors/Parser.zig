const Parser = @This();

const std = @import("std");
const Stream = @import("../syntax/ComponentValueStream.zig");
const parsing_results = @import("../syntax/parsing_results.zig");
const ComponentValue = parsing_results.ComponentValue;
const PreservedToken = parsing_results.PreservedToken;
const types = @import("types.zig");
const String = @import("../String.zig");
const SelectorList = types.SelectorList;
const ComplexSelector = types.ComplexSelector;
const Mode = types.Mode;
const Component = types.ComplexSelector.Component;
const Combinator = types.Combinator;
const SimpleSelector = types.SimpleSelector;

allocator: std.mem.Allocator,
input: *Stream,
components: std.ArrayList(Component) = .empty,

pub fn init(allocator: std.mem.Allocator, input: *Stream) Parser {
    return .{
        .allocator = allocator,
        .input = input,
    };
}

pub fn deinit(self: *Parser) void {
    self.components.deinit(self.allocator);
}

pub fn append(self: *Parser, component: Component) !void {
    try self.components.append(self.allocator, component);
}

pub fn consumeSelector(self: *Parser, comptime mode: Mode) !void {
    while (true) {
        try self.consumeUnit(mode);
        const end = self.input.index;
        self.input.discardWhitespace();

        if (mode.kind != .complex or self.input.empty() or isToken(self.input, .comma)) return;
        const cb: Combinator = self.consumeCombinator() orelse blk: {
            // Check if index change.
            if (self.input.index == end) return error.InvalidSelector;
            break :blk .descendant;
        };
        try self.append(.{ .combinator = cb });
        self.input.discardWhitespace();
    }
}

pub fn consumeUnit(self: *Parser, comptime mode: Mode) void {
    const start = self.components.items.len;
    if (try self.consumeType()) |selector| {
        try self.append(.{ .simple = selector });
        if (mode.kind == .simple) return;
    }

    var after_pseudo = false;
    while (!self.input.empty()) {
        if (self.isToken(.colon)) {
            const pseudo = try self.consumePseudo();
            if (pseudo == .pseudo_element) {
                if (mode.real) return error.InvalidSelector;
                after_pseudo = true;
            }
            try self.append(pseudo);
        } else {
            if (after_pseudo) break;
            const selector = try self.consumeSubclass() orelse break;
            try self.append(.{ .simple = selector });
        }
        if (mode.kind == .simple) return;
    }
    // At least one component is required.
    if (self.components.items.len == start) return error.InvalidSelector;
}

// https://www.w3.org/TR/selectors-4/#typedef-combinator
pub fn consumeCombinator(self: *Parser) ?Combinator {
    const tk = self.peekToken() orelse return null;
    if (tk.* != .delim) return null;
    const cb: Combinator = switch (tk.delim) {
        '>' => .child,
        '+' => .next_sibling,
        '~' => .subsequent_sibling,
        '|' => blk: {
            if (!self.isDelimAt(1, '|')) return null;
            self.advance();
            break :blk .column;
        },
        else => return null,
    };
    self.advance();
    return cb;
}

pub fn consumeType(self: *Parser) !SimpleSelector {
    _ = self;
    @panic("TODO");
}

pub fn consumePseudo(self: *Parser) !Component {
    _ = self;
    @panic("TODO");
}

pub fn consumeSubclass(self: *Parser) !SimpleSelector {
    _ = self;
    @panic("TODO");
}

fn peekToken(self: *const Parser) ?*const PreservedToken {
    const value = self.input.peek() orelse return null;
    return if (value.* == .preserved_token) &value.preserved_token else null;
}

inline fn isDelimAt(self: *const Parser, offset: usize, cp: u21) bool {
    return self.input.isDelimAt(offset, cp);
}

inline fn advance(self: *Parser) void {
    self.input.advance();
}

inline fn isToken(self: *const Parser, comptime tag: std.meta.Tag(PreservedToken)) bool {
    const tk = peekToken(self.input) orelse return false;
    return tk.* == tag;
}
