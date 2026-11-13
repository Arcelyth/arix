pub const Type = enum {
    basic,
    cors,
    default,
    @"error",
    @"opaque",
    opaqueredirect,
};

pub const CacheState = enum {
    /// The empty string.
    empty,
    local,
    validated,
};

pub const RedirectTaint = enum {
    @"same-origin",
    @"same-site",
    @"cross-site",
};

/// Body data used by Resource Timing and Navigation Timing.
/// https://fetch.spec.whatwg.org/#response-body-info
pub const BodyInfo = struct {
    encoded_size: u64 = 0,
    decoded_size: u64 = 0,
    content_type: []const u8 = "",
    content_encoding: []const u8 = "",
};

// FIXME: Not implemented
pub const ServiceWorkerTimingInfo = opaque {};
