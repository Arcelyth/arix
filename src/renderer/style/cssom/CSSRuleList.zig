const CSSRuleList = @This();

const std = @import("std");
const CSSStyleSheet = @import("CSSStyleSheet.zig");
const syntax = @import("../../css/syntax/parsing_results.zig");

pub const Rule = struct {
    syntax: syntax.Rule,
    parent_style_sheet: ?*CSSStyleSheet,
    parent_rule: ?*Rule = null,

    fn detach(self: *Rule) void {
        self.parent_rule = null;
        self.parent_style_sheet = null;
    }
};

items: std.ArrayList(*Rule) = .empty,
