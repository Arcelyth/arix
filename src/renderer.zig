pub const sniff_test = @import("renderer/html/encoding/sniff_test.zig");
pub const attr_test = @import("renderer/html/encoding/attr_test.zig");
pub const attr = @import("renderer/html/encoding/attr.zig");
pub const encoding = @import("renderer/html/encoding/encoding.zig");
pub const sniff = @import("renderer/html/encoding/sniff.zig");

pub const Tokenizer = @import("renderer/html/tokenizer/Tokenizer.zig");
pub const html5lib_tokenizer_test = @import("renderer/tests/html5lib_tokenizer_test.zig");
pub const TreeBuilder = @import("renderer/html/tree_builder/TreeBuilder.zig");
pub const tree_builder_test = @import("renderer/html/tree_builder/tree_builder_test.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
