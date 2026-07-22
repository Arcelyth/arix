const ErrorIngester = @This();

const TokenizerError = @import("error.zig").TokenizerError;

ptr: *anyopaque,
handleErrorFn: *const fn (ptr: *anyopaque, err: TokenizerError, cur_line: usize, ch: u21) void,

pub fn init(pointer: anytype, comptime handleErrorFn: fn (ptr: @TypeOf(pointer), err: TokenizerError, cur_line: usize, ch: u21) void) ErrorIngester {
    const Ptr = @TypeOf(pointer);
    const gen = struct {
        fn handleError(ptr: *anyopaque, err: TokenizerError, line: usize, c: u21) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            handleErrorFn(self, err, line, c);
        }
    };

    return .{
        .ptr = pointer,
        .handleErrorFn = gen.handleError,
    };
}

pub fn handleError(self: ErrorIngester, err: TokenizerError, cur_line: usize, ch: u21) void {
    self.handleErrorFn(self.ptr, err, cur_line, ch);
}


