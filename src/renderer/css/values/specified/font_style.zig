const Stream = @import("../../syntax/ComponentValueStream.zig");
const angle = @import("angle.zig");
const Angle = angle.Angle;

/// https://www.w3.org/TR/css-fonts-4/#font-style-prop
pub const FontStyle = union(enum) {
    normal,
    italic,
    left,
    right,
    oblique: Angle,
};

pub fn parse(input: *Stream) ?FontStyle {
    const name = input.consumeIdent() orelse return null;
    inline for (.{ "normal", "italic", "left", "right" }) |keyword| {
        if (name.eqlAscii(keyword)) return @unionInit(FontStyle, keyword, {});
    }
    if (!name.eqlAscii("oblique")) return null;

    input.discardWhitespace();
    const slant = angle.parse(input) orelse Angle{ .value = 14, .unit = .deg };
    if (!(slant.degrees() >= -90 and slant.degrees() <= 90)) return null;
    return .{ .oblique = slant };
}
