//! 3.3.4 Resolving Weak Types.
//! https://www.unicode.org/reports/tr9/#Resolving_Weak_Types
const defs = @import("defs.zig");
const BidiCharType = defs.BidiCharType;
const IsolatingRunSequence = defs.IsolatingRunSequence;

/// Applies W1–W7 to one isolating run sequence.
pub fn resolve(sequence: IsolatingRunSequence, processing: []BidiCharType) void {
    nonspacing(sequence.indices, processing, sequence.sos);
    arabicNumbers(sequence.indices, processing, sequence.sos);
    arabicLetters(sequence.indices, processing);
    separators(sequence.indices, processing);
    terminators(sequence.indices, processing);
    remainingSeparators(sequence.indices, processing);
    europeanNumbers(sequence.indices, processing, sequence.sos);
}

/// [W1]NSMs inherit the preceding type, except after isolate controls.
fn nonspacing(indices: []const usize, classes: []BidiCharType, sos: BidiCharType) void {
    var previous = sos;
    for (indices) |i| {
        if (classes[i] == .NSM)
            classes[i] = if (previous.isIsolate() or previous == .PDI)
                .ON
            else
                previous;
        previous = classes[i];
    }
}

/// [W2]EN following a strong AL becomes AN.
fn arabicNumbers(indices: []const usize, classes: []BidiCharType, sos: BidiCharType) void {
    var strong = sos;
    for (indices) |i| {
        if (classes[i].isStrong()) {
            strong = classes[i];
        } else if (classes[i] == .EN and strong == .AL) classes[i] = .AN;
    }
}

/// [W3]All ALs become R.
fn arabicLetters(indices: []const usize, classes: []BidiCharType) void {
    for (indices) |i| if (classes[i] == .AL) {
        classes[i] = .R;
    };
}

/// [W4]A single separator between matching numeric types joins those numbers.
fn separators(indices: []const usize, classes: []BidiCharType) void {
    if (indices.len < 3) return;
    for (1..indices.len - 1) |i| {
        const before = classes[indices[i - 1]];
        const after = classes[indices[i + 1]];
        const current = &classes[indices[i]];
        if (before != after) continue;
        if ((current.* == .ES and before == .EN) or
            (current.* == .CS and (before == .EN or before == .AN)))
            current.* = before;
    }
}

/// [W5]ET sequences adjacent to EN become EN.
fn terminators(indices: []const usize, classes: []BidiCharType) void {
    var i: usize = 0;
    while (i < indices.len) {
        if (classes[indices[i]] != .ET) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < indices.len and classes[indices[i]] == .ET) : (i += 1) {}
        if ((start > 0 and classes[indices[start - 1]] == .EN) or
            (i < indices.len and classes[indices[i]] == .EN))
            for (indices[start..i]) |index| {
                classes[index] = .EN;
            };
    }
}

/// [W6]Separators and terminators not resolved by W4–W5 become ON.
fn remainingSeparators(indices: []const usize, classes: []BidiCharType) void {
    for (indices) |i| switch (classes[i]) {
        .ES, .ET, .CS => classes[i] = .ON,
        else => {},
    };
}

/// [W7]EN following strong L becomes L.
fn europeanNumbers(indices: []const usize, classes: []BidiCharType, sos: BidiCharType) void {
    var strong = sos;
    for (indices) |i| switch (classes[i]) {
        .L, .R => strong = classes[i],
        .EN => if (strong == .L) {
            classes[i] = .L;
        },
        else => {},
    };
}
