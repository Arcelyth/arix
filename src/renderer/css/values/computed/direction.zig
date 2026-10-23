const Context = @import("Context.zig");
pub const Direction = @import("../specified.zig").Direction;

pub fn fromSpecified(value: Direction, _: *const Context) Direction {
    return value;
}
