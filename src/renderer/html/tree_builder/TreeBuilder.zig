const TreeBuilder = @This();

const std = @import("std");
const Token = @import("../tokenizer/token.zig").Token;
const Node = @import("../../dom/Node.zig");
const Element = @import("../../dom/Element.zig");
const ns = @import("../../dom/namespace.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

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

const InsertionLocation = union { last_child: *Element, before_child: *Element, parent_before_child: struct {
    parent: *Element,
    before_child: *Element,
} };

const ScriptingMode = enum {
    Normal,
    Disabled,
    Inert,
    Fragment,
};

allocator: std.mem.Allocator,
open_elements: std.ArrayList(*Element),
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

pub fn init(alloc: std.mem.Allocator) TreeBuilder {
    return TreeBuilder{
        .allocator = alloc,
        .open_elements = .empty,
        .insert_mode = .InitialMode,
        .orig_insert_mode = .InitialMode,
        .temp_insert_modes = .empty,
        .fragment_case = false,
        .scripting_mode = .Normal,
        .foster_parenting = false,
        .frameset_ok = false,
    };
}

pub fn deinit(self: *TreeBuilder) void {
    self.open_elements.deinit(self.allocator);
}

/// Implement TokenIngester.
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
                if (tag.kind == .StartTag and !tag.name.eql(.mglyph) and !tag.name.eql(.malignmark)) return false;
            },
            .CharacterToken => return false,
            else => {},
        }
    }

    if (cur_el.isMathMLAnnotationXml()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and tag.name.eql(.svg)) return false;
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

pub fn adjustedCurrentNode(self: *TreeBuilder) *Node {
    if (self.open_elements.getLastOrNull()) |*node| return &node else @panic("Stack of open elements is empty.");
}

pub fn appropriatePlaceForInsertion(self: *TreeBuilder, override_target: ?*Element) InsertionLocation {
    const target = override_target orelse self.currentNode();
    if (self.foster_parenting and target.in(&.{ .table, .tbody, .tfoot, .thead, .tr })) {
        const open_elements = self.open_elements;
        var last_table: ?*Element = null;
        var last_table_pos: usize = 0;
        var idx = open_elements.items.len;
        blk: while (idx > 0) {
            idx -= 1;
            if (open_elements.items[idx].local_name.is(.table)) {
                last_table = self.open_elements.items[idx];
                last_table_pos = idx;
                break :blk;
            }
            if (open_elements.items[idx].local_name.is(.template)) {
                return .{ .last_child = self.open_elements.items[idx] };
            }
        }

        if (last_table) |table| {
            if (table.asNode().parent) |p|
                return .{ .parent_before_child = .{
                    .parent = p.downcast(Element),
                    .before_child = table,
                } }
            else if (last_table_pos > 0)
                return .{ .last_child = self.open_elements.items[last_table_pos - 1] }
            else
                @panic("This should never happen: last_table_pos <= 0");
        } else {
            return .{ .last_child = self.htmlElement() orelse target };
        }
    }
    return .{ .last_child = target };
}

pub fn createElementForToken(self: *TreeBuilder) void {
    _ = self;
}

pub fn adjustedInsertionLocation(self: *TreeBuilder) void {
    _ = self;
}

pub fn insertElementAtAdjustedInsertionLocation(self: *TreeBuilder) void {
    _ = self;
}

pub fn insertForeignElement(self: *TreeBuilder) void {
    _ = self;
}

pub fn insertHtmlElement(self: *TreeBuilder) void {
    _ = self;
}

pub inline fn currentNode(self: *TreeBuilder) *Element {
    if (self.open_elements.items.len == 0) @panic("Empty open elements stack.");
    return self.open_elements.items[self.open_elements.items.len - 1];
}

pub fn lastStackElement(self: *TreeBuilder, elem: LocalTag) ?Element {
    for (self.open_elements.items..0) |idx| {
        if (self.open_elements.items[idx].local_name.is(elem)) {
            return self.open_elements.items[idx];
        }
    }
    return null;
}

pub inline fn htmlElement(self: *TreeBuilder) ?*Element {
    if (self.open_elements.items.len == 0) return null;
    return self.open_elements.items[0];
}
