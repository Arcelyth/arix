const File = @This();

const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

name: StraleUtf8Global,
ty: StraleUtf8Global,
body: StraleUtf8Global,

pub fn init() File {
    return .{
        .name = StraleUtf8Global.init(),
        .ty = StraleUtf8Global.init(),
        .body = StraleUtf8Global.init(),
    };
}
