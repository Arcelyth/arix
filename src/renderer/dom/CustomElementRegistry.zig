const CustomElementRegistry = @This();

const std = @import("std");
const HashSet = @import("../utils/hash_set.zig").HashSet;
const CustomElementDefinition = @import("CustomElementDefinition.zig");
const Document = @import("Document.zig");
const LocalName = @import("local_name").LocalName;

pub const DefKey = struct {
    name: []const u8,
    local_name: LocalName,
};

const DefKeyContext = struct {
    pub fn hash(_: DefKeyContext, key: DefKey) u64 {
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(key.name);
        hasher.update("\x00");
        hasher.update(key.local_name.slice());

        return hasher.final();
    }

    pub fn eql(_: DefKeyContext, a: DefKey, b: DefKey) bool {
        return std.mem.eql(u8, a.name, b.name) and
            b.local_name.eql(a.local_name);
    }
};

is_scoped: bool,
// TODO: Need to implement set data structure at first.
scoped_doc_set: HashSet(*Document),
custom_elem_def_set: std.HashMap(
    DefKey,
    *CustomElementDefinition,
    DefKeyContext,
    std.hash_map.default_max_load_percentage,
),
elem_def_is_running: bool,
//when_defined_promise_map: std.AutoArrayHashMapUnmanaged()

pub fn init() CustomElementRegistry {
    return .{
        .is_scoped = false,
        .scoped_doc_set = HashSet(*Document).init(),
        .custom_elem_def_set = .empty,
        .elem_def_is_running = HashSet(*CustomElementDefinition).init(),
    };
}

pub fn lookup(
    self: *CustomElementRegistry,
    name: []const u8,
    local_name: LocalName,
) ?*CustomElementDefinition {
    return self.custom_elem_def_set.get(.{
        .name = name,
        .local_name = local_name,
    });
}
