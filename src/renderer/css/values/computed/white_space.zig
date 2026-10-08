const Context = @import("Context.zig");
pub const WhiteSpace = @import("../specified.zig").WhiteSpace;

pub fn fromSpecified(value: WhiteSpace, _: *const Context) WhiteSpace {
    return value;
}
