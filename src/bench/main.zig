const std = @import("std");
const Bench = @import("Bench.zig");
const HtmlTokenizerBench = @import("HtmlTokenizerBench.zig");

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

        var benches: std.ArrayList(Bench) = .empty;
        if (std.mem.endsWith(u8, path, ".html")) {
            try benches.append(arena, Bench.init("HTML tokenizer", &html_tokenizer, HtmlTokenizerBench.step));
        } else if (std.mem.endsWith(u8, path, ".css")) {
            @panic("TODO");
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

fn measure(bench: Bench, input: []const u8, iters: usize, io: std.Io) !u64 {
    for (0..warmup_count) |_| {
        const result = try bench.step(input);
        std.mem.doNotOptimizeAway(result);
    }
    var samples: [sample_count]u64 = undefined;
    for (&samples) |*sample| sample.* = try bench.run(input, iters, io);
    std.mem.sortUnstable(u64, &samples, {}, std.sort.asc(u64));
    return samples[sample_count / 2];
}
