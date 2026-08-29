const std = @import("std");
const testing = std.testing;
const u8_buffer = @import("../../utils/u8_buffer.zig");
const strale = @import("strale");
const LocalName = @import("local_name").LocalName;
const LocalTag = @import("local_name").LocalTag;
const StraleUtf8Global = strale.StraleUtf8Global;
const BufferDeque = strale.BufferDeque;
const Namespace = @import("../../dom/namespace.zig").Namespace;
const Attr = @import("../../dom/Attr.zig");
const Attrs = @import("../../dom/Attrs.zig");
const dom_type = @import("../../dom/type.zig");
const ShadowRootMode = @import("../../dom/ShadowRoot.zig").ShadowRootMode;
const SlotAssignment = @import("../../dom/ShadowRoot.zig").ShadowRootSlotAssignment;

const ids = @import("ids.zig");

pub const Attribute = struct {
    name: LocalName,
    value: StraleUtf8Global,
    // These fields will only be used during the treebuilder stage.
    namespace: ?Namespace = null,
    prefix: ?LocalName = null,

    pub fn deinit(self: *Attribute) void {
        self.name.deinit();
        if (self.prefix) |*prefix| prefix.deinit();
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

    pub fn isQuirksDoctype(self: *const Doctype) bool {
        if (self.force_quirks) return true;

        if (!self.name.eqlIgnoreCase("html")) return true;

        if (self.public_id.isEmpty()) return false;

        if (self.system_id.eqlIgnoreCase("http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd")) return true;

        const pub_slice = self.public_id.slice();
        const first_char = std.ascii.toLower(pub_slice[0]);
        if (first_char != '+' and first_char != '-' and first_char != 'h') {
            return false;
        }

        for (ids.EXACT_PUBLIC_IDS) |target| {
            if (self.public_id.eqlIgnoreCase(target)) return true;
        }

        for (ids.PREFIX_PUBLIC_IDS) |prefix| {
            if (self.public_id.startsWith(prefix, true)) return true;
        }

        if (self.system_id.isEmpty()) {
            for (ids.CONDITIONAL_PREFIX_PUBLIC_IDS) |prefix| {
                if (self.public_id.startsWith(prefix, true)) return true;
            }
        }

        return false;
    }

    pub fn isLimitedQuirksDoctype(self: *const Doctype) bool {
        for (ids.LIMITED_QUIRKS_PUBLIC_IDS) |prefix| {
            if (self.public_id.startsWith(prefix, true)) return true;
        }

        if (!self.system_id.isEmpty()) {
            for (ids.LIMITED_QUIRKS_CONDITIONAL_PUBLIC_IDS) |prefix| {
                if (self.public_id.startsWith(prefix, true)) return true;
            }
        }

        return false;
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
        self: *const Tag,
        name: []const u8,
        value: []const u8,
        is_sensitive: bool,
    ) bool {
        const target = LocalName.fromSlice(name) catch return false;

        for (self.attrs.items) |attr| {
            if (!attr.name.eql(target)) continue;

            const attr_value = attr.value.slice();
            if (is_sensitive) return std.mem.eql(u8, attr_value, value) else return std.ascii.eqlIgnoreCase(attr_value, value);
        }

        return false;
    }

    pub fn hasAttrName(
        self: *const Tag,
        name: []const u8,
    ) bool {
        const target = LocalName.fromSlice(name) catch @panic("OutOfMemory");

        for (self.attrs.items) |attr| {
            if (attr.name.eql(target)) return true;
        }

        return false;
    }

    pub fn getAttrVal(self: *const Tag, name: []const u8) ?StraleUtf8Global {
        const target = LocalName.fromSlice(name) catch @panic("OutOfMemory");

        for (self.attrs.items) |attr| {
            if (attr.name.eql(target)) return attr.value;
        }

        return null;
    }

    pub fn shadowRootMode(self: *const Tag) ShadowRootMode {
        const val = self.getAttrVal("shadowrootmode") orelse return .SRM_None;
        if (val.eqlIgnoreCase("open")) return .SRM_Open;
        if (val.eqlIgnoreCase("closed")) return .SRM_Closed;
        return .SRM_None;
    }

    pub fn shadowRootSlotAssignment(self: *const Tag) SlotAssignment {
        const val = self.getAttrVal("shadowrootslotassignment") orelse return .SR_Named;
        if (val.eqlIgnoreCase("named")) return .SR_Named;
        if (val.eqlIgnoreCase("manual")) return .SR_Manual;
        return .SR_Named;
    }

    // https://html.spec.whatwg.org/multipage/parsing.html#adjust-mathml-attributes
    pub fn adjustMathMLAttributes(self: *Tag) void {
        for (self.attrs.items) |*attr| {
            if (std.mem.eql(u8, attr.name.slice(), "definitionurl")) {
                attr.name.deinit();
                attr.name = LocalName.fromTag(.definitionURL);
            }
        }
    }

    pub fn adjustSVGTagName(self: *Tag) void {
        const adjusted = svg_element_name_map.get(self.name.slice());
        if (adjusted) |name| self.name = LocalName.fromTag(name);
    }

    // https://html.spec.whatwg.org/multipage/parsing.html#adjust-svg-attributes
    pub fn adjustSVGAttributes(self: *Tag) void {
        for (self.attrs.items) |*attr| {
            if (svg_attribute_map.get(attr.name.slice())) |adjusted| {
                attr.name.deinit();
                attr.name = LocalName.fromSlice(adjusted) catch @panic("out of memory");
            }
        }
    }

    // https://html.spec.whatwg.org/multipage/parsing.html#adjust-foreign-attributes
    pub fn adjustForeignAttributes(self: *Tag) void {
        for (self.attrs.items) |*attr| {
            if (foreign_attribute_map.get(attr.name.slice())) |adjusted| {
                attr.name.deinit();
                attr.name = LocalName.fromTag(adjusted.local_name);
                attr.namespace = adjusted.namespace;
                attr.prefix = if (adjusted.prefix) |prefix| LocalName.fromTag(prefix) else null;
            }
        }
    }

    pub fn isForeignContentBreakout(tag: *const Tag) bool {
        if (tag.kind == .EndTag) return tag.name.is(.br) or tag.name.is(.p);
        if (tag.name.is(.font))
            return tag.hasAttrName("color") or tag.hasAttrName("face") or tag.hasAttrName("size");
        return tag.name.oneOf(&.{
            .b,       .big,   .blockquote, .body,   .br,     .center, .code, .dd,
            .div,     .dl,    .dt,         .em,     .embed,  .h1,     .h2,   .h3,
            .h4,      .h5,    .h6,         .head,   .hr,     .i,      .img,  .li,
            .listing, .menu,  .meta,       .nobr,   .ol,     .p,      .pre,  .ruby,
            .s,       .small, .span,       .strong, .strike, .sub,    .sup,  .table,
            .tt,      .u,     .ul,         .@"var",
        });
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

const svg_element_name_map = std.StaticStringMap(LocalTag).initComptime(.{
    .{ "altglyph", .altGlyph },
    .{ "altglyphdef", .altGlyphDef },
    .{ "altglyphitem", .altGlyphItem },
    .{ "animatecolor", .animateColor },
    .{ "animatemotion", .animateMotion },
    .{ "animatetransform", .animateTransform },
    .{ "clippath", .clipPath },
    .{ "feblend", .feBlend },
    .{ "fecolormatrix", .feColorMatrix },
    .{ "fecomponenttransfer", .feComponentTransfer },
    .{ "fecomposite", .feComposite },
    .{ "feconvolvematrix", .feConvolveMatrix },
    .{ "fediffuselighting", .feDiffuseLighting },
    .{ "fedisplacementmap", .feDisplacementMap },
    .{ "fedistantlight", .feDistantLight },
    .{ "fedropshadow", .feDropShadow },
    .{ "feflood", .feFlood },
    .{ "fefunca", .feFuncA },
    .{ "fefuncb", .feFuncB },
    .{ "fefuncg", .feFuncG },
    .{ "fefuncr", .feFuncR },
    .{ "fegaussianblur", .feGaussianBlur },
    .{ "feimage", .feImage },
    .{ "femerge", .feMerge },
    .{ "femergenode", .feMergeNode },
    .{ "femorphology", .feMorphology },
    .{ "feoffset", .feOffset },
    .{ "fepointlight", .fePointLight },
    .{ "fespecularlighting", .feSpecularLighting },
    .{ "fespotlight", .feSpotLight },
    .{ "fetile", .feTile },
    .{ "feturbulence", .feTurbulence },
    .{ "foreignobject", .foreignObject },
    .{ "glyphref", .glyphRef },
    .{ "lineargradient", .linearGradient },
    .{ "radialgradient", .radialGradient },
    .{ "textpath", .textPath },
});

const svg_attribute_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "attributename", "attributeName" },
    .{ "attributetype", "attributeType" },
    .{ "basefrequency", "baseFrequency" },
    .{ "baseprofile", "baseProfile" },
    .{ "calcmode", "calcMode" },
    .{ "clippathunits", "clipPathUnits" },
    .{ "diffuseconstant", "diffuseConstant" },
    .{ "edgemode", "edgeMode" },
    .{ "filterunits", "filterUnits" },
    .{ "glyphref", "glyphRef" },
    .{ "gradienttransform", "gradientTransform" },
    .{ "gradientunits", "gradientUnits" },
    .{ "kernelmatrix", "kernelMatrix" },
    .{ "kernelunitlength", "kernelUnitLength" },
    .{ "keypoints", "keyPoints" },
    .{ "keysplines", "keySplines" },
    .{ "keytimes", "keyTimes" },
    .{ "lengthadjust", "lengthAdjust" },
    .{ "limitingconeangle", "limitingConeAngle" },
    .{ "markerheight", "markerHeight" },
    .{ "markerunits", "markerUnits" },
    .{ "markerwidth", "markerWidth" },
    .{ "maskcontentunits", "maskContentUnits" },
    .{ "maskunits", "maskUnits" },
    .{ "numoctaves", "numOctaves" },
    .{ "pathlength", "pathLength" },
    .{ "patterncontentunits", "patternContentUnits" },
    .{ "patterntransform", "patternTransform" },
    .{ "patternunits", "patternUnits" },
    .{ "pointsatx", "pointsAtX" },
    .{ "pointsaty", "pointsAtY" },
    .{ "pointsatz", "pointsAtZ" },
    .{ "preservealpha", "preserveAlpha" },
    .{ "preserveaspectratio", "preserveAspectRatio" },
    .{ "primitiveunits", "primitiveUnits" },
    .{ "refx", "refX" },
    .{ "refy", "refY" },
    .{ "repeatcount", "repeatCount" },
    .{ "repeatdur", "repeatDur" },
    .{ "requiredextensions", "requiredExtensions" },
    .{ "requiredfeatures", "requiredFeatures" },
    .{ "specularconstant", "specularConstant" },
    .{ "specularexponent", "specularExponent" },
    .{ "spreadmethod", "spreadMethod" },
    .{ "startoffset", "startOffset" },
    .{ "stddeviation", "stdDeviation" },
    .{ "stitchtiles", "stitchTiles" },
    .{ "surfacescale", "surfaceScale" },
    .{ "systemlanguage", "systemLanguage" },
    .{ "tablevalues", "tableValues" },
    .{ "targetx", "targetX" },
    .{ "targety", "targetY" },
    .{ "textlength", "textLength" },
    .{ "viewbox", "viewBox" },
    .{ "viewtarget", "viewTarget" },
    .{ "xchannelselector", "xChannelSelector" },
    .{ "ychannelselector", "yChannelSelector" },
    .{ "zoomandpan", "zoomAndPan" },
});

