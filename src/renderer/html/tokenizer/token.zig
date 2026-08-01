const std = @import("std");
const testing = std.testing;
const u8_buffer = @import("../../utils/u8_buffer.zig");
const strale = @import("strale");
const LocalName = @import("local_name").LocalName;
const StraleUtf8Global = strale.StraleUtf8Global;
const BufferDeque = strale.BufferDeque;

pub const Attribute = struct {
    name: LocalName,
    value: StraleUtf8Global,

    pub fn deinit(self: *Attribute) void {
        self.name.deinit();
        self.value.deinit();
    }

    pub fn format(self: Attribute, writer: anytype) !void {
        try writer.print("Attribute's name: {f}, value: {s}\n", .{ self.name, self.value.slice() });
    }
};

pub const Doctype = struct {
    name: StraleUtf8Global,
    // public identifier
    public_id: StraleUtf8Global,
    // system identifier
    system_id: StraleUtf8Global,
    force_quirks: bool,

    pub fn init() Doctype {
        return Doctype{
            .name = StraleUtf8Global.initEmpty(),
            .public_id = StraleUtf8Global.initEmpty(),
            .system_id = StraleUtf8Global.initEmpty(),
            .force_quirks = false,
        };
    }

    pub fn deinit(self: *Doctype) void {
        self.name.deinit();
        self.public_id.deinit();
        self.system_id.deinit();
    }

    pub fn format(self: Doctype, writer: anytype) !void {
        try writer.print("Doctype's name: {s}, public_id: {s}, system_id: {s}, force_quirks: {}\n", .{ self.name.slice(), self.public_id.slice(), self.system_id.slice(), self.force_quirks });
    }
};

pub const TagKind = enum {
    StartTag,
    EndTag,
};

pub const Tag = struct {
    kind: TagKind,
    name: LocalName,
    self_closing: bool,
    attrs: std.ArrayList(Attribute),

    pub fn hasAttr(
        self: Tag,
        name: []const u8,
        value: []const u8,
        is_sensitive: bool,
    ) bool {
        const target = LocalName.fromSlice(name);

        for (self.attrs.items) |attr| {
            if (!attr.name.eql(target)) continue;

            const attr_value = attr.value.slice();
            if (is_sensitive) return std.mem.eql(u8, attr_value, value) else return std.ascii.eqlIgnoreCase(attr_value, value);
        }

        return false;
    }
};

pub const ProcessingInstruction = struct {
    target: StraleUtf8Global,
    data: StraleUtf8Global,

    pub fn init() ProcessingInstruction {
        return ProcessingInstruction{ .target = StraleUtf8Global.initEmpty(), .data = StraleUtf8Global.initEmpty() };
    }

    pub fn deinit(self: *ProcessingInstruction) void {
        self.target.deinit();
        self.data.deinit();
    }
};

pub const TokenTag = enum {
    UndefinedToken,
    DoctypeToken,
    TagToken,
    CommentToken,
    CharacterToken,
    EofToken,
    ProcessingInstructionToken,
};

