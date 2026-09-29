const std = @import("std");
const syntax = @import("../syntax/parsing_results.zig");
const types = @import("types.zig");
const Declaration = types.Declaration;

pub fn parseDeclaration(declaration: *const syntax.Declaration) Declaration {
    _ = declaration;
    @panic("TODO");
}
