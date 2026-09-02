/// Parser for parsing .dat file.
const TestParser = @This();

const std = @import("std");
const TestCase = @import("TestCase.zig");

allocator: std.mem.Allocator,
data: []const u8,
offset: usize = 0,

pub fn init(data: []const u8, alloc: std.mem.Allocator) TestParser {
    return .{
        .allocator = alloc,
        .data = data,
        .offset = 0,
    };
}

pub inline fn isEnd(self: *const TestParser) bool {
    var pos = self.offset;
    while (pos < self.data.len) : (pos += 1) {
        const c = self.data[pos];
        if (c != ' ' and c != '\t' and c != '\r' and c != '\n')
            return false;
    }
    return true;
}

fn readLine(self: *TestParser) ?[]const u8 {
    if (self.offset >= self.data.len) return null;

    const rest = self.data[self.offset..];
    const line_len = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;

    var line = rest[0..line_len];
    self.offset += line_len;
    if (self.offset < self.data.len and self.data[self.offset] == '\n') {
        self.offset += 1;
    }

    if (line.len > 0 and line[line.len - 1] == '\r') {
        line = line[0 .. line.len - 1];
    }
    return line;
}

fn peekLine(self: *const TestParser) ?[]const u8 {
    if (self.offset >= self.data.len) return null;

    const rest = self.data[self.offset..];
    const line_len = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;

    var line = rest[0..line_len];
    if (line.len > 0 and line[line.len - 1] == '\r') {
        line = line[0 .. line.len - 1];
    }
    return line;
}

pub fn nextTest(self: *TestParser) ?TestCase {
    while (self.readLine()) |line| {
        if (std.mem.eql(u8, line, "#data")) break;
    } else return null;

    var test_case = TestCase.init();

    const data_start = self.offset;
    var data_end = data_start;

    while (self.peekLine()) |line| : (_ = self.readLine()) {
        if (std.mem.eql(u8, line, "#errors")) {
            data_end = self.offset;
            break;
        }
    }

    var raw_data = self.data[data_start..data_end];
    if (std.mem.endsWith(u8, raw_data, "\r\n")) {
        raw_data = raw_data[0 .. raw_data.len - 2];
    } else if (std.mem.endsWith(u8, raw_data, "\n")) {
        raw_data = raw_data[0 .. raw_data.len - 1];
    }
    test_case.data = raw_data;

    while (self.readLine()) |line| {
        if (std.mem.eql(u8, line, "#errors") or std.mem.eql(u8, line, "#new-errors")) {
            while (self.peekLine()) |err_line| {
                if (isSectionHeader(err_line)) break;
                if (err_line.len > 0) test_case.errors += 1;
                _ = self.readLine();
            }
        } else if (std.mem.eql(u8, line, "#document-fragment")) {
            if (self.readLine()) |frag_line| {
                test_case.fragment = frag_line;
            }
        } else if (std.mem.eql(u8, line, "#script-off")) {
            test_case.scripting = false;
        } else if (std.mem.eql(u8, line, "#script-on")) {
            test_case.scripting = true;
        } else if (std.mem.eql(u8, line, "#document")) {
            self.handleDoc(&test_case);
            break;
        } else {}
    }

    return test_case;
}

fn handleDoc(self: *TestParser, case: *TestCase) void {
    const doc_start = self.offset;
    var doc_end = doc_start;

    while (self.peekLine()) |line| {
        if (std.mem.eql(u8, line, "")) break;
        _ = self.readLine();
        doc_end = self.offset;
    }

    var raw_doc = self.data[doc_start..doc_end];
    while (raw_doc.len > 0 and (raw_doc[raw_doc.len - 1] == '\n' or raw_doc[raw_doc.len - 1] == '\r')) {
        raw_doc = raw_doc[0 .. raw_doc.len - 1];
    }
    case.expected = raw_doc;
}

pub fn parse(self: *TestParser) !std.ArrayList(TestCase) {
    var list: std.ArrayList(TestCase) = .empty;
    errdefer list.deinit(self.allocator);

    while (self.nextTest()) |tc| {
        try list.append(self.allocator, tc);
    }

    return list;
}

fn isSectionHeader(line: []const u8) bool {
    return std.mem.eql(u8, line, "#data") or
        std.mem.eql(u8, line, "#errors") or
        std.mem.eql(u8, line, "#new-errors") or
        std.mem.eql(u8, line, "#document-fragment") or
        std.mem.eql(u8, line, "#script-off") or
        std.mem.eql(u8, line, "#script-on") or
        std.mem.eql(u8, line, "#document");
}

const testing = std.testing;

test "parse tree construction dat file" {
    const raw_dat =
        \\#data
        \\<p>One<p>Two
        \\#errors
        \\3: Missing document type declaration
        \\#document
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       "One"
        \\|     <p>
        \\|       "Two"
    ;

    var parser = TestParser.init(raw_dat, testing.allocator);
    try std.testing.expect(!parser.isEnd());

    const tc = parser.nextTest().?;
    try std.testing.expectEqualStrings("<p>One<p>Two", tc.data);
    try std.testing.expectEqual(1, tc.errors);
    try std.testing.expect(tc.fragment == null);
    try std.testing.expect(tc.scripting == null);
    try std.testing.expectEqualStrings(
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       "One"
        \\|     <p>
        \\|       "Two"
    , tc.expected);

    try std.testing.expect(parser.isEnd());
}
