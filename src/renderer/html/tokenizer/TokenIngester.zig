/// A type-erased interface for consuming tokens.
const TokenIngester = @This();

const Token = @import("token.zig").Token;

ptr: *anyopaque,
handleTokenFn: *const fn (ptr: *anyopaque, token: Token) void,

pub fn init(pointer: anytype, comptime handleTokenFn: fn (ptr: @TypeOf(pointer), token: Token) void) TokenIngester {
    const Ptr = @TypeOf(pointer);
    const gen = struct {
        fn handleToken(ptr: *anyopaque, token: Token) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            handleTokenFn(self, token);
        }
    };

    return .{
        .ptr = pointer,
        .handleTokenFn = gen.handleToken,
    };
}

pub fn handleToken(self: TokenIngester, token: Token) void {
    self.handleTokenFn(self.ptr, token);
}
