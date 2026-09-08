const std = @import("std");
const Bench = @import("Bench.zig");
const HtmlTokenizerBench = @import("HtmlTokenizerBench.zig");
const HtmlParserBench = @import("HtmlParserBench.zig");
const CssTokenizerBench = @import("CssTokenizerBench.zig");
const CssParserBench = @import("CssParserBench.zig");

const sample_count = 15;
const warmup_count = 3;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var iters: usize = 100;
    var first_path: usize = 1;

    if (args.len >= 3 and std.mem.eql(u8, args[1], "--iterations")) {
        iters = try std.fmt.parseInt(usize, args[2], 10);
        if (iters == 0) return error.InvalidIterationCount;
        first_path = 3;
    }
    if (first_path == args.len) {
        std.debug.print("usage: zig build bench -- [--iterations N] FILE.html FILE.css ...\n", .{});
        return;
    }

    std.debug.print("{s:<18} {s:<24} {s:>12} {s:>12}\n", .{
        "benchmark", "input", "ns/iteration", "MiB/s",
    });

    for (args[first_path..]) |path| {
        const input = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .unlimited);
        defer init.gpa.free(input);

        var html_tokenizer = HtmlTokenizerBench.init(init.gpa);
        var html_parser = HtmlParserBench.init(init.gpa);
        var css_tokenizer = CssTokenizerBench.init(init.gpa);
        var css_parser = CssParserBench.init(init.gpa);

        var benches: std.ArrayList(Bench) = .empty;
        if (std.mem.endsWith(u8, path, ".html")) {
            try benches.append(arena, Bench.init(
                "HTML tokenizer",
                &html_tokenizer,
                HtmlTokenizerBench.prepare,
                HtmlTokenizerBench.step,
                HtmlTokenizerBench.finish,
            ));
            try benches.append(arena, Bench.init(
                "HTML parser",
                &html_parser,
                HtmlParserBench.prepare,
                HtmlParserBench.step,
                HtmlParserBench.finish,
            ));
        } else if (std.mem.endsWith(u8, path, ".css")) {
            try benches.append(arena, Bench.init(
                "CSS tokenizer",
                &css_tokenizer,
                CssTokenizerBench.prepare,
                CssTokenizerBench.step,
                CssTokenizerBench.finish,
            ));
            try benches.append(arena, Bench.init(
                "CSS parser",
                &css_parser,
                CssParserBench.prepare,
                CssParserBench.step,
                CssParserBench.finish,
            ));
        } else {
            std.debug.print("skip {s}: expected an .html or .css file\n", .{path});
            continue;
        }

        for (benches.items) |bench| {
            const elapsed = try measure(bench, input, iters, init.io);
            const seconds = @as(f64, @floatFromInt(elapsed)) / 1_000_000_000.0;
            const bytes = @as(f64, @floatFromInt(input.len)) * @as(f64, @floatFromInt(iters));
            std.debug.print("{s:<18} {s:<24} {d:>12} {d:>12.2}\n", .{
                bench.name,
                std.fs.path.basename(path),
                elapsed / iters,
                bytes / seconds / (1024.0 * 1024.0),
            });
        }
    }
}

fn measure(bench: Bench, input: []const u8, iterations: usize, io: std.Io) !u64 {
    // Warm up the benchmark to reduce startup effects.
    for (0..warmup_count) |_| {
        _ = try bench.run(input, 1, io);
    }

    // Collect multiple samples for a more stable measurement.
    var samples: [sample_count]u64 = undefined;
    for (&samples) |*sample| sample.* = try bench.run(input, iterations, io);

    // Use the median sample to reduce the impact of outliers.
    std.mem.sortUnstable(u64, &samples, {}, std.sort.asc(u64));
    return samples[sample_count / 2];
}
