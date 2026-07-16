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
const TokenIngester = @import("TokenIngester.zig");
const named_char_refs = @import("named_char_refs_gen.zig").named_char_refs;

const Tokenizer = @This();
allocator: std.mem.Allocator,
state: TokenizerState,
return_state: TokenizerState,
pause_flag: bool,
at_eof: bool,
// character reference code
char_ref_code: u21,

current_tag_name: StraleUtf8Global,
current_tag_kind: token.TagKind,
current_tag_self_closing: bool,

current_comment: StraleUtf8Global,

current_attribute_name: StraleUtf8Global,
current_attribute_value: StraleUtf8Global,
// Current tag's attributes.
current_tag_attrs: std.ArrayList(token.Attribute),

current_doctype: token.Doctype,

// Current processing instruction.
current_process_inst: token.ProcessingInstruction,

ingester: TokenIngester,
last_start_tag_name: ?StraleUtf8Global,
temporary_buffer: StraleUtf8Global,
on_error: ?TokenizerErrorProc,

pub fn init(alloc: std.mem.Allocator, ingester: TokenIngester, on_error: ?TokenizerErrorProc) Tokenizer {
    //  TOOD: enable global allocator
    //    strale.setGlobalAlloc(alloc);
    return Tokenizer{
        .allocator = alloc,
        .state = .Data,
        .return_state = .Data,
        .pause_flag = false,
        .at_eof = false,
        .char_ref_code = 0,
        .current_tag_name = StraleUtf8Global.initEmpty(),
        .current_tag_kind = .StartTag,
        .current_tag_self_closing = false,
        .current_comment = StraleUtf8Global.initEmpty(),
        .current_attribute_name = StraleUtf8Global.initEmpty(),
        .current_attribute_value = StraleUtf8Global.initEmpty(),
        .current_tag_attrs = .empty,
        .current_doctype = token.Doctype.init(),
        .current_process_inst = token.ProcessingInstruction.init(),
        .ingester = ingester,
        .last_start_tag_name = null,
        .temporary_buffer = StraleUtf8Global.initEmpty(),
        .on_error = on_error,
    };
}

pub fn deinit(self: *Tokenizer) void {
    _ = self;
}

pub fn handle_token(self: *Tokenizer, t: token.Token) void {
    self.ingester.handle_token(t);
}

pub fn emitEof(self: *Tokenizer) void {
    self.handle_token(.EofToken);
}

pub fn emitChar(self: *Tokenizer, ch: u21) void {
    self.handle_token(token.Token{ .CharacterToken = StraleUtf8Global.initChar(ch) catch return });
}

pub fn emitCurrentTag(self: *Tokenizer) void {
    switch (self.current_tag_kind) {
        .StartTag => {
            self.last_start_tag_name = self.current_tag_name.clone();
        },
        .EndTag => {
            // TODO.
        },
    }
    const tag_token = token.Tag{
        .kind = self.current_tag_kind,
        .name = self.current_tag_name.clone(),
        .self_closing = self.current_tag_self_closing,
        .attrs = self.current_tag_attrs,
    };
    self.current_tag_attrs = .empty;
    self.handle_token(token.Token{ .TagToken = tag_token });
}

pub fn emitTempBuffer(self: *Tokenizer) void {
    self.handle_token(token.Token{ .CharacterToken = self.temporary_buffer.clone() });
    self.temporary_buffer.clear();
}

pub fn emitCurrentComment(self: *Tokenizer) void {
    self.handle_token(token.Token{ .CommentToken = self.current_comment.clone() });
    self.current_comment.clear();
}

pub fn emitCurrentDoctype(self: *Tokenizer) void {
    self.handle_token(token.Token{ .DoctypeToken = self.current_doctype });
    self.current_doctype = token.Doctype.init();
}

pub fn discardTag(self: *Tokenizer) void {
    self.current_tag_name.clear();
    self.current_tag_self_closing = false;
}

