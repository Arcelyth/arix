pub const CSS = @import("cssom/CSSRuleList.zig");
pub const CSSRuleList = @import("cssom/CSSRuleList.zig");
pub const CSSStyleSheet = @import("cssom/CSSStyleSheet.zig");
pub const MediaList = @import("cssom/MediaList.zig");
pub const serialize = @import("cssom/serialize.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
