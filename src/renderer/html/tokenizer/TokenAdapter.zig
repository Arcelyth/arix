/// A type-erased interface for consuming tokens.
const TokenAdapter = @This();

const Token = @import("token.zig").Token;
const TokenizerError = @import("error.zig").TokenizerError;
const TokenizerState = @import("state.zig").TokenizerState;

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    handleTokenFn: *const fn (ptr: *anyopaque, token: Token) ?TokenizerState,
    handleErrorFn: *const fn (ptr: *anyopaque, err: TokenizerError, cur_line: usize) void,
    adjustCurrentNodeAndNotInHtmlNamespace: *const fn (ptr: *anyopaque) bool,
};

pub fn handleToken(self: TokenAdapter, token: Token) ?TokenizerState {
    return self.vtable.handleTokenFn(self.ptr, token);
}

pub fn handleError(self: TokenAdapter, err: TokenizerError, cur_line: usize) void {
    self.vtable.handleErrorFn(self.ptr, err, cur_line);
}

/// For markup-declaration-open-state.
pub fn adjustCurrentNodeAndNotInHtmlNamespace(self: TokenAdapter) bool {
    return self.vtable.adjustCurrentNodeAndNotInHtmlNamespace(self.ptr);
}
