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

const html_path = "./index.html";
const css_path = "./rect.css";

const output_path = "./target/rect.ppm";
const width = 320;
const height = 200;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    strale.setGlobalAlloc(allocator);

    const cwd = std.Io.Dir.cwd();
    const html = try cwd.readFileAlloc(init.io, html_path, allocator, .unlimited);
    const css = try cwd.readFileAlloc(init.io, css_path, allocator, .unlimited);

    // HTML -> DOM.
    const html_parser = try HtmlParser.create(allocator, .{ .tokenizer = .{}, .tree_builder = .{} });
    defer html_parser.destroy();

    var input = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
    defer input.deinit();

    try input.pushBackSlice(html);
    try html_parser.tokenizer.step_E(&input);
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
    const styled = try style.StyledNode.build(allocator, root, &.{prepared}, &.{
        .font_size = 16,
        .root_font_size = 16,
        .x_height = 8,
        .zero_advance = 8,
        .viewport_width = width,
        .viewport_height = height,
    });
    defer styled.destroy(allocator);

    var boxes = try layout.BoxTree.build(allocator, styled);
    defer boxes.destroy(allocator);

    var fragments = try boxes.layout(allocator, width, height);
    defer fragments.destroy(allocator);

    // Fragments -> display list -> pixels -> binary PPM.
    var list = try DisplayList.build(allocator, &fragments);
    defer list.deinit(allocator);

    var canvas = try Canvas.init(allocator, width, height);
    defer canvas.deinit(allocator);

    canvas.draw(&list);
    const ppm = try image.ppm.encode(allocator, width, height, canvas.pixels);
    try cwd.createDirPath(init.io, std.fs.path.dirname(output_path).?);
    try cwd.writeFile(init.io, .{ .sub_path = output_path, .data = ppm });
    std.debug.print("Wrote {s} ({d} x {d})\n", .{ output_path, width, height });
}
