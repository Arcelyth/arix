const config = @import("config");

pub const Example = enum { rect };

pub const main = switch (config.example) {
    .rect => @import("rect/main.zig").main,
};
