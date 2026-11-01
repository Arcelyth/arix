/// Receives URL validation errors without stopping parsing.
const ErrorAdapter = @This();
const ParserError = @import("error.zig").ParserError;

ptr: *anyopaque,
handleErrorFn: *const fn (ptr: *anyopaque, err: ParserError) void,

/// Sends a validation error to the caller.
pub fn handleError(self: ErrorAdapter, err: ParserError) void {
    self.handleErrorFn(self.ptr, err);
}

/// Reports a validation error when an adapter is provided.
pub fn report(adapter: ?ErrorAdapter, err: ParserError) void {
    if (adapter) |value| value.handleError(err);
}

/// Helper that combines report a fatal validation error and returns its Zig error.
pub fn fail(adapter: ?ErrorAdapter, comptime err: ParserError) anyerror {
    report(adapter, err);
    return @field(anyerror, @tagName(err));
}
