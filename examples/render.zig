const std = @import("std");
const renderer = @import("renderer");
const strale = @import("strale");
const utils = renderer.utils;
const image = utils.image;
const BufferDeque = utils.buffer_deque.BufferDeque;
const HtmlParser = renderer.html.Parser;
const CssBuffer = renderer.css.syntax.Buffer;
const CssParser = renderer.css.syntax.Parser;
const style = renderer.style;
const layout = renderer.layout;
const DisplayList = renderer.paint.display.DisplayList;
const Canvas = renderer.paint.Canvas;

pub const Options = struct {
    css_path: []const u8,
    output_path: []const u8,
    width: usize,
    height: usize,
};

pub fn run(init: std.process.Init, options: Options) !void {
    const allocator = init.arena.allocator();

    strale.setGlobalAlloc(allocator);

    const cwd = std.Io.Dir.cwd();
    const html = try cwd.readFileAlloc(init.io, "./index.html", allocator, .unlimited);
    const css = try cwd.readFileAlloc(init.io, options.css_path, allocator, .unlimited);

    // HTML -> DOM.
    const html_parser = try parseHtml(allocator, html);
    defer html_parser.destroy();
    const root = html_parser.tree_builder.document.documentElement() orelse return error.NoDocumentElement;

    // CSS -> stylesheet.
    var buffer = try CssBuffer.init(allocator, css);
    defer buffer.deinit();

    var stream = buffer.stream(allocator);
    defer stream.deinit();

    var css_parser = CssParser.init(allocator, &stream);
    const stylesheet = try css_parser.parseStylesheet();

    var prepared = try style.PreparedStylesheet.init(allocator, &stylesheet, .author);
    defer prepared.deinit(allocator);

    // DOM + CSS -> styled tree -> layout fragments.
    const context: style.computed.ComputedStyle.Context = .{
        .font_size = 16,
        .root_font_size = 16,
        .x_height = 8,
        .zero_advance = 8,
        .viewport_width = @floatFromInt(options.width),
        .viewport_height = @floatFromInt(options.height),
    };
    const styled = try style.StyledNode.build(allocator, root, &.{prepared}, &context);
    defer styled.destroy(allocator);

    var boxes = try layout.BoxTree.build(allocator, styled);
    defer boxes.destroy(allocator);

    var fragments = try boxes.layout(allocator, context.viewport_width, context.viewport_height);
    defer fragments.destroy(allocator);

    try paint(init, options, &fragments);
}

fn parseHtml(allocator: std.mem.Allocator, html: []const u8) !*HtmlParser {
    const parser = try HtmlParser.create(allocator, .{
        .tokenizer = .{},
        .tree_builder = .{},
    });
    errdefer parser.destroy();
    var input = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
    defer input.deinit();
    try input.pushBackSlice(html);
    try parser.tokenizer.step_E(&input);
    return parser;
}

fn paint(init: std.process.Init, options: Options, fragments: *const layout.fragment.FragmentTree) !void {
    const allocator = init.arena.allocator();
    const cwd = std.Io.Dir.cwd();

    // Fragments -> display list -> pixels -> BMP.
    var list = try DisplayList.build(allocator, fragments);
    defer list.deinit(allocator);

    var canvas = try Canvas.init(
        allocator,
        options.width,
        options.height,
        .{
            .clear_color = .{ 255, 255, 255 },
        },
    );
    defer canvas.deinit(allocator);

    try canvas.draw(allocator, &list);
    const bmp = try image.bmp.encode(allocator, options.width, options.height, canvas.pixels);
    defer allocator.free(bmp);
    try cwd.createDirPath(init.io, std.fs.path.dirname(options.output_path).?);
    try cwd.writeFile(init.io, .{ .sub_path = options.output_path, .data = bmp });
    std.debug.print("Wrote {s} ({d} x {d})\n", .{ options.output_path, options.width, options.height });
}
