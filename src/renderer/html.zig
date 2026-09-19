pub const sniff_test = @import("html/encoding/sniff_test.zig");
pub const attr = @import("html/encoding/attr.zig");
pub const sniff = @import("html/encoding/sniff.zig");

pub const Tokenizer = @import("html/tokenizer/Tokenizer.zig");
pub const TreeBuilder = @import("html/tree_builder/TreeBuilder.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
