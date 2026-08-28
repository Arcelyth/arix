const ActiveFormatElementList = @This();

const std = @import("std");
const types = @import("types.zig");
const ActiveFormatElement = types.ActiveFormatElement;
const Element = @import("../../dom/Element.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

allocator: std.mem.Allocator,
data: std.ArrayList(ActiveFormatElement),

pub fn init(alloc: std.mem.Allocator) ActiveFormatElementList {
    return .{
        .allocator = alloc,
        .data = .empty,
    };
}

pub fn deinit(self: *ActiveFormatElementList) void {
    self.data.deinit(self.allocator);
}

pub inline fn len(self: *const ActiveFormatElementList) usize {
    return self.data.items.len;
}

pub inline fn append(self: *ActiveFormatElementList, el: ActiveFormatElement) !void {
    try self.data.append(self.allocator, el);
}

pub inline fn pop(self: *ActiveFormatElementList) ?ActiveFormatElement {
    return self.data.pop();
}

pub inline fn at(self: *ActiveFormatElementList, idx: usize) ActiveFormatElement {
    return self.data.items[idx];
}

pub inline fn setAt(self: *ActiveFormatElementList, idx: usize, el: ActiveFormatElement) void {
    self.data.items[idx] = el;
}

pub inline fn index(self: *const ActiveFormatElementList, el: *Element) ?usize {
    for (self.data.items, 0..) |entry, i| switch (entry) {
        .AFE_Element => |candidate| if (candidate == el) return i,
        .AFE_Marker => {},
    };
    return null;
}

pub inline fn lastWithTag(self: *const ActiveFormatElementList, subject: LocalTag) ?usize {
    var i = self.data.items.len;
    while (index > 0) {
        i -= 1;
        switch (self.data[i]) {
            .AFE_Marker => return null,
            .AFE_Element => |el| if (el.local_name.is(subject)) return i,
        }
    }
    return null;
}
