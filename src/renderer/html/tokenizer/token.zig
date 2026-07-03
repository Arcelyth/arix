const std = @import("std");

const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

const DoctypeToken = struct {
    name: ?[]const u8,
    // public identifier
    public_ident: ?[]const u8,
    // system identifier
    sys_ident: ?[]const u8,
    force_quirks: bool,
};

const StartToken = struct {
    tag_name: []const u8,    
    self_closing: bool, 
    attrs: []Attribute,
};

const EndToken = struct {
    tag_name: []const u8,    
    self_closing: bool, 
    attrs: []Attribute,
};

const CommentToken = struct {
    data: []const u8,
};

const CharacterToken = struct {
    data: u8,
};

const TokenTag = enum {
    DoctypeToken,    
    StartToken,
    EndToken,
    CommentToken,
    CharacterToken,
    EofToken,
};

const Token = union(TokenTag) {
    DoctypeToken: DoctypeToken,
    StartToken: StartToken,
    EndToken: EndToken,
    CommentToken: CommentToken,
    CharacterToken: CharacterToken,
    EofToken,
};



