const Tokenizer = @This();

const std = @import("std");
const Preprocessor = @import("Preprocessor.zig");

allocator: std.mem.Allocator,
steam: Preprocessor,

pub fn init(alloc: std.mem.Allocator, input_stream: []const u8) Tokenizer {
    return .{
        .allocator = alloc,
        .stream = Preprocessor.init(input_stream),
    }; 
}



