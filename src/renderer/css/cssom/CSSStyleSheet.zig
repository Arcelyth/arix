//! CSSOM stylesheet state and operations.
//! https://drafts.csswg.org/cssom/#css-style-sheets
const CSSStyleSheet = @This();

const std = @import("std");
const Node = @import("../../dom/Node.zig");
const Document = @import("../../dom/Document.zig");
const CSSRuleList = @import("CSSRuleList.zig");
const MediaList = @import("media/MediaList.zig");

allocator: std.mem.Allocator,

location: ?[]const u8 = null,
parent_style_sheet: ?*CSSStyleSheet = null,
owner_node: ?*Node = null,
owner_rule: ?*const CSSRuleList.Rule = null,
media: MediaList = .{},
title: []const u8 = "",
alternate: bool = false,
disabled: bool = false,
rule_list: CSSRuleList = .{},
origin_clean: bool = false,
constructed: bool = false,
disallow_modification: bool = false,
constructor_document: ?*Document = null,
stylesheet_base_url: ?[]const u8 = null,
