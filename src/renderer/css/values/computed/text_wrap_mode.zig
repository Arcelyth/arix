const Context = @import("Context.zig");
pub const TextWrapMode = @import("../specified.zig").TextWrapMode;

pub fn fromSpecified(value: TextWrapMode, _: *const Context) TextWrapMode {
    return value;
}
