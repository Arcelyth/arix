pub const Namespace = enum {
    NS_Html,
    NS_Math,
    NS_Svg,
    NS_XLink,
    NS_Xml,
    NS_Xmlns,

    pub const Html = "http://www.w3.org/1999/xhtml";
    pub const Math = "http://www.w3.org/1998/Math/MathML";
    pub const Svg = "http://www.w3.org/2000/svg";
    pub const XLink = "http://www.w3.org/1999/xlink";
    pub const Xml = "http://www.w3.org/XML/1998/namespace";
    pub const Xmlns = "http://www.w3.org/2000/xmlns/";

    pub inline fn toStr(self: Namespace) []const u8 {
        return switch (self) {
            .NS_Html => Html,
            .NS_Math => Math,
            .NS_Svg => Svg,
            .NS_XLink => XLink,
            .NS_Xml => Xml,
            .NS_Xmlns => Xmlns,
        };
    }
};
