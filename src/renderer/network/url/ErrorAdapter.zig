/// Receives URL validation errors without stopping parsing.
const ErrorAdapter = @This();
const ParserError = @import("error.zig").ParserError;

ptr: *anyopaque,
handleErrorFn: *const fn (ptr: *anyopaque, err: ParserError) void,

/// Sends a validation error to the caller.
pub fn handleError(self: ErrorAdapter, err: ParserError) void {
    self.handleErrorFn(self.ptr, err);
}