pub const Token = union(TokenTag) {
    UndefinedToken,
    DoctypeToken: Doctype,
    TagToken: Tag,
    CommentToken: StraleUtf8Global,
    CharacterToken: StraleUtf8Global,
    EofToken,
    ProcessingInstructionToken: ProcessingInstruction,

    pub fn deinit(self: *Token, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .UndefinedToken => {},

            .EofToken => {},

            .DoctypeToken => |*doctype| {
                doctype.deinit();
            },

            .TagToken => |*tag| {
                tag.name.deinit();
                for (tag.attrs.items) |*attr| {
                    attr.deinit();
                }
                tag.attrs.deinit(alloc);
            },

            .CommentToken => |*comment| {
                comment.deinit();
            },

            .CharacterToken => |*character| {
                character.deinit();
            },

            .ProcessingInstructionToken => |*pi| {
                pi.deinit();
            },
        }

        self.* = .UndefinedToken;
    }

    pub fn format(
        self: Token,
        writer: anytype,
    ) !void {
        switch (self) {
            .UndefinedToken => try writer.writeAll("UndefinedToken"),
            .EofToken => try writer.writeAll("EofToken"),
            .DoctypeToken => |doctype| {
                try writer.print(
                    "DoctypeToken{{ name=\"{s}\", public_id=\"{s}\", system_id=\"{s}\", force_quirks={} }}",
                    .{
                        doctype.name.slice(),
                        doctype.public_id.slice(),
                        doctype.system_id.slice(),
                        doctype.force_quirks,
                    },
                );
            },

            .TagToken => |tag| {
                try writer.print(
                    "TagToken{{ kind={s}, name=\"{f}\", self_closing={}, attrs=[",
                    .{
                        @tagName(tag.kind),
                        tag.name,
                        tag.self_closing,
                    },
                );

                for (tag.attrs.items, 0..) |attr, i| {
                    if (i != 0) {
                        try writer.writeAll(", ");
                    }

                    try writer.print(
                        "{{name=\"{f}\", value=\"{s}\"}}",
                        .{
                            attr.name,
                            attr.value.slice(),
                        },
                    );
                }

                try writer.writeAll("] }");
            },

            .CommentToken => |comment| {
                try writer.print(
                    "CommentToken{{ \"{s}\" }}",
                    .{comment.slice()},
                );
            },

            .CharacterToken => |character| {
                try writer.print(
                    "CharacterToken{{ \"{s}\" }}",
                    .{character.slice()},
                );
            },

            .ProcessingInstructionToken => |pi| {
                try writer.print(
                    "ProcessingInstructionToken{{ target=\"{s}\", data=\"{s}\" }}",
                    .{
                        pi.target.slice(),
                        pi.data.slice(),
                    },
                );
            },
        }
    }
};

pub fn expectToken(expected: Token, actual: Token) !void {
    const expected_tag = std.meta.activeTag(expected);
    const actual_tag = std.meta.activeTag(actual);
    try testing.expectEqual(expected_tag, actual_tag);
    switch (expected) {
        .UndefinedToken, .EofToken => {},

        .DoctypeToken => |exp_doc| {
            const act_doc = actual.DoctypeToken;
            try testing.expectEqualSlices(u8, exp_doc.name.slice(), act_doc.name.slice());
            try testing.expectEqualSlices(u8, exp_doc.public_id.slice(), act_doc.public_id.slice());
            try testing.expectEqualSlices(u8, exp_doc.system_id.slice(), act_doc.system_id.slice());
            try testing.expectEqual(exp_doc.force_quirks, act_doc.force_quirks);
        },

        .TagToken => |exp_tag| {
            const act_tag = actual.TagToken;
            try testing.expectEqual(exp_tag.kind, act_tag.kind);
            try testing.expect(exp_tag.name.eql(act_tag.name));

            // Ignore end tag's attributes and self_closing.
            if (exp_tag.kind == .EndTag) return;

            try testing.expectEqual(exp_tag.self_closing, act_tag.self_closing);
            try testing.expectEqual(exp_tag.attrs.items.len, act_tag.attrs.items.len);
            for (exp_tag.attrs.items, act_tag.attrs.items) |exp_attr, act_attr| {
                try testing.expect(exp_attr.name.eql(act_attr.name));
                try testing.expectEqualSlices(u8, exp_attr.value.slice(), act_attr.value.slice());
            }
        },

        .CommentToken => |exp_comment| {
            try testing.expectEqualSlices(u8, exp_comment.slice(), actual.CommentToken.slice());
        },

        .CharacterToken => |exp_char| {
            try testing.expectEqualSlices(u8, exp_char.slice(), actual.CharacterToken.slice());
        },

        .ProcessingInstructionToken => |exp_pi| {
            const act_pi = actual.ProcessingInstructionToken;
            try testing.expectEqualSlices(u8, exp_pi.target.slice(), act_pi.target.slice());
            try testing.expectEqualSlices(u8, exp_pi.data.slice(), act_pi.data.slice());
        },
    }
}
