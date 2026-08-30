const Tokenizer = @This();

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
const TokenAdapter = @import("TokenAdapter.zig");
const trie_nodes = @import("named_ref").trie_nodes;
const local_name = @import("local_name");
const LocalName = local_name.LocalName;
const LocalNameMap = local_name.LocalNameMap;
const config = @import("config");

allocator: std.mem.Allocator,
state: TokenizerState,
ch: u21,
is_eof: bool,
return_state: TokenizerState,
pause_flag: bool,
// Character reference code.
char_ref_code: u64,
ignore_lf: bool,

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
current_attr_dup: bool,

current_character: StraleUtf8Global,
current_line: usize,
adapter: TokenAdapter,
last_start_tag_name: ?StraleUtf8Global,
temporary_buffer: StraleUtf8Global,

pub const TokenizerOpts = struct {
    initial_state: TokenizerState = .Data,
    last_state_tag_name: ?StraleUtf8Global = null,
};

pub fn init(alloc: std.mem.Allocator, adapter: TokenAdapter, opts: TokenizerOpts) Tokenizer {
    //  TOOD: enable global allocator
    //    strale.setGlobalAlloc(alloc);
    return Tokenizer{
        .allocator = alloc,
        .state = opts.initial_state,
        .ch = undefined,
        .is_eof = false,
        .return_state = .Data,
        .pause_flag = false,
        .char_ref_code = 0,
        .ignore_lf = false,
        .current_tag_name = StraleUtf8Global.initEmpty(),
        .current_tag_kind = .StartTag,
        .current_tag_self_closing = false,
        .current_comment = StraleUtf8Global.initEmpty(),
        .current_attribute_name = StraleUtf8Global.initEmpty(),
        .current_attribute_value = StraleUtf8Global.initEmpty(),
        .current_tag_attrs = .empty,
        .current_doctype = token.Doctype.init(),
        .current_process_inst = token.ProcessingInstruction.init(),
        .current_attr_dup = false,
        .current_character = StraleUtf8Global.initEmpty(),
        .current_line = 1,
        .adapter = adapter,
        .last_start_tag_name = opts.last_state_tag_name,
        .temporary_buffer = StraleUtf8Global.initEmpty(),
    };
}

pub fn deinit(self: *Tokenizer) void {
    self.current_tag_name.deinit();
    self.current_comment.deinit();
    self.current_attribute_name.deinit();
    self.current_attribute_value.deinit();
    self.current_doctype.deinit();
    self.current_process_inst.deinit();
    self.temporary_buffer.deinit();
}

pub fn handleToken(self: *Tokenizer, t: token.Token) void {
    if (self.adapter.handleToken(t)) |state| self.state = state;
}

pub fn emitChar(self: *Tokenizer, ch: u21) void {
    self.current_character.push(ch) catch return;
}

pub fn flushCurrentChar(self: *Tokenizer) void {
    if (self.current_character.isEmpty()) return;
    self.handleToken(token.Token{ .CharacterToken = self.current_character.take() });
}

pub fn emitEof(self: *Tokenizer) void {
    self.flushCurrentChar();
    self.handleToken(.EofToken);
}

pub fn emitCurrentTag(self: *Tokenizer) void {
    self.flushCurrentChar();
    self.sealAttr() catch return;
    switch (self.current_tag_kind) {
        .StartTag => {
            self.last_start_tag_name = self.current_tag_name.clone();
        },
        .EndTag => {
            if (self.current_tag_attrs.items.len != 0) self.handleError(.EndTagWithAttributes);
            if (self.current_tag_self_closing) self.handleError(.EndTagWithSelfClosing);
        },
    }
    const tag_token = token.Tag{
        .kind = self.current_tag_kind,
        .name = LocalName.fromSlice(self.current_tag_name.slice()) catch return,
        .self_closing = self.current_tag_self_closing,
        .attrs = self.current_tag_attrs,
    };
    self.current_tag_attrs = .empty;
    self.handleToken(token.Token{ .TagToken = tag_token });
}

pub fn emitTempBuffer(self: *Tokenizer) void {
    self.current_character.append(self.temporary_buffer.slice()) catch return;
    self.temporary_buffer.clear();
}

pub fn emitCurrentComment(self: *Tokenizer) void {
    self.flushCurrentChar();
    self.handleToken(token.Token{ .CommentToken = self.current_comment.clone() });
    self.current_comment.clear();
}

pub fn emitCurrentDoctype(self: *Tokenizer) void {
    self.flushCurrentChar();
    self.handleToken(token.Token{ .DoctypeToken = self.current_doctype });
    self.current_doctype = token.Doctype.init();
}

pub fn emitCharAndAdvance(self: *Tokenizer, ch: u21, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.emitChar(ch);
    self.nextChar(input);
}

pub fn emitProcessingInst(self: *Tokenizer) void {
    self.flushCurrentChar();
    self.handleToken(token.Token{ .ProcessingInstructionToken = self.current_process_inst });
}

