const TreeBuilder = @This();

const std = @import("std");
const Token = @import("../tokenizer/token.zig").Token;
const Node = @import("../../dom/Node.zig");
const Element = @import("../../dom/Element.zig");
const ns = @import("../../dom/namespace.zig");

const InsertionMode = enum {
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

const ScriptingMode = enum {
    Normal,
    Disabled,
    Inert,
    Fragment,
};

open_elements: std.ArrayList(Element),
// InsertionMode
insert_mode: InsertionMode,
// Original Insertion Mode
orig_insert_mode: InsertionMode,
// Template Insertion Mode
temp_insert_modes: std.ArrayList(InsertionMode),
fragment_case: bool,
scripting_mode: ScriptingMode,
foster_parenting: bool,
frameset_ok: bool,

pub fn init() TreeBuilder {
    return TreeBuilder{
        .insert_mode = .Initial,
        .orig_insert_mode = .Initial,
        .temp_insert_modes = .empty,
        .fragment_case = false,
        .scripting_mode = .Normal,
        .foster_parenting = false,
        .frameset_ok = false,
    };
}

// Implement TokenIngester.
pub fn handleToken(self: *TreeBuilder, tk: Token) void {
    // Dispatch token.
    if (self.isForeign(tk)) {
        self.processTokenForeign(tk);
    } else {
        self.processToken(tk);
    }
}

// https://html.spec.whatwg.org/#tree-construction-dispatcher
pub fn isForeign(self: TreeBuilder, tk: Token) bool {
    if (self.open_elements.items.len == 0 or std.meta.activeTag(tk) == .EofToken) return false;
    const cur_el = self.adjustedCurrentNode();

    if (cur_el.ns == .NS_Html) return false;

    if (cur_el.isMathMLTextIntegrationPoint()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and !tag.name.cmp("mglyph") and !tag.name.cmp("malignmark")) return false;
            },
            .CharacterToken => return false,
            else => {},
        }
    }

    if (cur_el.isMathMLAnnotationXml()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and tag.name.cmp("svg")) return false;
            },
            else => {},
        }
    }

    if (cur_el.isHtmlIntegrationPoint()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag) return false;
            },
            .CharacterToken => return false,
        }
    }

    return true;
}

pub fn processToken(self: TreeBuilder, tk: Token) void {
    _ = self;
    _ = tk;
}

pub fn processTokenForeign(self: TreeBuilder, tk: Token) void {
    _ = self;
    _ = tk;
}

pub fn adjustedCurrentNode(self: TreeBuilder) *Node {
    if (self.open_elements.last()) |node| return node else @panic("Stack of open elements is empty.");
}
