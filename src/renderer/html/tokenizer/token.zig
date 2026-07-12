const std = @import("std");
const u8_buffer = @import("../../utils/u8_buffer.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

pub const Doctype = struct {
    name: ?StraleUtf8Global,
    // public identifier
    public_id: ?StraleUtf8Global,
    // system identifier
    system_id: ?StraleUtf8Global,
    force_quirks: bool,

    pub fn init() Doctype {
        return Doctype {
            .name = StraleUtf8Global.initEmpty(),
            .public_id = StraleUtf8Global.initEmpty(),
            .system_id = StraleUtf8Global.initEmpty(),
            .force_quirks = false,
        };
    } 

    pub fn deinit() void {

        // TODO
    }
};

pub const TagKind = enum {
    StartTag,
    EndTag,
};