pub fn discardTag(self: *Tokenizer) void {
    self.current_tag_name.clear();
    self.current_tag_self_closing = false;
}

pub fn createTag(self: *Tokenizer, tag_kind: token.TagKind) void {
    self.discardTag();
    self.current_tag_kind = tag_kind;
}

pub fn createAttr_E(self: *Tokenizer, ch: ?u21) !void {
    try self.sealAttr();
    if (ch) |c| try self.current_attribute_name.push(c);
}

// Append current attribute to current tag's attribute list and
// clear the fields.
pub fn sealAttr(self: *Tokenizer) !void {
    if (self.current_attribute_name.isEmpty()) return;
    const name_slice = self.current_attribute_name.slice();
    var lc_attr = try LocalName.fromSlice(name_slice);
    defer lc_attr.deinit();
    const dup = for (self.current_tag_attrs.items) |attr| {
        if (attr.name.eql(lc_attr)) break true;
    } else false;
    if (dup) {
        self.handleError(.DuplicateAttribute);
        self.current_attr_dup = true;
        self.current_attribute_name.clear();
        self.current_attribute_value.clear();
    } else {
        const final_name = if (LocalNameMap.get(name_slice)) |tag|
            LocalName{ .static = tag }
        else
            LocalName{ .dynamic = self.current_attribute_name.take() };

        self.current_attribute_name.clear();
        try self.current_tag_attrs.append(self.allocator, .{
            .name = final_name,
            .value = self.current_attribute_value.take(),
        });
    }
}

// Ensure the previous character is not '\n' when use this function.
// Otherwise should use updateLine version.
pub inline fn setStateAndAdvance(self: *Tokenizer, state: TokenizerState, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.state = state;
    self.nextChar(input);
}

pub inline fn setCharacterReferenceStateAndAdvance(self: *Tokenizer, return_state: TokenizerState, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.return_state = return_state;
    self.setStateAndAdvance(.CharacterReference, input);
}

fn asciiEqIgnoreCase(a: u8, b: u8) bool {
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

fn asciiEq(a: u8, b: u8) bool {
    return a == b;
}

pub fn match_insensitive(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true), str: []const u8) bool {
    if (input.consume(str, asciiEqIgnoreCase)) {
        self.peekChar(input);
        return true;
    }
    return false;
}

pub fn match_sensitive(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true), str: []const u8) bool {
    if (input.consume(str, asciiEq)) {
        self.peekChar(input);
        return true;
    }
    return false;
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

// https://html.spec.whatwg.org/multipage/parsing.html#flush-code-points-consumed-as-a-character-reference
pub fn flushCodePoints_E(self: *Tokenizer) !void {
    const slice = self.temporary_buffer.slice();
    try if (self.isConsumedAsPartOfAttr()) self.current_attribute_value.append(slice) else self.current_character.append(slice);
}

inline fn isConsumedAsPartOfAttr(self: *Tokenizer) bool {
    return blk: switch (self.return_state) {
        .AttributeValueSingleQuoted, .AttributeValueDoubleQuoted, .AttributeValueUnquoted => break :blk true,
        else => break :blk false,
    };
}

inline fn peekChar(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    self.is_eof = if (input.peekChar()) |c| blk: {
        self.ch = c;
        break :blk false;
    } else true;
}

inline fn nextChar(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true)) void {
    const raw = input.nextChar() orelse return;
    if (raw == '\r' or raw == '\n') self.current_line += 1;
    self.peekChar(input);
    if (!self.is_eof) self.preprocessChar(input, &self.ch);
}

