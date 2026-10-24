const Context = @import("Context.zig");
pub const UnicodeBidi = @import("../specified.zig").UnicodeBidi;

pub fn fromSpecified(value: UnicodeBidi, _: *const Context) UnicodeBidi {
    return value;
}
