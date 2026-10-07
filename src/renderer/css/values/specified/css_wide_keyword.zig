const std = @import("std");
const String = @import("../../String.zig");

// https://drafts.csswg.org/css-cascade-5/#revert-rule-keyword
pub const CSSWideKeyword = enum {
    initial,
    inherit,
    unset,
    revert,
    revert_layer,
    revert_rule,

    pub fn parse(name: String) ?CSSWideKeyword {
        inline for (std.enums.values(CSSWideKeyword)) |keyword| {
            const spelling = comptime cssName(@tagName(keyword));
            if (name.eqlAscii(&spelling)) return keyword;
        }
        return null;
    }
};

fn cssName(comptime name: []const u8) [name.len]u8 {
    var result: [name.len]u8 = undefined;
    for (name, 0..) |byte, i| result[i] = if (byte == '_') '-' else byte;
    return result;
}
