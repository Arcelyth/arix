const Stream = @import("../../syntax/ComponentValueStream.zig");
const String = @import("../../String.zig");
const CSSWideKeyword = @import("css_wide_keyword.zig").CSSWideKeyword;

/// https://www.w3.org/TR/css-values-4/#custom-idents
pub fn parse(input: *Stream) ?String {
    const token = input.peekToken() orelse return null;
    if (token.* != .ident) return null;
    if (CSSWideKeyword.parse(token.ident) != null) return null;
    if (token.ident.eqlAscii("default")) return null;
    input.advance();
    return token.ident;
}
