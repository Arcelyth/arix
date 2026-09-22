const ComponentValueStream = @import("ComponentValueStream.zig");

pub fn ParseFn(comptime T: type) type {
    return struct {
        parse: fn (*ComponentValueStream) ?T,
    };
}

/// Half-open byte offsets into the decoded UTF-8 source.
pub const Span = struct {
    start: u32,
    end: u32,
};
