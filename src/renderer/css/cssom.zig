pub const CSS = @import("cssom/CSSRuleList.zig");
pub const CSSRuleList = @import("cssom/CSSRuleList.zig");
pub const CSSStyleSheet = @import("cssom/CSSStyleSheet.zig");
pub const serialize = @import("cssom/serialize.zig");
pub const media = @import("cssom/media.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
