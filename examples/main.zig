const config = @import("config");

pub const Example = enum { textblock, page };

pub const main = switch (config.example) {
    .textblock => @import("textblock/main.zig").main,
    .page => @import("page/main.zig").main,
};
