pub const Namespace = enum {
    NS_Html,
    NS_Math,
    NS_Svg,
    NS_XLink,
    NS_Xml,
    NS_XmlNS,
};

pub fn namespaceToStr(ns: Namespace) []const u8 {
    return switch (ns) {
        .NS_Html => "http://www.w3.org/1999/xhtml",
        .NS_Math => "http://www.w3.org/1998/Math/MathML",
        .NS_Svg => "http://www.w3.org/2000/svg",
        .NS_XLink => "http://www.w3.org/1999/xlink",
        .NS_Xml => "http://www.w3.org/XML/1998/namespace",
        .NS_XmlNS => "http://www.w3.org/2000/xmlns/",
    };
}