pub fn createTag_E(self: *Tokenizer, tag_kind: token.TagKind, ch: u21) !void {
    self.discardTag();
    self.current_tag_kind = tag_kind;
    try self.current_tag_name.push(ch);
}

pub fn createAttr_E(self: *Tokenizer, ch: u21) !void {
    _ = self;
    _ = ch;
}

pub inline fn setStateAndAdvance(self: *Tokenizer, state: TokenizerState, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.state = state;
    _ = input.nextChar();
}

pub inline fn setCharacterReferenceStateAndAdvance(self: *Tokenizer, return_state: TokenizerState, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.state = .CharacterReference;
    self.return_state = return_state;
    _ = input.nextChar();
}

pub inline fn emitCharAndAdvance(self: *Tokenizer, ch: u21, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.emitChar(ch);
    _ = input.nextChar();
}

pub inline fn emitProcessingInst(self: *Tokenizer) void {
    self.handle_token(token.Token{ .ProcessingInstructionToken = self.current_process_inst });
}

pub fn match_insensitive(input: *BufferDeque(.utf8, .not_atomic, true), str: []const u8) bool {
    // TODO.
    _ = input;
    _ = str;
    return true;
}

pub fn createComment(self: *Tokenizer) void {
    _ = self;
}

pub inline fn createDoctype(self: *Tokenizer) void {
    self.current_doctype.deinit();
    self.current_doctype = token.Doctype.init();
}

pub fn isAppropriateEndTag(self: *const Tokenizer) bool {
    return if (self.last_start_tag_name) |*name| blk: {
        break :blk self.current_tag_kind == .EndTag and self.current_tag_name.cmp(name);
    } else false;
}

