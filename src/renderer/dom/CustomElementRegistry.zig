const CustomElementRegistry = @This();

const std = @import("std");
const HashSet = @import("../utils/hash_set.zig").HashSet;
const CustomElementDefinition = @import("CustomElementDefinition.zig");
const Document = @import("Document.zig");
const LocalName = @import("local_name").LocalName;

pub const DefKey = struct {
    name: LocalName,
    local_name: LocalName,
};

is_scoped: bool,
// TODO: Need to implement set data structure at first.
scoped_doc_set: HashSet(*Document),
custom_elem_def_set: std.AutoHashMap(DefKey, *CustomElementDefinition),
elem_def_is_running: bool,
//when_defined_promise_map: std.AutoArrayHashMapUnmanaged()

pub fn init() CustomElementRegistry {
    return .{
        .is_scoped = false,
        .scoped_doc_set = HashSet(*Document).init(),
        .elem_def_is_running = HashSet(*CustomElementDefinition).init(),
    };
}

pub fn lookup(
    self: *CustomElementRegistry,
    name: LocalName,
    local_name: LocalName,
) ?*CustomElementDefinition {
    return self.definitions.get(.{
        .name = name,
        .local_name = local_name,
    });
}
