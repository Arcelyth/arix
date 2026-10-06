const registry = @import("../../properties/registry.zig");

/// The computed style being resolved.
style: *const registry.ComputedValues,
/// The physical property whose value is being resolved.
current_longhand: registry.PropertyId,
