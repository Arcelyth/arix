const std = @import("std");
const TokenizerState = @import("state.zig").TokenizerState;
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;
const StraleUtf8 = strale.StraleUtf8;
const t_error = @import("error.zig");
const TokenizerErrorProc = t_error.TokenizerErrorProc;
const TokenizerError = t_error.TokenizerError;
const u8_buffer = @import("utils").u8_buffer;

const Self = @This();
allocator: std.mem.Allocator,
state: TokenizerState,
pause_flag: bool,
at_eof: bool,
current_tag_name: ?StraleUtf8,
temporary_buffer: u8_buffer.U8Buffer(32), 
on_error: ?TokenizerErrorProc,


pub fn init(alloc: std.mem.Allocator, on_error: ?TokenizerErrorProc) Self {
    return Self{
        .allocator = alloc,
        .state = .Data,
        .pause_flag = false,
        .at_eof = false,
        .current_tag_name = null,
        .temporary_buffer = u8_buffer.U8Buffer(32){},
        .on_error = on_error,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn emitEof(self: *Self) void {
    _ = self;
}

pub fn emitChar(self: *Self, ch: u21) void {
    _ = self;
    _ = ch;
}

pub inline fn setStateAndAdvance(self: *Self, state: TokenizerState, input: *BufferDeque(.utf8, .not_atomic)) void {
    self.state = state;
    _ = input.nextChar();
}

pub fn createComment(self: *Self) void {
    _ = self; 
}

pub fn reconsume(self: *Self) void {
    _ = self; 
}

pub fn step(self: *Self, input: *BufferDeque(.utf8, .not_atomic)) void {
    var ch: u21 = undefined;
    while (true) {
        const is_eof = if (input.peekChar()) |c| blk:{
            ch = c;
            break :blk false;
        } else true;

        switch (self.state) {
            
            // https://html.spec.whatwg.org/multipage/parsing.html#data-state
            .Data => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '&' => self.setStateAndAdvance(.CharacterReferenceInData, input),
                    '<' => self.setStateAndAdvance(.TagOpen, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                    },
                    else => self.emitChar(ch),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-state
            .RCDATA => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }

                switch (ch) {
                    '&' => self.setStateAndAdvance(.CharacterReferenceInRCDATA, input),
                    '<' => self.setStateAndAdvance(.RCDATALessThanSign, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                    },
                    else => self.emitChar(ch),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-state
            .RAWTEXT => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }

                switch (ch) {
                    '<' => self.setStateAndAdvance(.RAWTEXTLessThanSign, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                    },
                    else => self.emitChar(ch),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-state
            .ScriptData => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }

                switch (ch) {
                    '<' => self.setStateAndAdvance(.ScriptDataLessThanSign, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                    },
                    else => self.emitChar(ch),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#plaintext-state
            .PLAINTEXT => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }

                switch (ch) {
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                    },
                    else => self.emitChar(ch),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-open-state
            .TagOpen => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofBeforeTagName, ch);
                    self.emitChar('<');
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '!' => self.setStateAndAdvance(.MarkupDeclarationOpen, input),
                    '/' => self.setStateAndAdvance(.EndTagOpen, input),
                    '?' => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedQuestionMarkInsteadOfTagName, ch);
                        self.create_comment();
                        self.state = .BogusComment;
//                        reconsume();
                    },
                    else => {
// TODO
                    }
                }
            },

            else => {},
        }

        _ = input.nextChar();
    }

    self.emitEof();
}

pub fn create_comment(self: *Self) void {
    _ = self;
}
