const std = @import("std");
const Token = @import("../tokenizer/token.zig").Token;
const types = @import("types.zig");
const InsertionMode = types.InsertionMode;

pub const TreeBuilderError = union(enum) {
    unexpected: struct { tk: Token, mode: InsertionMode },

    pub fn format(self: TreeBuilderError, writer: anytype) !void {
        switch (self) {
            .unexpected => |info| {
                try writer.print(
                    "Unexpected token: {f} in insertion mode: {s}.",
                    .{ info.tk, @tagName(info.mode) },
                );
            },
        }
    }
};
