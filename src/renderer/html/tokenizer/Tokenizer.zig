const std = @import("std");
const TokenizerState = @import("state.zig").TokenizerState;
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;
const StraleUtf8Global = strale.StraleUtf8Global;
const t_error = @import("error.zig");
const TokenizerErrorProc = t_error.TokenizerErrorProc;
const TokenizerError = t_error.TokenizerError;
const u8_buffer = @import("../../utils/u8_buffer.zig");
const ascii = @import("../../utils/ascii.zig");
const token = @import("token.zig");

const Self = @This();
allocator: std.mem.Allocator,
state: TokenizerState,
pause_flag: bool,
at_eof: bool,

current_tag_name: StraleUtf8Global,
current_tag_kind: token.TagKind,
current_tag_self_closing: bool,

current_comment: StraleUtf8Global,

current_attribute_name: StraleUtf8Global,
current_attribute_value: StraleUtf8Global,

current_doctype: token.Doctype,

temporary_buffer: StraleUtf8Global,
on_error: ?TokenizerErrorProc,

pub fn init(alloc: std.mem.Allocator, on_error: ?TokenizerErrorProc) Self {
    return Self{
        .allocator = alloc,
        .state = .Data,
        .pause_flag = false,
        .at_eof = false,
        .current_tag_name = StraleUtf8Global.initEmpty(),
        .current_tag_kind = .StartTag,
        .current_tag_self_closing = false,
        .current_comment = StraleUtf8Global.initEmpty(),
        .current_attribute_name = StraleUtf8Global.initEmpty(),
        .current_attribute_value = StraleUtf8Global.initEmpty(),
        .current_doctype = token.Doctype.init(),
        .temporary_buffer = StraleUtf8Global.initEmpty(),
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

pub fn emitCurrentTag(self: *Self) void {
    _ = self;
}

pub fn discardTag(self: *Self) void {
    self.current_tag_name.clear();
    self.current_tag_self_closing = false;
}

pub fn createTag_E(self: *Self, tag_kind: token.TagKind, ch: u21) !void {
    self.discardTag();
    self.current_tag_kind = tag_kind;
    try self.current_tag_name.push(ch);
}

pub inline fn setStateAndAdvance(self: *Self, state: TokenizerState, input: *BufferDeque(.utf8, .not_atomic, false)) void {
    self.state = state;
    _ = input.nextChar();
}

pub inline fn emitCharAndNext(self: *Self, ch: u21, input: *BufferDeque(.utf8, .not_atomic, false)) void {
    self.emitChar(ch);
    _ = input.nextChar();
}

pub fn createComment(self: *Self) void {
    _ = self;
}

pub fn step_E(self: *Self, input: *BufferDeque(.utf8, .not_atomic, false)) !void {
    var ch: u21 = undefined;
    while (true) {
        const is_eof = if (input.peekChar()) |c| blk: {
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
                        self.emitCharAndNext('\u{FFFD}', input);
                    },
                    else => self.emitCharAndNext(ch, input),
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
                        self.emitCharAndNext('\u{FFFD}', input);
                    },
                    else => self.emitCharAndNext(ch, input),
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
                        self.emitCharAndNext('\u{FFFD}', input);
                    },
                    else => self.emitCharAndNext(ch, input),
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
                        self.emitCharAndNext('\u{FFFD}', input);
                    },
                    else => self.emitCharAndNext(ch, input),
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
                        self.emitCharAndNext('\u{FFFD}', input);
                    },
                    else => self.emitCharAndNext(ch, input),
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
                        self.current_comment.clear();
                        // Since reconsume, no advance here.
                        self.state = .BogusComment;
                    },
                    else => {
                        if (ascii.isAsciiAlpha(ch)) {
                            try self.createTag_E(.StartTag, ch);
                            // Since already pushed current char into tag_name, use advance instead of reconsume.
                            self.setStateAndAdvance(.TagName, input);
                        } else {
                            if (self.on_error) |err_cb| err_cb(.InvalidFirstCharacterOfTagName, ch);
                            self.emitChar('<');
                            self.state = .Data;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#end-tag-open-state
            .EndTagOpen => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofBeforeTagName, ch);
                    self.emitChar('<');
                    self.emitChar('/');
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.MissingEndTagName, ch);
                        self.state = .Data;
                    },
                    else => {
                        if (ascii.isAsciiAlpha(ch)) {
                            try self.createTag_E(.EndTag, ch);
                            self.setStateAndAdvance(.TagName, input);
                        } else {
                            if (self.on_error) |err_cb| err_cb(.InvalidFirstCharacterOfTagName, ch);
                            self.current_comment.clear();
                            self.state = .BogusComment;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-name-state
            .TagName => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInTag, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeAttributeName, input),
                    '/' => self.setStateAndAdvance(.SelfClosingStartTag, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentTag();
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_tag_name.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        if (ascii.isAsciiUpperAlpha(ch))
                            try self.current_tag_name.push(ch + 0x0020)
                        else
                            try self.current_tag_name.push(ch);
                        _ = input.nextChar();
                    },
                }
            },
            else => {
                break;
            },
        }
    }
}

pub fn create_comment(self: *Self) void {
    _ = self;
}
