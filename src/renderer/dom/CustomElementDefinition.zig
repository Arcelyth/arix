// https://html.spec.whatwg.org/#custom-element-definition
const CustomElementDefinition = @This();

const LocalName = @import("local_name").LocalName;

// TODO: Not sure the type.
name: []const u8,
local_name: LocalName,
// constructor:
// observed_attributes
// ...

pub fn init() CustomElementDefinition {
    return .{};
}
