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

pub fn consumeSelector(self: *Parser, comptime mode: Mode) !void {
    _ = self;
    _ = mode;
}
