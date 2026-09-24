//! Implementation of CSS Selector's grammar's parser.
//! See https://www.w3.org/TR/selectors-4/#grammar

const std = @import("std");
const Stream = @import("../syntax/ComponentValueStream.zig");
const Parser = @import("Parser.zig");
const types = @import("types.zig");
const SelectorList = types.SelectorList;
const ComplexSelector = types.ComplexSelector;
const Mode = types.Mode;

pub fn parseList(allocator: std.mem.Allocator, input: *Stream, comptime mode: Mode) !?SelectorList {
    return consumeList(allocator, input, mode);
}

pub fn consumeList(allocator: std.mem.Allocator, input: *Stream, comptime mode: Mode) !SelectorList {
    const list: std.ArrayList(ComplexSelector) = .empty;
    defer {
        for (list.items) |selector| selector.deinit(allocator);
        list.deinit(allocator);
    }

    var parser = Parser.init(allocator, input);

    input.discardWhitespace();
    while (true) {
        try parser.consumeSelector(mode);
        list.append(allocator, .{
            .components = try parser.components.toOwnedSlice(allocator),
        });
        if (input.empty()) break;
        _ = input.consume(); // comma
        input.discardWhitespace();
    }

    return .{
        .selectors = list.toOwnedSlice(allocator),
    };
}
