pub const sniff_test = @import("renderer/html/encoding/sniff_test.zig");
pub const attr_test = @import("renderer/html/encoding/attr_test.zig");
pub const attr = @import("renderer/html/encoding/attr.zig");
pub const encoding = @import("renderer/html/encoding/encoding.zig");
pub const sniff = @import("renderer/html/encoding/sniff.zig");

// HTML
pub const Tokenizer = @import("renderer/html/tokenizer/Tokenizer.zig");
pub const TreeBuilder = @import("renderer/html/tree_builder/TreeBuilder.zig");

// tests
pub const html5lib_tokenizer_test = @import("renderer/tests/html/html5lib_tokenizer_test.zig");
pub const html5lib_tree_builder_test = @import("renderer/tests/html/html5lib_tree_construction_test.zig");
pub const TestParser = @import("renderer/tests/html/TestParser.zig");

// CSS
pub const decode = @import("renderer/css/decode.zig");
pub const InputStream = @import("renderer/css/InputStream.zig");
pub const CSSTokenizer = @import("renderer/css/Tokenizer.zig");
pub const TokenStream = @import("renderer/css/TokenStream.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
