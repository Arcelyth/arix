pub const html5lib_tokenizer_test = @import("tests/html/html5lib_tokenizer_test.zig");
pub const html5lib_tree_builder_test = @import("tests/html/html5lib_tree_construction_test.zig");
pub const TestParser = @import("tests/html/TestParser.zig");
pub const css_parsing_tests = @import("tests/css/css_parsing_tests.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
