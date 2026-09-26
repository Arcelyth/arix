const ComponentValue = @import("parsing_results.zig").ComponentValue;

// https://www.w3.org/TR/css-syntax-3/#typedef-declaration-value
pub fn parseDeclarationValue(values: []const ComponentValue) bool {
    return matchValue(values, true);
}

// https://www.w3.org/TR/css-syntax-3/#typedef-any-value
pub fn parseAnyValue(values: []const ComponentValue) bool {
    return matchValue(values, false);
}

fn matchValue(values: []const ComponentValue, comptime declaration: bool) bool {
    if (values.len == 0) return false;
    for (values) |*value| switch (value.*) {
        .preserved_token => |tk| switch (tk) {
            .bad_string, .bad_url, .right_paren, .right_bracket, .right_brace => return false,
            .semicolon => if (declaration) return false,
            .delim => |cp| if (declaration and cp == '!') return false,
            else => {},
        },
        inline .simple_block, .function => |nested| {
            if (nested.value.len != 0 and !parseAnyValue(nested.value)) return false;
        },
    };
    return true;
}
