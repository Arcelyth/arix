const std = @import("std");
const BufferDeque = @import("../renderer/utils/buffer_deque.zig").BufferDeque;

const Buffer = BufferDeque(.utf8, .not_atomic, true);
const chunk_character_count = 1024;

/// Split to chunks to simulate the data from network.
pub fn fill(buffer: *Buffer, allocator: std.mem.Allocator, input: []const u8) !usize {
    if (input.len == 0) return 0;

    var chunk: std.ArrayList(u8) = .empty;
    defer chunk.deinit(allocator);

    var idx: usize = 0;
    var total_chars: usize = 0;
    var total_bytes: usize = 0;

    while (total_chars < input.len) {
        const characters_in_chunk = @min(chunk_character_count, input.len - total_chars);
        chunk.clearRetainingCapacity();

        for (0..characters_in_chunk) |_| {
            if (idx == input.len) idx = 0;

            const sequence_len = try std.unicode.utf8ByteSequenceLength(input[idx]);
            if (idx + sequence_len > input.len) return error.InvalidUtf8;
            _ = try std.unicode.utf8Decode(input[idx .. idx + sequence_len]);
            try chunk.appendSlice(allocator, input[idx .. idx + sequence_len]);
            idx += sequence_len;
        }

        try buffer.pushBackSlice(chunk.items);
        total_chars += characters_in_chunk;
        total_bytes += chunk.items.len;
    }

    return total_bytes;
}

/// Return the byte count produced by `fill` without allocating its chunks.
pub fn byteLen(input: []const u8) !usize {
    if (input.len == 0) return 0;

    var idx: usize = 0;
    var total_chars: usize = 0;
    var total_bytes: usize = 0;

    while (total_chars < input.len) : (total_chars += 1) {
        if (idx == input.len) idx = 0;

        const sequence_len = try std.unicode.utf8ByteSequenceLength(input[idx]);
        if (idx + sequence_len > input.len) return error.InvalidUtf8;
        _ = try std.unicode.utf8Decode(input[idx .. idx + sequence_len]);
        idx += sequence_len;
        total_bytes += sequence_len;
    }

    return total_bytes;
}
