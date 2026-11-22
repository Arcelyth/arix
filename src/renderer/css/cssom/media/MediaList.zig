//! A style sheet's ordered collection of media queries.
//! https://drafts.csswg.org/cssom/#the-medialist-interface
const MediaList = @This();
const std = @import("std");
const MediaQuery = @import("MediaQuery.zig");
const Allocator = std.mem.Allocator;

queries: std.ArrayList(MediaQuery) = .empty,
