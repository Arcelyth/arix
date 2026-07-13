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

last_start_tag_name: ?StraleUtf8Global,
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
        .last_start_tag_name = null,
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

pub fn emitTempBuffer(self: *Self) void {
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

pub fn isAppropriateEndTag(self: *const Self) bool {
    return if (self.last_start_tag_name) |*name| blk: {
        break :blk self.current_tag_kind == .EndTag and self.current_tag_name.cmp(name);
    } else false;
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

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-less-than-sign-state
            .RCDATALessThanSign => {
                switch (ch) {
                    '/' => {
                        self.temporary_buffer.clear();
                        self.setStateAndAdvance(.RCDATAEndTagName, input);
                    },
                    else => {
                        self.emitChar('<');
                        self.state = .RCDATA;
                    },
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-open-state
            .RCDATAEndTagOpen => {
                if (ascii.isAsciiAlpha(ch)) {
                    try self.createTag_E(.EndTag, ch);
                    self.setStateAndAdvance(.RCDATAEndTagName, input);
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.state = .RCDATA;
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-name-state
            .RCDATAEndTagName => blk: {
                if (self.isAppropriateEndTag()) {
                    switch (ch) {
                        '\t', '\n', '\x0C', ' ' => {
                            self.setStateAndAdvance(.BeforeAttributeName, input);
                            break :blk;
                        },
                        '/' => {
                            self.setStateAndAdvance(.SelfClosingStartTag, input);
                            break :blk;
                        },
                        '>' => {
                            self.setStateAndAdvance(.Data, input);
                            self.emitCurrentTag();
                            break :blk;
                        },
                        else => {},
                    }
                }
                if (ascii.isAsciiUpperAlpha(ch)) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else if (ascii.isAsciiLowerAlpha(ch)) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.emitTempBuffer();
                    self.state = .RCDATA;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-less-than-sign-state
            .RAWTEXTLessThanSign => {
                switch (ch) {
                    '/' => {
                        self.temporary_buffer.clear();
                        self.setStateAndAdvance(.RAWTEXTEndTagOpen, input);
                    },
                    else => {
                        self.emitChar('<');
                        self.state = .RAWTEXT;
                    },
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-end-tag-open-state
            .RAWTEXTEndTagOpen => {
                if (ascii.isAsciiAlpha(ch)) {
                    try self.createTag_E(.EndTag, ch);
                    self.setStateAndAdvance(.RAWTEXTEndTagName, input);
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.state = .RAWTEXT;
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-end-tag-name-state
            .RAWTEXTEndTagName => blk: {
                if (self.isAppropriateEndTag()) {
                    switch (ch) {
                        '\t', '\n', '\x0C', ' ' => {
                            self.setStateAndAdvance(.BeforeAttributeName, input);
                            break :blk;
                        },

                        '/' => {
                            self.setStateAndAdvance(.SelfClosingStartTag, input);
                            break :blk;
                        },
                        '>' => {
                            self.setStateAndAdvance(.Data, input);
                            self.emitCurrentTag();
                            break :blk;
                        },
                        else => {},
                    }
                }
                if (ascii.isAsciiUpperAlpha(ch)) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else if (ascii.isAsciiLowerAlpha(ch)) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.emitTempBuffer();
                    self.state = .RAWTEXT;
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-less-than-sign-state
            .ScriptDataLessThanSign => {
                switch (ch) {
                    '/' => {
                        self.temporary_buffer.clear();
                        self.setStateAndAdvance(.ScriptDataEndTagOpen, input);
                    },
                    '!' => {
                        self.setStateAndAdvance(.ScriptDataEscapeStart, input);
                        self.emitChar('<');
                        self.emitChar('!');
                    },
                    else => {
                        self.emitChar('<');
                        self.state = .ScriptData;
                    },
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-end-tag-open-state
            .ScriptDataEndTagOpen => {
                if (ascii.isAsciiAlpha(ch)) {
                    try self.createTag_E(.EndTag, ch);
                    self.setStateAndAdvance(.ScriptDataEndTagName, input);
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.state = .ScriptData;
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-end-tag-name-state
            .ScriptDataEndTagName => blk: {
                if (self.isAppropriateEndTag()) {
                    switch (ch) {
                        '\t', '\n', '\x0C', ' ' => {
                            self.setStateAndAdvance(.BeforeAttributeName, input);
                            break :blk;
                        },
                        '/' => {
                            self.setStateAndAdvance(.SelfClosingStartTag, input);
                            break :blk;
                        },
                        '>' => {
                            self.setStateAndAdvance(.Data, input);
                            self.emitCurrentTag();
                            break :blk;
                        },
                        else => {},
                    }
                }
                if (ascii.isAsciiUpperAlpha(ch)) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else if (ascii.isAsciiLowerAlpha(ch)) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.emitTempBuffer();
                    self.state = .ScriptData;
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escape-start-state
            .ScriptDataEscapeStart => {
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataEscapeStartDash, input);
                        self.emitChar('-');
                    },
                    else => self.state = .ScriptData,
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escape-start-dash-state
            .ScriptDataEscapeStartDash => {
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataEscapedDashDash, input);
                        self.emitChar('-');
                    },
                    else => self.state = .ScriptData,
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-state
            .ScriptDataEscaped => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInScriptHtmlCommentLikeText, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataEscapedDash, input);
                        self.emitChar('-');
                    },
                    '<' => self.setStateAndAdvance(.ScriptDataEscapedLessThanSign, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        self.emitChar(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-state
            .ScriptDataEscapedDash => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInScriptHtmlCommentLikeText, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataEscapedDashDash, input);
                        self.emitChar('-');
                    },
                    '<' => self.setStateAndAdvance(.ScriptDataEscapedLessThanSign, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.setStateAndAdvance(.ScriptDataEscaped, input);
                        self.emitChar('\u{FFFD}');
                    },
                    else => {
                        self.setStateAndAdvance(.ScriptDataEscaped, input);
                        self.emitChar(ch);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-dash-state
            .ScriptDataEscapedDashDash => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInScriptHtmlCommentLikeText, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.emitChar('-');
                        _ = input.nextChar();
                    },
                    '<' => self.setStateAndAdvance(.ScriptDataEscapedLessThanSign, input),
                    '>' => {
                        self.setStateAndAdvance(.ScriptData, input);
                        self.emitChar('>');
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.setStateAndAdvance(.ScriptDataEscaped, input);
                        self.emitChar('\u{FFFD}');
                    },
                    else => {
                        self.setStateAndAdvance(.ScriptDataEscaped, input);
                        self.emitChar(ch);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-less-than-sign-state
            .ScriptDataEscapedLessThanSign => {
                if (is_eof) {
                    self.emitChar('<');
                    self.state = .ScriptDataEscaped;
                    return;
                }
                switch (ch) {
                    '/' => {
                        self.temporary_buffer.clear();
                        self.setStateAndAdvance(.ScriptDataEscapedEndTagOpen, input);
                    },
                    else => {
                        if (ascii.isAsciiAlpha(ch)) {
                            self.temporary_buffer.clear();
                            self.emitChar('<');
                            self.state = .ScriptDataDoubleEscapeStart;
                        } else {
                            self.emitChar('<');
                            self.state = .ScriptDataEscaped;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-end-tag-open-state
            .ScriptDataEscapedEndTagOpen => {
                if (ascii.isAsciiAlpha(ch)) {
                    try self.createTag_E(.EndTag, ch);
                    self.setStateAndAdvance(.ScriptDataEscapedEndTagName, input);
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.state = .ScriptDataEscaped;
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-end-tag-name-state
            .ScriptDataEscapedEndTagName => blk: {
                if (self.isAppropriateEndTag()) {
                    switch (ch) {
                        '\t', '\n', '\x0C', ' ' => {
                            self.setStateAndAdvance(.BeforeAttributeName, input);
                            break :blk;
                        },
                        '/' => {
                            self.setStateAndAdvance(.SelfClosingStartTag, input);
                            break :blk;
                        },
                        '>' => {
                            self.setStateAndAdvance(.Data, input);
                            self.emitCurrentTag();
                            break :blk;
                        },
                        else => {},
                    }
                }
                if (ascii.isAsciiUpperAlpha(ch)) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else if (ascii.isAsciiLowerAlpha(ch)) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    _ = input.nextChar();
                } else {
                    self.emitChar('<');
                    self.emitChar('/');
                    self.emitTempBuffer();
                    self.state = .ScriptDataEscaped;
                }

                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escape-start-state
            .ScriptDataDoubleEscapeStart => {
                switch (ch) {
                    '\t', '\n', '\x0C', ' ', '/', '>' => {
                        if (std.mem.eql(u8, self.temporary_buffer.slice(), "script")) self.setStateAndAdvance(.ScriptDataDoubleEscaped, input) else self.setStateAndAdvance(.ScriptDataEscaped, input);
                        self.emitChar(ch);
                    },
                    else => {
                        if (ascii.isAsciiUpperAlpha(ch)) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            _ = input.nextChar();
                        } else if (ascii.isAsciiLowerAlpha(ch)) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            _ = input.nextChar();
                        } else {
                            self.state = .ScriptDataDoubleEscaped;
                        }
                    },
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-state
            .ScriptDataDoubleEscaped => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInScriptHtmlCommentLikeText, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataEscapedDash, input);
                        self.emitChar('-');
                    },
                    '<' => {
                        self.setStateAndAdvance(.ScriptDataEscapedLessThanSign, input);
                        self.emitChar('<');
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitChar('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        self.emitChar(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-state
            .ScriptDataDoubleEscapedDash => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInScriptHtmlCommentLikeText, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscapedDashDash, input);
                        self.emitChar('-');
                    },
                    '<' => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscapedLessThanSign, input);
                        self.emitChar('<');
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.setStateAndAdvance(.ScriptDataDoubleEscaped, input);
                        self.emitChar('\u{FFFD}');
                    },
                    else => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscaped, input);
                        self.emitChar(ch);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-dash-state
            .ScriptDataDoubleEscapedDashDash => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInScriptHtmlCommentLikeText, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.emitChar('-');
                        _ = input.nextChar();
                    },
                    '<' => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscapedLessThanSign, input);
                        self.emitChar('<');
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.setStateAndAdvance(.ScriptDataDoubleEscaped, input);
                        self.emitChar('\u{FFFD}');
                    },
                    else => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscaped, input);
                        self.emitChar(ch);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-less-than-sign-state
            .ScriptDataDoubleEscapedLessThanSign => {
                switch (ch) {
                    '/' => {
                        self.temporary_buffer.clear();
                        self.setStateAndAdvance(.ScriptDataDoubleEscapeEnd, input);
                        self.emitChar('/');
                    },
                    else => {
                        self.state = .ScriptDataDoubleEscaped;
                    },
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escape-end-state
            .ScriptDataDoubleEscapeEnd => {
                switch (ch) {
                    '\t', '\n', '\x0C', ' ', '/', '>' => {
                        if (std.mem.eql(u8, self.temporary_buffer.slice(), "script")) self.setStateAndAdvance(.ScriptDataEscaped, input) else self.setStateAndAdvance(.ScriptDataDoubleEscaped, input);
                        self.emitChar(ch);
                    },
                    else => {
                        if (ascii.isAsciiUpperAlpha(ch)) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            _ = input.nextChar();
                        } else if (ascii.isAsciiLowerAlpha(ch)) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            _ = input.nextChar();
                        } else {
                            self.state = .ScriptDataDoubleEscaped;
                        }
                    },
                }
                if (is_eof) return;
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
            .BeforeAttributeName => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
            .AttributeName => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-name-state
            .AfterAttributeName => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
            .BeforeAttributeValue => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-double-quoted-state
            .AttributeValueDoubleQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-single-quoted-state
            .AttributeValueSingleQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-unquoted-state
            .AttributeValueUnquoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-value-quoted-state
            .AfterAttributeValueQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#self-closing-start-tag-state
            .SelfClosingStartTag => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-comment-state
            .BogusComment => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#markup-declaration-open-state
            .MarkupDeclarationOpen => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-state
            .CommentStart => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-dash-state
            .CommentStartDash => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-state
            .Comment => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-state
            .CommentLessThanSign => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-state
            .CommentLessThanSignBang => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-state
            .CommentLessThanSignBangDash => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-dash-state
            .CommentLessThanSignBangDashDash => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-dash-state
            .CommentEndDash => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-state
            .CommentEnd => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-bang-state
            .CommentEndBang => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-state
            .DOCTYPE => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-name-state
            .BeforeDOCTYPEName => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-name-state
            .DOCTYPEName => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-name-state
            .AfterDOCTYPEName => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-keyword-state
            .AfterDOCTYPEPublicKeyword => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-public-identifier-state
            .BeforeDOCTYPEPublicIdentifier => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(double-quoted)-state
            .DOCTYPEPublicIdentifierDoubleQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(single-quoted)-state
            .DOCTYPEPublicIdentifierSingleQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-identifier-state
            .AfterDOCTYPEPublicIdentifier => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#between-doctype-public-and-system-identifiers-state
            .BetweenDOCTYPEPublicAndSystemIdentifiers => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-keyword-state
            .AfterDOCTYPESystemKeyword => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-system-identifier-state
            .BeforeDOCTYPESystemIdentifier => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            .DOCTYPESystemIdentifierDoubleQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(single-quoted)-state
            .DOCTYPESystemIdentifierSingleQuoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-identifier-state
            .AfterDOCTYPESystemIdentifier => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-doctype-state
            .BogusDOCTYPE => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-state
            .CDATASection => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-bracket-state
            .CDATASectionBracket => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-end-state
            .CDATASectionEnd => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#character-reference-state
            .CharacterReferenceInData => {},

            .CharacterReferenceInRCDATA => {},

            .CharacterReferenceInAttributeValueSingleQuoted => {},

            .CharacterReferenceInAttributeValueDoubleQuoted => {},

            .CharacterReferenceInAttributeValueUnquoted => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
            .NamedCharacterReference => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#ambiguous-ampersand-state
            .AmbiguousAmpersand => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-state
            .NumericCharacterReference => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-start-state
            .HexadecimalCharacterReferenceStart => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-start-state
            .DecimalCharacterReferenceStart => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-state
            .HexadecimalCharacterReference => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-state
            .DecimalCharacterReference => {},

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
            .NumericCharacterReferenceEnd => {},
        }
    }
}
