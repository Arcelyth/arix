const std = @import("std");
const ascii = @import("utils").ascii;

pub const AttrName = enum(u2) {
    HttpEquiv,
    Content,
    Charset,
};

pub const Attr = struct {
    name: []const u8,
    value: []const u8,
};

pub const attr_name_map = std.StaticStringMap(AttrName).initComptime(.{
    .{ "http-equiv", .HttpEquiv },
    .{ "content", .Content },
    .{ "charset", .Charset },
});

/// https://html.spec.whatwg.org/multipage/parsing.html#concept-get-attributes-when-sniffing
pub fn get_attr(input: []const u8, i: *usize, l: usize) struct { ?Attr, usize } {
    while (i.* < l) {
        const c = input[i.*];
        if (ascii.isHtmlSpace(c) or c == 0x2F) {
            i.* += 1;
            continue;
        }
        if (c == 0x3E) {
            return .{ null, i.* };
        }
        break;
    }
    if (i.* >= l) {
        return .{ null, i.* };
    }

    const n_start = i.*;
    var n_end: usize = 0;
    var have_n_end = false;
    while (i.* < l) {
        var c = input[i.*];
        if (c == 0x3D) { // '='
            n_end = i.*;
            have_n_end = true;
            i.* += 1;
            break;
        }
        if (ascii.isHtmlSpace(c)) {
            n_end = i.*;
            have_n_end = true;
            i.* += 1;
            while (i.* < l) {
                c = input[i.*];
                if (ascii.isHtmlSpace(c)) {
                    i.* += 1;
                    continue;
                }
                if (c != 0x3D) {
                    return .{ Attr{ .name = input[n_start..n_end], .value = "" }, i.* };
                }
                i.* += 1;
                break;
            }
            break;
        }
        // '/', '>'
        if (c == 0x2F or c == 0x3E) {
            n_end = i.*;
            have_n_end = true;

            return .{ Attr{ .name = input[n_start..n_end], .value = "" }, i.* };
        }
        i.* += 1;
    }
    if (!have_n_end) {
        n_end = i.*;
    }
    if (n_end < n_start) {
        n_end = n_start;
    }
    while (i.* < l and ascii.isHtmlSpace(input[i.*])) {
        i.* += 1;
    }
    if (i.* >= l) {
        return .{ Attr{ .name = input[n_start..n_end], .value = "" }, i.* };
    }

    var v_start = i.*;
    var v_end: usize = 0;
    var have_v_end = false;

    var c = input[i.*];
    if (c == 0x22 or c == 0x27) {
        const quote = c;
        i.* += 1;
        v_start = i.*;
        while (i.* < l) {
            if (input[i.*] == quote) {
                v_end = i.*;
                have_v_end = true;
                i.* += 1;
                break;
            }
            i.* += 1;
        }
        if (!have_v_end) {
            v_end = i.*;
        }
    } else if (c == 0x3E) { // '>'
        return .{ Attr{ .name = input[n_start..n_end], .value = "" }, i.* };
    } else {
        while (i.* < l) {
            c = input[i.*];
            if (ascii.isHtmlSpace(c) or c == 0x3E) {
                break;
            }
            i.* += 1;
        }
        v_end = i.*;
        have_v_end = true;
    }

    return .{ Attr{ .name = input[n_start..n_end], .value = input[v_start..v_end] }, i.* };
}
