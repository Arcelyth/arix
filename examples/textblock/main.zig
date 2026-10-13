const std = @import("std");

pub fn main(init: std.process.Init) !void {
    try @import("../render.zig").run(init, .{
        .css_path = "./style.css",
        .output_path = "./target/textblock.ppm",
        .width = 320,
        .height = 300,
    });
}