pub const ForeignAttrEntry = struct {
    prefix: ?LocalTag,
    local_name: LocalTag,
    namespace: Namespace,
};

const foreign_attribute_map =
    std.StaticStringMap(ForeignAttrEntry).initComptime(.{
        .{ "xlink:actuate", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .actuate,
            .namespace = .NS_XLink,
        } },
        .{ "xlink:arcrole", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .arcrole,
            .namespace = .NS_XLink,
        } },
        .{ "xlink:href", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .href,
            .namespace = .NS_XLink,
        } },
        .{ "xlink:role", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .role,
            .namespace = .NS_XLink,
        } },
        .{ "xlink:show", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .show,
            .namespace = .NS_XLink,
        } },
        .{ "xlink:title", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .title,
            .namespace = .NS_XLink,
        } },
        .{ "xlink:type", ForeignAttrEntry{
            .prefix = .xlink,
            .local_name = .type,
            .namespace = .NS_XLink,
        } },
        .{ "xml:lang", ForeignAttrEntry{
            .prefix = .xml,
            .local_name = .lang,
            .namespace = .NS_Xml,
        } },
        .{ "xml:space", ForeignAttrEntry{
            .prefix = .xml,
            .local_name = .space,
            .namespace = .NS_Xml,
        } },
        .{ "xmlns", ForeignAttrEntry{
            .prefix = null,
            .local_name = .xmlns,
            .namespace = .NS_Xmlns,
        } },
        .{ "xmlns:xlink", ForeignAttrEntry{
            .prefix = .xmlns,
            .local_name = .xlink,
            .namespace = .NS_Xmlns,
        } },
    });