pub fn consumeNamedCharRef(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true)) !?struct { []const u8, bool } {
    var matched_str: ?[]const u8 = null;
    var has_semicolon = false;
    var matched_len: usize = 0;

    var current_node_idx: usize = 0;
    var lookahead_idx: usize = 0;

    while (true) {
        const next_ch = input.peekCharN(lookahead_idx) orelse break;

        if (next_ch > 127) break;
        const search_char = @as(u8, @intCast(next_ch));

        const current_node = trie_nodes[current_node_idx];

        var found_child_idx: ?usize = null;
        const start = current_node.child_start;
        const end = start + current_node.child_count;

        var i = start;
        while (i < end) : (i += 1) {
            if (trie_nodes[i].char == search_char) {
                found_child_idx = i;
                break;
            }
        }

        const child_idx = found_child_idx orelse break;

        current_node_idx = child_idx;
        lookahead_idx += 1;

        if (trie_nodes[child_idx].value) |val| {
            matched_str = val;
            has_semicolon = (search_char == ';');
            matched_len = lookahead_idx;
        }
    }
    if (matched_str) |value| {
        var i: usize = 0;
        while (i < matched_len) : (i += 1) {
            if (input.nextChar()) |ch| try self.temporary_buffer.push(ch);
        }

        return .{ value, has_semicolon };
    }
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

// https://html.spec.whatwg.org/multipage/parsing.html#adjusted-current-node
pub fn is_adjusted(self: *Tokenizer) bool {
    // TODO
    _ = self;
    return false;
}

pub inline fn handleError(self: *Tokenizer, err: TokenizerError) void {
    self.adapter.handleError(err, self.current_line);
}

pub fn debugDetail(self: *Tokenizer) void {
    std.debug.print("Current Character: {s}\n", .{self.current_character.slice()});
    std.debug.print("Current Tag Attributes:\n", .{});
    for (self.current_tag_attrs.items) |a| {
        std.debug.print("   {f}:\n", .{a});
    }
    std.debug.print("Current Tag Name: {s}\n", .{self.current_tag_name.slice()});
    std.debug.print("Current Tag Value: {}\n", .{self.current_tag_self_closing});
    std.debug.print("Current Tag Kind: {s}\n", .{@tagName(self.current_tag_kind)});
    std.debug.print("Current Attribute Name: {s}\n", .{self.current_attribute_name.slice()});
    std.debug.print("Current Attribute Value: {s}\n", .{self.current_attribute_value.slice()});
    std.debug.print("Current Attribute Name: {f}\n", .{self.current_doctype});
}

pub fn preprocessChar(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true), ch: *u21) void {
    if (self.ignore_lf) {
        self.ignore_lf = false;

        if (ch.* == '\n') {
            _ = input.nextChar();

            if (input.peekChar()) |next|
                ch.* = next
            else
                self.is_eof = true;
        }
    }

    if (ch.* == '\r') {
        self.ignore_lf = true;
        ch.* = '\n';
    }

    if (self.is_eof) return;

    if (ascii.isSurrogate(u21, ch.*)) self.handleError(.SurrogateInInputStream) else if (ascii.isNoncharacter(u21, ch.*)) self.handleError(.NoncharacterInInputStream) else if (ascii.isControlCharacter(u21, ch.*)) self.handleError(.ControlCharacterInInputStream);
}

