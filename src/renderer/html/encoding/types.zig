pub const Confidence = enum(u1) {
    Certain,
    Tentative,
};

pub const EncodingOptions = struct {
    override_encoding: ?[]const u8,
    transport_encoding: ?[]const u8,
    parent_encoding: ?[]const u8,
    likely_encoding: ?[]const u8,
    default_encoding: ?[]const u8,
    same_origin_with_parent: bool,
};