pub fn step_E(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true)) !void {
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
                    '&' => self.setCharacterReferenceStateAndAdvance(.Data, input),
                    '<' => self.setStateAndAdvance(.TagOpen, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitCharAndAdvance('\u{FFFD}', input);
                    },
                    else => self.emitCharAndAdvance(ch, input),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-state
            .RCDATA => {
                if (is_eof) {
                    self.emitEof();
                    return;
                }

                switch (ch) {
                    '&' => self.setCharacterReferenceStateAndAdvance(.RCDATA, input),
                    '<' => self.setStateAndAdvance(.RCDATALessThanSign, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.emitCharAndAdvance('\u{FFFD}', input);
                    },
                    else => self.emitCharAndAdvance(ch, input),
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
                        self.emitCharAndAdvance('\u{FFFD}', input);
                    },
                    else => self.emitCharAndAdvance(ch, input),
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
                        self.emitCharAndAdvance('\u{FFFD}', input);
                    },
                    else => self.emitCharAndAdvance(ch, input),
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
                        self.emitCharAndAdvance('\u{FFFD}', input);
                    },
                    else => self.emitCharAndAdvance(ch, input),
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
                            try self.temporary_buffer.push(ch + 0x0020);
                            self.emitChar(ch);
                            _ = input.nextChar();
                        } else if (ascii.isAsciiLowerAlpha(ch)) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            _ = input.nextChar();
                        } else {
                            self.state = .ScriptDataEscaped;
                        }
                    },
                }
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
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
            .BeforeAttributeName => {
                if (is_eof) {
                    self.state = .AfterAttributeName;
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        _ = input.nextChar();
                    },
                    '/', '>' => {
                        self.state = .AfterAttributeName;
                    },
                    '=' => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedEqualsSignBeforeAttributeName, ch);
                        try self.createAttr_E('=');
                        self.setStateAndAdvance(.AttributeName, input);
                    },
                    else => {
                        try self.createAttr_E(ch);
                        self.setStateAndAdvance(.AttributeName, input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
            .AttributeName => {
                if (is_eof) {
                    self.state = .AfterAttributeName;
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ', '/', '>' => self.state = .AfterAttributeName,
                    '=' => self.setStateAndAdvance(.BeforeAttributeValue, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_attribute_name.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    '"', '\'', '<' => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedCharacterInAttributeName, ch);
                        try self.current_attribute_name.push(ch);
                        _ = input.nextChar();
                    },
                    else => {
                        if (ascii.isAsciiUpperAlpha(ch)) {
                            try self.current_attribute_name.push(ch + 0x0020);
                        } else {
                            try self.current_attribute_name.push(ch);
                        }
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-name-state
            .AfterAttributeName => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInTag, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        _ = input.nextChar();
                    },
                    '/' => self.setStateAndAdvance(.SelfClosingStartTag, input),
                    '=' => self.setStateAndAdvance(.BeforeAttributeValue, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentTag();
                    },
                    else => {
                        try self.createAttr_E(ch);
                        self.setStateAndAdvance(.AttributeName, input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
            .BeforeAttributeValue => {
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        _ = input.nextChar();
                    },
                    '"' => self.setStateAndAdvance(.AttributeValueDoubleQuoted, input),
                    '\'' => self.setStateAndAdvance(.AttributeValueSingleQuoted, input),
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.MissingAttributeValue, ch);
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentTag();
                    },
                    else => {
                        self.state = .AttributeValueUnquoted;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-double-quoted-state
            .AttributeValueDoubleQuoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInTag, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '"' => self.setStateAndAdvance(.AfterAttributeValueQuoted, input),
                    '&' => self.setCharacterReferenceStateAndAdvance(.AttributeValueDoubleQuoted, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_attribute_value.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_attribute_value.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-single-quoted-state
            .AttributeValueSingleQuoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInTag, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\'' => self.setStateAndAdvance(.AfterAttributeValueQuoted, input),
                    '&' => self.setCharacterReferenceStateAndAdvance(.AttributeValueSingleQuoted, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_attribute_value.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_attribute_value.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-unquoted-state
            .AttributeValueUnquoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInTag, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeAttributeName, input),
                    '&' => self.setCharacterReferenceStateAndAdvance(.AttributeValueUnquoted, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentTag();
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_attribute_value.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    '"', '\'', '<', '=', '`' => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedCharacterInUnquotedAttributeValue, ch);
                        try self.current_attribute_value.push(ch);
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_attribute_value.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-value-quoted-state
            .AfterAttributeValueQuoted => {
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
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceBetweenAttributes, ch);
                        self.state = .BeforeAttributeName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#self-closing-start-tag-state
            .SelfClosingStartTag => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInTag, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        self.current_tag_self_closing = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentTag();
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedSolidusInTag, ch);
                        self.state = .BeforeAttributeName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-comment-state
            .BogusComment => {
                if (is_eof) {
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentComment();
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_comment.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_comment.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#markup-declaration-open-state
            .MarkupDeclarationOpen => {
                // TODO
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-state
            .CommentStart => {
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentStartDash, input),
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.AbruptClosingOfEmptyComment, ch);
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentComment();
                    },
                    else => self.state = .Comment,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-dash-state
            .CommentStartDash => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInComment, ch);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentEnd, input),
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.AbruptClosingOfEmptyComment, ch);
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentComment();
                    },
                    else => {
                        try self.current_comment.push('-');
                        self.state = .Comment;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-state
            .Comment => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInComment, ch);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '<' => {
                        try self.current_comment.push('<');
                        self.setStateAndAdvance(.CommentLessThanSign, input);
                    },
                    '-' => self.setStateAndAdvance(.CommentEndDash, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_comment.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_comment.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-state
            .CommentLessThanSign => {
                switch (ch) {
                    '!' => {
                        try self.current_comment.push('!');
                        self.setStateAndAdvance(.CommentLessThanSignBang, input);
                    },
                    '<' => {
                        try self.current_comment.push('<');
                        _ = input.nextChar();
                    },
                    else => self.state = .Comment,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-state
            .CommentLessThanSignBang => {
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentLessThanSignBangDash, input),
                    else => self.state = .Comment,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-state
            .CommentLessThanSignBangDash => {
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentLessThanSignBangDashDash, input),
                    else => self.state = .CommentEndDash,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-dash-state
            .CommentLessThanSignBangDashDash => {
                if (is_eof or ch == '>') self.state = .CommentEnd else {
                    if (self.on_error) |err_cb| err_cb(.NestedComment, ch);
                    self.state = .CommentEnd;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-dash-state
            .CommentEndDash => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInComment, ch);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentEnd, input),
                    else => {
                        try self.current_comment.push('-');
                        self.state = .Comment;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-state
            .CommentEnd => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInComment, ch);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentComment();
                    },
                    '!' => self.setStateAndAdvance(.CommentEndBang, input),
                    '-' => {
                        try self.current_comment.push('-');
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_comment.push('-');
                        try self.current_comment.push('-');
                        self.state = .CommentEnd;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-bang-state
            .CommentEndBang => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInComment, ch);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.IncorrectlyClosedComment, ch);
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentComment();
                    },
                    '-' => {
                        try self.current_comment.push('-');
                        try self.current_comment.push('-');
                        try self.current_comment.push('!');
                        self.setStateAndAdvance(.CommentEndDash, input);
                    },
                    else => {
                        try self.current_comment.push('-');
                        try self.current_comment.push('-');
                        try self.current_comment.push('!');
                        self.state = .Comment;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-state
            .DOCTYPE => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.createDoctype();
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeDOCTYPEName, input),
                    '>' => self.state = .BeforeDOCTYPEName,
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceBeforeDOCTYPEName, ch);
                        self.state = .BeforeDOCTYPEName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-name-state
            .BeforeDOCTYPEName => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.createDoctype();
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        _ = input.nextChar();
                    },
                    'A'...'Z' => {
                        self.createDoctype();
                        try self.current_doctype.name.push(ch + 0x0020);
                        self.setStateAndAdvance(.DOCTYPEName, input);
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        self.createDoctype();
                        try self.current_doctype.name.push('\u{FFFD}');
                        self.setStateAndAdvance(.DOCTYPEName, input);
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.MissingDOCTYPEName, ch);
                        self.createDoctype();
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        self.createDoctype();
                        try self.current_doctype.name.push(ch);
                        self.setStateAndAdvance(.DOCTYPEName, input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-name-state
            .DOCTYPEName => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.AfterDOCTYPEName, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    'A'...'Z' => {
                        try self.current_doctype.name.push(ch + 0x0020);
                        _ = input.nextChar();
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_doctype.name.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    else => {
                        try self.current_doctype.name.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-name-state
            .AfterDOCTYPEName => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        _ = input.nextChar();
                    },
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (match_insensitive(input, "PUBLIC"))
                            self.state = .AfterDOCTYPEPublicKeyword
                        else if (match_insensitive(input, "SYSTEM")) self.state = .AfterDOCTYPESystemKeyword else {
                            if (self.on_error) |err_cb| err_cb(.InvalidCharacterSequenceAfterDOCTYPEName, ch);
                            self.current_doctype.force_quirks = true;
                            self.state = .BogusDOCTYPE;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-keyword-state
            .AfterDOCTYPEPublicKeyword => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeDOCTYPEPublicIdentifier, input),
                    '"' => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceAfterDOCTYPEPublicKeyword, ch);
                        self.current_doctype.public_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceAfterDOCTYPEPublicKeyword, ch);
                        self.current_doctype.public_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierSingleQuoted, input);
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.MissingDOCTYPEPublicIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingQuoteBeforeDOCTYPEPublicIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-public-identifier-state
            .BeforeDOCTYPEPublicIdentifier => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        _ = input.nextChar();
                    },
                    '"' => {
                        self.current_doctype.public_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        self.current_doctype.public_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierSingleQuoted, input);
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.MissingDOCTYPEPublicIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingQuoteBeforeDOCTYPEPublicIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.BogusDOCTYPE, input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(double-quoted)-state
            .DOCTYPEPublicIdentifierDoubleQuoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '"' => self.setStateAndAdvance(.AfterDOCTYPEPublicIdentifier, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_doctype.public_id.push('\u{FFFD}');
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.AbruptDOCTYPEPublicIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.public_id.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(single-quoted)-state
            .DOCTYPEPublicIdentifierSingleQuoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\'' => self.setStateAndAdvance(.AfterDOCTYPEPublicIdentifier, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_doctype.public_id.push('\u{FFFD}');
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.AbruptDOCTYPEPublicIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.public_id.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-identifier-state
            .AfterDOCTYPEPublicIdentifier => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BetweenDOCTYPEPublicAndSystemIdentifiers, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    '"' => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceBetweenDOCTYPEPublicAndSystemIdentifiers, ch);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceBetweenDOCTYPEPublicAndSystemIdentifiers, ch);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierSingleQuoted, input);
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingQuoteBeforeDOCTYPESystemIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#between-doctype-public-and-system-identifiers-state
            .BetweenDOCTYPEPublicAndSystemIdentifiers => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => _ = input.nextChar(),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    '"' => {
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierSingleQuoted, input);
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingQuoteBeforeDOCTYPESystemIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-keyword-state
            .AfterDOCTYPESystemKeyword => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeDOCTYPESystemIdentifier, input),
                    '"' => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceAfterDOCTYPESystemKeyword, ch);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        if (self.on_error) |err_cb| err_cb(.MissingWhitespaceAfterDOCTYPESystemKeyword, ch);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierSingleQuoted, input);
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.MissingDOCTYPESystemIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.MissingQuoteBeforeDOCTYPESystemIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-system-identifier-state
            .BeforeDOCTYPESystemIdentifier => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => _ = input.nextChar(),
                    '"' => {
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierSingleQuoted, input);
                    },
                    '>' => {
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedCharacterAfterDOCTYPESystemIdentifier, ch);
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            .DOCTYPESystemIdentifierDoubleQuoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '"' => self.setStateAndAdvance(.AfterDOCTYPESystemIdentifier, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_doctype.system_id.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.AbruptDOCTYPESystemIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.system_id.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(single-quoted)-state
            .DOCTYPESystemIdentifierSingleQuoted => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\'' => self.setStateAndAdvance(.AfterDOCTYPESystemIdentifier, input),
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        try self.current_doctype.system_id.push('\u{FFFD}');
                        _ = input.nextChar();
                    },
                    '>' => {
                        if (self.on_error) |err_cb| err_cb(.AbruptDOCTYPESystemIdentifier, ch);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.system_id.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-identifier-state
            .AfterDOCTYPESystemIdentifier => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInDOCTYPE, ch);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => _ = input.nextChar(),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedCharacterAfterDOCTYPESystemIdentifier, ch);
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-doctype-state
            .BogusDOCTYPE => {
                if (is_eof) {
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    0x0000 => {
                        if (self.on_error) |err_cb| err_cb(.UnexpectedNullCharacter, ch);
                        _ = input.nextChar();
                    },
                    else => _ = input.nextChar(),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-state
            .CDATASection => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInCDATA, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    ']' => self.setStateAndAdvance(.CDATASectionBracket, input),
                    else => self.emitCharAndAdvance(ch, input),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-bracket-state
            .CDATASectionBracket => {
                switch (ch) {
                    ']' => self.setStateAndAdvance(.CDATASectionEnd, input),
                    else => {
                        self.emitChar(']');
                        self.state = .CDATASection;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-end-state
            .CDATASectionEnd => {
                switch (ch) {
                    ']' => self.emitCharAndAdvance(']', input),
                    '>' => self.setStateAndAdvance(.Data, input),
                    else => {
                        self.emitChar(']');
                        self.emitChar(']');
                        self.state = .CDATASection;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-open-state
            .ProcessingInstructionOpen => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInProcessingInstruction, ch);
                    self.emitEof();
                    return;
                }
                if (ascii.isAsciiAlpha(ch) or ch == '_') self.state = .ProcessingInstructionTarget else {
                    if (self.on_error) |err_cb| err_cb(.InvalidFirstCharacterOfProcessingInstructionTarget, ch);
                    self.current_comment = self.temporary_buffer;
                    self.state = .BogusComment;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-target-state
            .ProcessingInstructionTarget => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInProcessingInstruction, ch);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ', '?', '>' => {
                        var t = try BufferDeque(.utf8, .not_atomic, true).init(self.allocator);
                        try t.pushBack(self.temporary_buffer.clone());
                        if (match_insensitive(&t, "xml") or match_insensitive(&t, "xml-stylesheet")) {
                            if (self.on_error) |err_cb| err_cb(.DisallowedProcessingInstructionTarget, ch);

                            self.current_comment = self.temporary_buffer.clone();
                            self.temporary_buffer.clear();
                            self.state = .BogusComment;
                        } else {
                            if (t.popFront()) |str| {
                                self.current_process_inst.target = str;
                            }
                            self.state = .AfterProcessingInstructionTarget;
                        }
                    },
                    else => {
                        if (ascii.isAsciiAlphanum(ch) or (ch == '-') or (ch == '_')) {
                            try self.temporary_buffer.push(ch);
                            _ = input.nextChar();
                        } else {
                            if (self.on_error) |err_cb| err_cb(.InvaildProcessingInstructionTarget, ch);
                            self.current_comment = self.temporary_buffer.clone();
                            self.temporary_buffer.clear();
                            self.state = .BogusComment;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-processing-instruction-target-state
            .AfterProcessingInstructionTarget => {
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => _ = input.nextChar(),
                    else => self.state = .ProcessingInstructionData,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-data-state
            .ProcessingInstructionData => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInProcessingInstruction, ch);
                    self.emitEof();
                }
                switch (ch) {
                    '?' => self.setStateAndAdvance(.ProcessingInstructionQuestionable, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitProcessingInst();
                    },
                    else => {
                        try self.current_process_inst.data.push(ch);
                        _ = input.nextChar();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-questionable-state
            .ProcessingInstructionQuestionable => {
                if (is_eof) {
                    if (self.on_error) |err_cb| err_cb(.EofInProcessingInstruction, ch);
                    self.emitEof();
                }
                switch (ch) {
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitProcessingInst();
                    },
                    else => {
                        try self.current_process_inst.data.push('?');
                        self.state = .ProcessingInstructionData;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#character-reference-state
            .CharacterReference => {
                self.temporary_buffer.clear();
                try self.temporary_buffer.push('&');
                switch (ch) {
                    '#' => {
                        try self.temporary_buffer.push(ch);
                        self.setStateAndAdvance(.NumericCharacterReference, input);
                    },
                    else => {
                        if (ascii.isAsciiAlphanum(ch)) self.state = .NamedCharacterReference else {
                            try self.flushCodePoints();
                            self.state = self.return_state;
                        }
                    },
                }
            },
            //            .CharacterReferenceInData => self.stepCharacterReference(.CharacterReferenceInData, is_eof, ch),
            //
            //            .CharacterReferenceInRCDATA => self.stepCharacterReference(.CharacterReferenceInRCDATA, is_eof, ch),
            //
            //            .CharacterReferenceInAttributeValueSingleQuoted => self.stepCharacterReference(.CharacterReferenceInAttributeValueSingleQuoted, is_eof, ch),
            //
            //            .CharacterReferenceInAttributeValueDoubleQuoted => self.stepCharacterReference(.CharacterReferenceInAttributeValueDoubleQuoted, is_eof, ch),
            //
            //            .CharacterReferenceInAttributeValueUnquoted => self.stepCharacterReference(.CharacterReferenceInAttributeValueUnquoted, is_eof, ch),

            // https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
            .NamedCharacterReference => {
                const res = self.tryConsumeNamedCharRef(input);
                if (res) |r| {
                    const is_last_semicolon, const matched = r;
                    if (self.isConsumedAsPartOfAttr() and
                        !is_last_semicolon and (ch == '=' or ascii.isAsciiAlphanum(ch)))
                    {
                        try self.flushCodePoints();
                        self.setStateAndAdvance(self.return_state, input);
                    } else {
                        if (!is_last_semicolon) {
                            if (self.on_error) |err_cb| err_cb(.MissingSemicolonAfterCharacterReference, ch);
                        }
                        self.temporary_buffer.clear();
                        try self.temporary_buffer.append(matched);
                        try self.flushCodePoints();
                        self.setStateAndAdvance(self.return_state, input);
                    }
                } else {
                    try self.flushCodePoints();
                    self.setStateAndAdvance(.AmbiguousAmpersand, input);
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#ambiguous-ampersand-state
            .AmbiguousAmpersand => {
                switch (ch) {
                    ';' => {
                        if (self.on_error) |err_cb| err_cb(.UnknownNamedCharacterReference, ch);
                        self.state = self.return_state;
                    },
                    else => {
                        if (ascii.isAsciiAlphanum(ch)) {
                            if (self.isConsumedAsPartOfAttr())
                                try self.current_attribute_value.push(ch)
                            else
                                self.emitChar(ch);
                            _ = input.nextChar();
                        } else {
                            self.state = self.return_state;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-state
            .NumericCharacterReference => {
                self.char_ref_code = 0;
                switch (ch) {
                    'x', 'X' => {
                        try self.temporary_buffer.push(ch);
                        self.setStateAndAdvance(.HexadecimalCharacterReferenceStart, input);
                    },
                    else => self.state = .DecimalCharacterReferenceStart,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-start-state
            .HexadecimalCharacterReferenceStart => {
                if (ascii.isAsciiHexDigit(ch)) self.state = .HexadecimalCharacterReference else {
                    if (self.on_error) |err_cb| err_cb(.AbsenceOfDigitsInNumericCharacterReference, ch);
                    try self.flushCodePoints();
                    self.state = self.return_state;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-start-state
            .DecimalCharacterReferenceStart => {
                if (ascii.isAsciiDigit(ch)) self.state = .DecimalCharacterReference else {
                    if (self.on_error) |err_cb| err_cb(.AbsenceOfDigitsInNumericCharacterReference, ch);
                    try self.flushCodePoints();
                    self.state = self.return_state;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-state
            .HexadecimalCharacterReference => blk: {
                if (ascii.isAsciiDigit(ch))
                    self.char_ref_code = self.char_ref_code * 16 + (ch - 0x0030)
                else if (ascii.isAsciiUpperAlpha(ch)) self.char_ref_code = self.char_ref_code * 16 + (ch - 0x0037) else if (ascii.isAsciiLowerAlpha(ch)) self.char_ref_code = self.char_ref_code * 16 + (ch - 0x0057) else if (ch == ';') self.state = .NumericCharacterReferenceEnd else {
                    if (self.on_error) |err_cb| err_cb(.MissingSemicolonAfterCharacterReference, ch);
                    self.state = .NumericCharacterReferenceEnd;
                    break :blk;
                }
                _ = input.nextChar();
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-state
            .DecimalCharacterReference => {
                switch (ch) {
                    ';' => self.setStateAndAdvance(.NumericCharacterReferenceEnd, input),
                    else => {
                        if (ascii.isAsciiDigit(ch)) {
                            self.char_ref_code = self.char_ref_code * 10 + (ch - 0x0030);
                            _ = input.nextChar();
                        } else {
                            if (self.on_error) |err_cb| err_cb(.MissingSemicolonAfterCharacterReference, ch);
                            self.state = .NumericCharacterReferenceEnd;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
            .NumericCharacterReferenceEnd => {
                const code = self.char_ref_code;
                if (code == 0x00) {
                    if (self.on_error) |err_cb| err_cb(.NullCharacterReference, ch);
                    self.char_ref_code = 0xFFFD;
                } else if (code > 0x10FFFF) {
                    if (self.on_error) |err_cb| err_cb(.CharacterReferenceOutsideUnicodeRange, ch);
                    self.char_ref_code = 0xFFFD;
                } else if (ascii.isSurrogate(code)) {
                    if (self.on_error) |err_cb| err_cb(.SurrogateCharacterReference, ch);
                    self.char_ref_code = 0xFFFD;
                } else if (ascii.isNoneCharacter(code)) {
                    if (self.on_error) |err_cb| err_cb(.NoncharacterCharacterReference, ch);
                } else if (code == 0x0D or (ascii.isControl(code) and !ascii.isAsciiWhitespace(code))) {
                    if (self.on_error) |err_cb| err_cb(.ControlCharacterReference, ch);
                    self.setCodePoint();
                }

                self.temporary_buffer.clear();
                try self.temporary_buffer.push(self.char_ref_code);
                try self.flushCodePoints();
                self.setStateAndAdvance(self.return_state, input);
            },
        }
    }
}

// https://html.spec.whatwg.org/multipage/parsing.html#flush-code-points-consumed-as-a-character-reference
pub fn flushCodePoints(self: *Tokenizer) !void {
    const slice = self.temporary_buffer.slice();
    for (slice) |s| {
        if (self.isConsumedAsPartOfAttr()) try self.current_attribute_value.push(s) else self.emitChar(s);
    }
}

inline fn isConsumedAsPartOfAttr(self: *Tokenizer) bool {
    return blk: switch (self.return_state) {
        .AttributeValueSingleQuoted, .AttributeValueDoubleQuoted, .AttributeValueUnquoted => break :blk true,
        else => break :blk false,
    };
}

// TODO: Replace with Trie.
pub fn tryConsumeNamedCharRef(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true)) ?struct { bool, []const u8 } {
    _ = self;
    _ = input;
    return null;
}

pub inline fn setCodePoint(self: *Tokenizer) void {
    switch (self.char_ref_code) {
        0x80 => self.char_ref_code = 0x20AC,
        0x82 => self.char_ref_code = 0x201A,
        0x83 => self.char_ref_code = 0x0192,
        0x84 => self.char_ref_code = 0x201E,
        0x85 => self.char_ref_code = 0x2026,
        0x86 => self.char_ref_code = 0x2020,
        0x87 => self.char_ref_code = 0x2021,
        0x88 => self.char_ref_code = 0x02C6,
        0x89 => self.char_ref_code = 0x2030,
        0x8A => self.char_ref_code = 0x0160,
        0x8B => self.char_ref_code = 0x2039,
        0x8C => self.char_ref_code = 0x0152,
        0x8E => self.char_ref_code = 0x017D,
        0x91 => self.char_ref_code = 0x2018,
        0x92 => self.char_ref_code = 0x2019,
        0x93 => self.char_ref_code = 0x201C,
        0x94 => self.char_ref_code = 0x201D,
        0x95 => self.char_ref_code = 0x2022,
        0x96 => self.char_ref_code = 0x2013,
        0x97 => self.char_ref_code = 0x2014,
        0x98 => self.char_ref_code = 0x02DC,
        0x99 => self.char_ref_code = 0x2122,
        0x9A => self.char_ref_code = 0x0161,
        0x9B => self.char_ref_code = 0x203A,
        0x9C => self.char_ref_code = 0x0153,
        0x9E => self.char_ref_code = 0x017E,
        0x9F => self.char_ref_code = 0x0178,
        else => {},
    }
}
