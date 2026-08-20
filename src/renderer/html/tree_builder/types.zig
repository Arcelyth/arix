const Element = @import("../../dom/Element.zig");
const Node = @import("../../dom/Node.zig");

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

pub const InsertionLocation = union {
    last_child: *Node,
    before_child: *Node,
    parent_before_child: struct {
        parent: *Node,
        before_child: *Node,
    },

    pub fn getParent(self: *InsertionLocation) *Node {
        return switch (self) {
            .last_child => |parent| parent,
            .before_child => |before| before.parent orelse @panic("before_child has no parent"),
            .parent_before_child => |loc| loc.parent,
        };
    }

    pub fn beforeNode(self: InsertionLocation) ?*Node {
        const before = switch (self) {
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
};

pub const ActiveFormatElement = union(enum) {
    AFE_Element: *Element,
    AFE_Marker,
};