pub fn step_E(self: *Tokenizer, input: *BufferDeque(.utf8, .not_atomic, true)) !void {
    self.peekChar(input);
    self.preprocessChar(input, &self.ch);
    while (true) {
        //        self.peekChar(input);
        const ch = self.ch;
        const is_eof = self.is_eof;

        // Jump to here if is_eof already been true.
        if (config.debug) {
            std.debug.print("\n[STATE]: {s}\n", .{@tagName(self.state)});
            self.debugDetail();
        }

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
                        self.handleError(.UnexpectedNullCharacter);
                        self.emitCharAndAdvance(ch, input);
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
                        self.handleError(.UnexpectedNullCharacter);
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
                        self.handleError(.UnexpectedNullCharacter);
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
                        self.handleError(.UnexpectedNullCharacter);
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
                        self.handleError(.UnexpectedNullCharacter);
                        self.emitCharAndAdvance('\u{FFFD}', input);
                    },
                    else => self.emitCharAndAdvance(ch, input),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-open-state
            .TagOpen => {
                if (is_eof) {
                    self.handleError(.EofBeforeTagName);
                    self.emitChar('<');
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '!' => self.setStateAndAdvance(.MarkupDeclarationOpen, input),
                    '/' => self.setStateAndAdvance(.EndTagOpen, input),
                    '?' => {
                        self.handleError(.UnexpectedQuestionMarkInsteadOfTagName);
                        self.current_comment.clear();
                        // Since reconsume, no advance here.
                        self.state = .BogusComment;
                    },
                    else => {
                        if (ascii.isAsciiAlpha(ch)) {
                            self.createTag(.StartTag);
                            self.state = .TagName;
                        } else {
                            self.handleError(.InvalidFirstCharacterOfTagName);
                            self.emitChar('<');
                            self.state = .Data;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#end-tag-open-state
            .EndTagOpen => {
                if (is_eof) {
                    self.handleError(.EofBeforeTagName);
                    self.emitChar('<');
                    self.emitChar('/');
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        self.handleError(.MissingEndTagName);
                        self.setStateAndAdvance(.Data, input);
                    },
                    else => {
                        if (ascii.isAsciiAlpha(ch)) {
                            self.createTag(.EndTag);
                            self.state = .TagName;
                        } else {
                            self.handleError(.InvalidFirstCharacterOfTagName);
                            self.current_comment.clear();
                            self.state = .BogusComment;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-name-state
            .TagName => {
                if (is_eof) {
                    self.handleError(.EofInTag);
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
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_tag_name.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        if (ascii.isAsciiUpperAlpha(ch))
                            try self.current_tag_name.push(ch + 0x0020)
                        else
                            try self.current_tag_name.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-less-than-sign-state
            .RCDATALessThanSign => {
                switch (ch) {
                    '/' => {
                        self.temporary_buffer.clear();
                        self.setStateAndAdvance(.RCDATAEndTagOpen, input);
                    },
                    else => {
                        self.emitChar('<');
                        self.state = .RCDATA;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-open-state
            .RCDATAEndTagOpen => {
                if (ascii.isAsciiAlpha(ch) and !is_eof) {
                    self.createTag(.EndTag);
                    self.state = .RCDATAEndTagName;
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
                if (ascii.isAsciiUpperAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
                } else if (ascii.isAsciiLowerAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
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
                if (ascii.isAsciiAlpha(ch) and !is_eof) {
                    self.createTag(.EndTag);
                    self.state = .RAWTEXTEndTagName;
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
                if (ascii.isAsciiUpperAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
                } else if (ascii.isAsciiLowerAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
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
                if (ascii.isAsciiAlpha(ch) and !is_eof) {
                    self.createTag(.EndTag);
                    self.state = .ScriptDataEndTagName;
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
                if (ascii.isAsciiUpperAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
                } else if (ascii.isAsciiLowerAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
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
                    self.handleError(.EofInScriptHtmlCommentLikeText);
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
                        self.handleError(.UnexpectedNullCharacter);
                        self.emitChar('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        self.emitChar(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-state
            .ScriptDataEscapedDash => {
                if (is_eof) {
                    self.handleError(.EofInScriptHtmlCommentLikeText);
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
                        self.handleError(.UnexpectedNullCharacter);
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
                    self.handleError(.EofInScriptHtmlCommentLikeText);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.emitChar('-');
                        self.nextChar(input);
                    },
                    '<' => self.setStateAndAdvance(.ScriptDataEscapedLessThanSign, input),
                    '>' => {
                        self.setStateAndAdvance(.ScriptData, input);
                        self.emitChar('>');
                    },
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
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
                        if (ascii.isAsciiAlpha(ch) and !is_eof) {
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
                if (ascii.isAsciiAlpha(ch) and !is_eof) {
                    self.createTag(.EndTag);
                    self.state = .ScriptDataEscapedEndTagName;
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
                if (ascii.isAsciiUpperAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch + 0x0020);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
                } else if (ascii.isAsciiLowerAlpha(ch) and !is_eof) {
                    try self.current_tag_name.push(ch);
                    try self.temporary_buffer.push(ch);
                    self.nextChar(input);
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
                        if (ascii.isAsciiUpperAlpha(ch) and !is_eof) {
                            try self.temporary_buffer.push(ch + 0x0020);
                            self.emitChar(ch);
                            self.nextChar(input);
                        } else if (ascii.isAsciiLowerAlpha(ch) and !is_eof) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            self.nextChar(input);
                        } else {
                            self.state = .ScriptDataEscaped;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-state
            .ScriptDataDoubleEscaped => {
                if (is_eof) {
                    self.handleError(.EofInScriptHtmlCommentLikeText);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscapedDash, input);
                        self.emitChar('-');
                    },
                    '<' => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscapedLessThanSign, input);
                        self.emitChar('<');
                    },
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        self.emitChar('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        self.emitChar(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-state
            .ScriptDataDoubleEscapedDash => {
                if (is_eof) {
                    self.handleError(.EofInScriptHtmlCommentLikeText);
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
                        self.handleError(.UnexpectedNullCharacter);
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
                    self.handleError(.EofInScriptHtmlCommentLikeText);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => {
                        self.emitChar('-');
                        self.nextChar(input);
                    },
                    '<' => {
                        self.setStateAndAdvance(.ScriptDataDoubleEscapedLessThanSign, input);
                        self.emitChar('<');
                    },
                    '>' => {
                        self.setStateAndAdvance(.ScriptData, input);
                        self.emitChar('>');
                    },
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
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
                        if (ascii.isAsciiUpperAlpha(ch) and !is_eof) {
                            try self.temporary_buffer.push(ch + 0x0020);
                            self.emitChar(ch);
                            self.nextChar(input);
                        } else if (ascii.isAsciiLowerAlpha(ch) and !is_eof) {
                            try self.temporary_buffer.push(ch);
                            self.emitChar(ch);
                            self.nextChar(input);
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
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        self.nextChar(input);
                    },
                    '/', '>' => {
                        self.state = .AfterAttributeName;
                    },
                    '=' => {
                        self.handleError(.UnexpectedEqualsSignBeforeAttributeName);
                        try self.createAttr_E('=');
                        self.setStateAndAdvance(.AttributeName, input);
                    },
                    else => {
                        try self.createAttr_E(null);
                        self.state = .AttributeName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
            .AttributeName => {
                if (is_eof) {
                    self.state = .AfterAttributeName;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ', '/', '>' => self.state = .AfterAttributeName,
                    '=' => self.setStateAndAdvance(.BeforeAttributeValue, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_attribute_name.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    '"', '\'', '<' => {
                        self.handleError(.UnexpectedCharacterInAttributeName);
                        try self.current_attribute_name.push(ch);
                        self.nextChar(input);
                    },
                    else => {
                        if (ascii.isAsciiUpperAlpha(ch)) {
                            try self.current_attribute_name.push(ch + 0x0020);
                        } else {
                            try self.current_attribute_name.push(ch);
                        }
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-name-state
            .AfterAttributeName => {
                if (is_eof) {
                    self.handleError(.EofInTag);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        self.nextChar(input);
                    },
                    '/' => self.setStateAndAdvance(.SelfClosingStartTag, input),
                    '=' => self.setStateAndAdvance(.BeforeAttributeValue, input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentTag();
                    },
                    else => {
                        try self.createAttr_E(null);
                        self.state = .AttributeName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
            .BeforeAttributeValue => {
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        self.nextChar(input);
                    },
                    '"' => self.setStateAndAdvance(.AttributeValueDoubleQuoted, input),
                    '\'' => self.setStateAndAdvance(.AttributeValueSingleQuoted, input),
                    '>' => {
                        self.handleError(.MissingAttributeValue);
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
                    self.handleError(.EofInTag);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '"' => self.setStateAndAdvance(.AfterAttributeValueQuoted, input),
                    '&' => self.setCharacterReferenceStateAndAdvance(.AttributeValueDoubleQuoted, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_attribute_value.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_attribute_value.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-single-quoted-state
            .AttributeValueSingleQuoted => {
                if (is_eof) {
                    self.handleError(.EofInTag);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\'' => self.setStateAndAdvance(.AfterAttributeValueQuoted, input),
                    '&' => self.setCharacterReferenceStateAndAdvance(.AttributeValueSingleQuoted, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_attribute_value.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_attribute_value.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-unquoted-state
            .AttributeValueUnquoted => {
                if (is_eof) {
                    self.handleError(.EofInTag);
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
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_attribute_value.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    '"', '\'', '<', '=', '`' => {
                        self.handleError(.UnexpectedCharacterInUnquotedAttributeValue);
                        try self.current_attribute_value.push(ch);
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_attribute_value.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-value-quoted-state
            .AfterAttributeValueQuoted => {
                if (is_eof) {
                    self.handleError(.EofInTag);
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
                        self.handleError(.MissingWhitespaceBetweenAttributes);
                        self.state = .BeforeAttributeName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#self-closing-start-tag-state
            .SelfClosingStartTag => {
                if (is_eof) {
                    self.handleError(.EofInTag);
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
                        self.handleError(.UnexpectedSolidusInTag);
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
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_comment.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_comment.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#markup-declaration-open-state
            .MarkupDeclarationOpen => {
                if (self.match_sensitive(input, "--")) {
                    self.current_comment.clear();
                    if (!self.is_eof) self.preprocessChar(input, &self.ch);
                    self.state = .CommentStart;
                } else if (self.match_insensitive(input, "DOCTYPE")) {
                    if (!self.is_eof) self.preprocessChar(input, &self.ch);
                    self.state = .DOCTYPE;
                } else if (self.match_sensitive(input, "[CDATA[")) {
                    if (self.adapter.adjustCurrentNodeAndNotInHtmlNamespace()) {
                        self.state = .CDATASection;
                    } else {
                        self.handleError(.CDATAInHtmlContent);

                        try self.current_comment.append("[CDATA[");
                        self.state = .BogusComment;
                    }
                } else {
                    self.handleError(.IncorrectlyOpenedComment);
                    self.current_comment.clear();
                    self.state = .BogusComment;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-state
            .CommentStart => {
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentStartDash, input),
                    '>' => {
                        self.handleError(.AbruptClosingOfEmptyComment);
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentComment();
                    },
                    else => self.state = .Comment,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-dash-state
            .CommentStartDash => {
                if (is_eof) {
                    self.handleError(.EofInComment);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentEnd, input),
                    '>' => {
                        self.handleError(.AbruptClosingOfEmptyComment);
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
                    self.handleError(.EofInComment);
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
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_comment.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_comment.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-state
            .CommentLessThanSign => {
                if (is_eof) {
                    self.state = .Comment;
                } else switch (ch) {
                    '!' => {
                        try self.current_comment.push('!');
                        self.setStateAndAdvance(.CommentLessThanSignBang, input);
                    },
                    '<' => {
                        try self.current_comment.push('<');
                        self.nextChar(input);
                    },
                    else => self.state = .Comment,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-state
            .CommentLessThanSignBang => {
                if (is_eof) {
                    self.state = .Comment;
                } else switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentLessThanSignBangDash, input),
                    else => self.state = .Comment,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-state
            .CommentLessThanSignBangDash => {
                if (is_eof) {
                    self.state = .Comment;
                } else switch (ch) {
                    '-' => self.setStateAndAdvance(.CommentLessThanSignBangDashDash, input),
                    else => self.state = .CommentEndDash,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-dash-state
            .CommentLessThanSignBangDashDash => {
                if (is_eof) {
                    self.state = .Comment;
                } else if (ch == '>') self.state = .CommentEnd else {
                    self.handleError(.NestedComment);
                    self.state = .CommentEnd;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-dash-state
            .CommentEndDash => {
                if (is_eof) {
                    self.handleError(.EofInComment);
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
                    self.handleError(.EofInComment);
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
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_comment.push('-');
                        try self.current_comment.push('-');
                        self.state = .Comment;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-bang-state
            .CommentEndBang => {
                if (is_eof) {
                    self.handleError(.EofInComment);
                    self.emitCurrentComment();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '>' => {
                        self.handleError(.IncorrectlyClosedComment);
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
                    self.handleError(.EofInDOCTYPE);
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
                        self.handleError(.MissingWhitespaceBeforeDOCTYPEName);
                        self.state = .BeforeDOCTYPEName;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-name-state
            .BeforeDOCTYPEName => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.createDoctype();
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        self.nextChar(input);
                    },
                    'A'...'Z' => {
                        self.createDoctype();
                        try self.current_doctype.name.push(ch + 0x0020);
                        self.setStateAndAdvance(.DOCTYPEName, input);
                    },
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        self.createDoctype();
                        try self.current_doctype.name.push('\u{FFFD}');
                        self.setStateAndAdvance(.DOCTYPEName, input);
                    },
                    '>' => {
                        self.handleError(.MissingDOCTYPEName);
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
                    self.handleError(.EofInDOCTYPE);
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
                        self.nextChar(input);
                    },
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_doctype.name.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    else => {
                        try self.current_doctype.name.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-name-state
            .AfterDOCTYPEName => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        self.nextChar(input);
                    },
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        if (self.match_insensitive(input, "PUBLIC")) {
                            if (!self.is_eof) self.preprocessChar(input, &self.ch);
                            self.state = .AfterDOCTYPEPublicKeyword;
                        } else if (self.match_insensitive(input, "SYSTEM")) {
                            if (!self.is_eof) self.preprocessChar(input, &self.ch);
                            self.state = .AfterDOCTYPESystemKeyword;
                        } else {
                            self.handleError(.InvalidCharacterSequenceAfterDOCTYPEName);
                            self.current_doctype.force_quirks = true;
                            self.state = .BogusDOCTYPE;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-keyword-state
            .AfterDOCTYPEPublicKeyword => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeDOCTYPEPublicIdentifier, input),
                    '"' => {
                        self.handleError(.MissingWhitespaceAfterDOCTYPEPublicKeyword);
                        self.current_doctype.public_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        self.handleError(.MissingWhitespaceAfterDOCTYPEPublicKeyword);
                        self.current_doctype.public_id.clear();
                        self.setStateAndAdvance(.DOCTYPEPublicIdentifierSingleQuoted, input);
                    },
                    '>' => {
                        self.handleError(.MissingDOCTYPEPublicIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        self.handleError(.MissingQuoteBeforeDOCTYPEPublicIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-public-identifier-state
            .BeforeDOCTYPEPublicIdentifier => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => {
                        // Ignore.
                        self.nextChar(input);
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
                        self.handleError(.MissingDOCTYPEPublicIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        self.handleError(.MissingQuoteBeforeDOCTYPEPublicIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.BogusDOCTYPE, input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(double-quoted)-state
            .DOCTYPEPublicIdentifierDoubleQuoted => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '"' => self.setStateAndAdvance(.AfterDOCTYPEPublicIdentifier, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_doctype.public_id.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    '>' => {
                        self.handleError(.AbruptDOCTYPEPublicIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.public_id.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(single-quoted)-state
            .DOCTYPEPublicIdentifierSingleQuoted => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\'' => self.setStateAndAdvance(.AfterDOCTYPEPublicIdentifier, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_doctype.public_id.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    '>' => {
                        self.handleError(.AbruptDOCTYPEPublicIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.public_id.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-identifier-state
            .AfterDOCTYPEPublicIdentifier => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
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
                        self.handleError(.MissingWhitespaceBetweenDOCTYPEPublicAndSystemIdentifiers);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        self.handleError(.MissingWhitespaceBetweenDOCTYPEPublicAndSystemIdentifiers);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierSingleQuoted, input);
                    },
                    else => {
                        self.handleError(.MissingQuoteBeforeDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#between-doctype-public-and-system-identifiers-state
            .BetweenDOCTYPEPublicAndSystemIdentifiers => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.nextChar(input),
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
                        self.handleError(.MissingQuoteBeforeDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-keyword-state
            .AfterDOCTYPESystemKeyword => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.setStateAndAdvance(.BeforeDOCTYPESystemIdentifier, input),
                    '"' => {
                        self.handleError(.MissingWhitespaceAfterDOCTYPESystemKeyword);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierDoubleQuoted, input);
                    },
                    '\'' => {
                        self.handleError(.MissingWhitespaceAfterDOCTYPESystemKeyword);
                        self.current_doctype.system_id.clear();
                        self.setStateAndAdvance(.DOCTYPESystemIdentifierSingleQuoted, input);
                    },
                    '>' => {
                        self.handleError(.MissingDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        self.handleError(.MissingQuoteBeforeDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-system-identifier-state
            .BeforeDOCTYPESystemIdentifier => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.nextChar(input),
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
                        self.handleError(.MissingQuoteBeforeDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.state = .BogusDOCTYPE;
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            .DOCTYPESystemIdentifierDoubleQuoted => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '"' => self.setStateAndAdvance(.AfterDOCTYPESystemIdentifier, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_doctype.system_id.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    '>' => {
                        self.handleError(.AbruptDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.system_id.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(single-quoted)-state
            .DOCTYPESystemIdentifierSingleQuoted => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\'' => self.setStateAndAdvance(.AfterDOCTYPESystemIdentifier, input),
                    0x0000 => {
                        self.handleError(.UnexpectedNullCharacter);
                        try self.current_doctype.system_id.push('\u{FFFD}');
                        self.nextChar(input);
                    },
                    '>' => {
                        self.handleError(.AbruptDOCTYPESystemIdentifier);
                        self.current_doctype.force_quirks = true;
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        try self.current_doctype.system_id.push(ch);
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-identifier-state
            .AfterDOCTYPESystemIdentifier => {
                if (is_eof) {
                    self.handleError(.EofInDOCTYPE);
                    self.current_doctype.force_quirks = true;
                    self.emitCurrentDoctype();
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ' => self.nextChar(input),
                    '>' => {
                        self.setStateAndAdvance(.Data, input);
                        self.emitCurrentDoctype();
                    },
                    else => {
                        self.handleError(.UnexpectedCharacterAfterDOCTYPESystemIdentifier);
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
                        self.handleError(.UnexpectedNullCharacter);
                        self.nextChar(input);
                    },
                    else => self.nextChar(input),
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-state
            .CDATASection => {
                if (is_eof) {
                    self.handleError(.EofInCDATA);
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
                    self.handleError(.EofInProcessingInstruction);
                    self.emitEof();
                    return;
                }
                if (ascii.isAsciiAlpha(ch) or ch == '_') self.state = .ProcessingInstructionTarget else {
                    self.handleError(.InvalidFirstCharacterOfProcessingInstructionTarget);
                    self.current_comment = self.temporary_buffer;
                    self.state = .BogusComment;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-target-state
            .ProcessingInstructionTarget => {
                if (is_eof) {
                    self.handleError(.EofInProcessingInstruction);
                    self.emitEof();
                    return;
                }
                switch (ch) {
                    '\t', '\n', '\x0C', ' ', '?', '>' => {
                        var t = try BufferDeque(.utf8, .not_atomic, true).init(self.allocator);
                        try t.pushBack(self.temporary_buffer.clone());
                        if (self.match_insensitive(&t, "xml") or self.match_insensitive(&t, "xml-stylesheet")) {
                            self.handleError(.DisallowedProcessingInstructionTarget);

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
                            self.nextChar(input);
                        } else {
                            self.handleError(.InvaildProcessingInstructionTarget);
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
                    '\t', '\n', '\x0C', ' ' => self.nextChar(input),
                    else => self.state = .ProcessingInstructionData,
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-data-state
            .ProcessingInstructionData => {
                if (is_eof) {
                    self.handleError(.EofInProcessingInstruction);
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
                        self.nextChar(input);
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#processing-instruction-questionable-state
            .ProcessingInstructionQuestionable => {
                if (is_eof) {
                    self.handleError(.EofInProcessingInstruction);
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
                        if (ascii.isAsciiAlphanum(ch) and !is_eof) self.state = .NamedCharacterReference else {
                            try self.flushCodePoints_E();
                            self.state = self.return_state;
                        }
                    },
                }
            },
            //            .CharacterReferenceInData => self.stepCharacterReference(.CharacterReferenceInData, is_eof),
            //
            //            .CharacterReferenceInRCDATA => self.stepCharacterReference(.CharacterReferenceInRCDATA, is_eof),
            //
            //            .CharacterReferenceInAttributeValueSingleQuoted => self.stepCharacterReference(.CharacterReferenceInAttributeValueSingleQuoted, is_eof),
            //
            //            .CharacterReferenceInAttributeValueDoubleQuoted => self.stepCharacterReference(.CharacterReferenceInAttributeValueDoubleQuoted, is_eof),
            //
            //            .CharacterReferenceInAttributeValueUnquoted => self.stepCharacterReference(.CharacterReferenceInAttributeValueUnquoted, is_eof),

            // https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
            .NamedCharacterReference => {
                const res = try self.consumeNamedCharRef(input);

                if (res) |r| {
                    const matched, const is_last_semicolon = r;
                    var invalid_attr_entity = false;

                    if (self.isConsumedAsPartOfAttr() and !is_last_semicolon) {
                        if (input.peekCharN(0)) |next|
                            invalid_attr_entity = next == '=' or ascii.isAsciiAlphanum(next);
                    }

                    if (invalid_attr_entity) {
                        try self.flushCodePoints_E();
                        self.state = self.return_state;
                    } else {
                        if (!is_last_semicolon) self.handleError(.MissingSemicolonAfterCharacterReference);

                        self.temporary_buffer.clear();
                        try self.temporary_buffer.append(matched);
                        try self.flushCodePoints_E();
                        self.state = self.return_state;
                    }
                } else {
                    try self.flushCodePoints_E();
                    self.state = .AmbiguousAmpersand;
                }

                self.peekChar(input);
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#ambiguous-ampersand-state
            .AmbiguousAmpersand => {
                switch (ch) {
                    ';' => {
                        self.handleError(.UnknownNamedCharacterReference);
                        self.state = self.return_state;
                    },
                    else => {
                        if (ascii.isAsciiAlphanum(ch) and !is_eof) {
                            if (self.isConsumedAsPartOfAttr())
                                try self.current_attribute_value.push(ch)
                            else
                                self.emitChar(ch);
                            self.nextChar(input);
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
                    else => {
                        if (ascii.isAsciiDigit(ch) and !is_eof)
                            self.state = .DecimalCharacterReference
                        else {
                            self.handleError(.AbsenceOfDigitsInNumericCharacterReference);
                            try self.flushCodePoints_E();
                            self.state = self.return_state;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-start-state
            .HexadecimalCharacterReferenceStart => {
                if (ascii.isAsciiHexDigit(ch) and !is_eof) self.state = .HexadecimalCharacterReference else {
                    self.handleError(.AbsenceOfDigitsInNumericCharacterReference);
                    try self.flushCodePoints_E();
                    self.state = self.return_state;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-start-state
            .DecimalCharacterReferenceStart => {
                if (ascii.isAsciiDigit(ch) and !is_eof) self.state = .DecimalCharacterReference else {
                    self.handleError(.AbsenceOfDigitsInNumericCharacterReference);
                    try self.flushCodePoints_E();
                    self.state = self.return_state;
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-state
            .HexadecimalCharacterReference => blk: {
                if (ascii.isAsciiDigit(ch) and !is_eof)
                    self.char_ref_code = self.char_ref_code *| 16 +| (ch -| 0x0030)
                else if (ch >= 'A' and ch <= 'F' and !is_eof) self.char_ref_code = self.char_ref_code *| 16 +| (ch -| 0x0037) else if (ch >= 'a' and ch <= 'f' and !is_eof) self.char_ref_code = self.char_ref_code *| 16 +| (ch -| 0x0057) else if (ch == ';') self.state = .NumericCharacterReferenceEnd else {
                    self.handleError(.MissingSemicolonAfterCharacterReference);
                    self.state = .NumericCharacterReferenceEnd;
                    break :blk;
                }
                self.nextChar(input);
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-state
            .DecimalCharacterReference => {
                switch (ch) {
                    ';' => self.setStateAndAdvance(.NumericCharacterReferenceEnd, input),
                    else => {
                        if (ascii.isAsciiDigit(ch) and !is_eof) {
                            self.char_ref_code = self.char_ref_code *| 10 +| (ch -| 0x0030);
                            self.nextChar(input);
                        } else {
                            self.handleError(.MissingSemicolonAfterCharacterReference);
                            self.state = .NumericCharacterReferenceEnd;
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
            .NumericCharacterReferenceEnd => {
                const code = self.char_ref_code;
                if (code == 0x00) {
                    self.handleError(.NullCharacterReference);
                    self.char_ref_code = 0xFFFD;
                } else if (code > 0x10FFFF) {
                    self.handleError(.CharacterReferenceOutsideUnicodeRange);
                    self.char_ref_code = 0xFFFD;
                } else if (ascii.isSurrogate(u64, code)) {
                    self.handleError(.SurrogateCharacterReference);
                    self.char_ref_code = 0xFFFD;
                } else if (ascii.isNoneCharacter(u64, code)) {
                    self.handleError(.NoncharacterCharacterReference);
                } else if (code == 0x0D or (ascii.isControlCharacter(u64, code) and !ascii.isAsciiWhitespace(u64, code))) {
                    self.handleError(.ControlCharacterReference);
                    self.setCodePoint();
                }

                self.temporary_buffer.clear();
                try self.temporary_buffer.push(@intCast(self.char_ref_code));
                try self.flushCodePoints_E();
                self.state = self.return_state;
            },
        }
    }
}
