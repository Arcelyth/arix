const std = @import("std");
const TokenizerState = @import("state.zig");
const strale = @import("strale.zig");
const BufferDeque = strale.BufferDeque;
const StraleUtf8 = strale.StraleUtf8;
const t_error = @import("error.zig");
const TokenizerErrorProc = t_error.TokenizerErrorProc;
const TokenizerError = t_error.TokenizerError;

const Self = @This();
allocator: std.mem.Allocator,
state: TokenizerState,
return_state: TokenizerState,
pause_flag: bool,
at_eof: bool,
current_tag_name: ?StraleUtf8,


pub fn init(alloc: std.mem.Allocator) Self {
    return Self{
        .allocator = alloc,
        .state = .Data,
        .return_state = .Data,
        .pause_flag = false,
        .at_eof = false,
        .current_tag_name = null,
        .on_error = ?TokenizerErrorProc,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn emitEof(self: *Self) void {
    _ = self;
}

pub fn emitChar(self: *Self) void {
    _ = self;
}

pub fn step(self: *Self, input: BufferDeque(.utf8, .not_atomic)) void {
    var ch = undefined;
    const is_eof = if (input.peek()) |c| blk: {
        ch = c;
        break :blk false;
    } else true;

    blk: while (true) {
        switch (self.state) {
            .Data => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '&' => {
                        self.return_state = .Data;
                        self.state = .CharacterReference;
                        continue :blk;
                    },
                    '<' => {
                        self.state = .TagOpen;
                        continue :blk;
                    },
                    0x0000 => {
                        if (self.on_error != null) self.on_error(.UnexpectedNullCharacter, ch);
                        emitChar(ch);
                    }
                }
            },
            else => {}
        }
    }
}
