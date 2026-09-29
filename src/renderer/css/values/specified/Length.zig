//! CSS Values Level 3 length units.
//! See https://www.w3.org/TR/css-values-3/#lengths
value: f64,
unit: Unit,

pub const Unit = enum { px, em, ex, ch, rem, vw, vh, vmin, vmax, cm, mm, q, in, pt, pc };
