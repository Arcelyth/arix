const std = @import("std");
const Element = @import("../../dom/Element.zig");
const Node = @import("../../dom/Node.zig");
const token_ = @import("../tokenizer/token.zig");
const TokenTag = token_.TokenTag; 
const Tag = token_.Tag;
const ProcessingInstruction =  token_.ProcessingInstruction;
const Doctype = token_.Doctype; 
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

const TokenizerState = @import("../tokenizer/state.zig").TokenizerState;

pub const InsertionMode = enum {
    InitialMode,
    BeforeHtmlMode,
    BeforeHeadMode,
    InHeadMode,
    InHeadNoscriptMode,
    AfterHeadMode,
    InBodyMode,
    TextMode,
    InTableMode,
    InTableTextMode,
    InCaptionMode,
    InColumnGroupMode,
    InTableBodyMode,
    InRowMode,
    InCellMode,
    InTemplateMode,
    AfterBodyMode,
    InFramesetMode,
    AfterFramesetMode,
    AfterAfterBodyMode,
    AfterAfterFramesetMode,
};

pub const InsertionLocation = union(enum) {
    last_child: *Node,
    before_child: *Node,
    parent_before_child: struct {
        parent: *Node,
        before_child: *Node,
    },

    pub fn getParent(self: *const InsertionLocation) *Node {
        return switch (self.*) {
            .last_child => |parent| parent,
            .before_child => |before| before.parent orelse @panic("before_child has no parent"),
            .parent_before_child => |loc| loc.parent,
        };
    }

    pub fn beforeNode(self: *const InsertionLocation) ?*Node {
        const before = switch (self.*) {
            .last_child => |parent| return parent.last_child,
            .before_child => |node| node,
            .parent_before_child => |loc| loc.before_child,
        };

        return before.prev_sibling;
    }
};

pub const ScriptingMode = enum {
    Normal,
    Disabled,
    Inert,
    Fragment,
};

pub const ProcessResult = union(enum) {
    PR_Done,
    PR_ChangeState: TokenizerState,
    PR_AckSelfClosing,
    PR_SplitWhitespace,
    PR_StopParsing,
};

pub const ActiveFormatElement = union(enum) {
    AFE_Element: *Element,
    AFE_Marker,
};

pub const SplitStatus = enum {
    NotSplit,
    Whitespace,
    NotWhitespace,
};

pub const Character = struct {
    split_status: SplitStatus,
    data: StraleUtf8Global,

    pub fn init(data: StraleUtf8Global) Character {
        defer data.deinit();
        return .{
            .split_status = .NotSplit,
            .data = data,
        }; 
    }

    pub fn deinit(self: Character) void {
        self.data.deinit();
    }
};

pub const PendingToken = union(TokenTag) {
    DoctypeToken: Doctype,
    TagToken: Tag,
    CommentToken: StraleUtf8Global,
    CharacterToken: Character,
    EofToken,
    ProcessingInstructionToken: ProcessingInstruction,

    pub fn deinit(self: *PendingToken, alloc: std.mem.Allocator) void {
        switch (self.*) {
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
        self: PendingToken,
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
                    "CharacterToken{{ split_status=\"{s}\", data=\"{s}\" }}",
                    .{@typeName(character.split_status), character.data.slice()},
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
