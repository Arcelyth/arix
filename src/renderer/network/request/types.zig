const Url = @import("../url/Url.zig");

// FIXME: Not implemented yet.
pub const EnvironmentSettingsObject = opaque {};
pub const Environment = opaque {};
pub const TraversableNavigable = opaque {};
pub const PolicyContainer = opaque {};
pub const Origin = opaque {};
pub const Body = opaque {};
pub const InternalPriority = opaque {};

pub const RequestBody = union(enum) {
    bytes: []const u8,
    body: *Body,
};

pub const TraversableForUserPrompts = union(enum) {
    @"no-traversable",
    client,
    traversable: *TraversableNavigable,
};

pub const RequestOrigin = union(enum) {
    client,
    origin: *const Origin,
};

pub const RequestPolicyContainer = union(enum) {
    client,
    container: *PolicyContainer,
};

pub const Referrer = union(enum) {
    @"no-referrer",
    client,
    url: *const Url,
};

pub const InitiatorType = enum {
    audio,
    beacon,
    body,
    css,
    @"early-hints",
    embed,
    fetch,
    font,
    frame,
    iframe,
    image,
    img,
    input,
    link,
    object,
    ping,
    script,
    track,
    video,
    xmlhttprequest,
    other,
};

pub const ServiceWorkersMode = enum { all, none };

pub const Initiator = enum {
    /// The empty string.
    empty,
    download,
    imageset,
    manifest,
    prefetch,
    prerender,
    xslt,
};

/// Includes the internal serviceworker and webidentity destinations.
pub const Destination = enum {
    /// The empty string.
    empty,
    audio,
    audioworklet,
    document,
    embed,
    font,
    frame,
    iframe,
    image,
    json,
    manifest,
    object,
    paintworklet,
    report,
    script,
    serviceworker,
    sharedworker,
    style,
    text,
    track,
    video,
    webidentity,
    worker,
    xslt,

    /// Whether this destination is script-like.
    /// https://fetch.spec.whatwg.org/#request-destination-script-like
    pub fn isScriptLike(self: Destination) bool {
        return switch (self) {
            .audioworklet, .paintworklet, .script, .serviceworker, .sharedworker, .worker => true,
            else => false,
        };
    }
};

pub const Priority = enum {
    high,
    low,
    auto,
};

pub const Mode = enum {
    @"same-origin",
    cors,
    @"no-cors",
    navigate,
    websocket,
    webtransport,
};

pub const CredentialsMode = enum {
    omit,
    @"same-origin",
    include,
};

pub const CacheMode = enum {
    default,
    @"no-store",
    reload,
    @"no-cache",
    @"force-cache",
    @"only-if-cached",
};

pub const RedirectMode = enum {
    follow,
    @"error",
    manual,
};

pub const ResponseTainting = enum {
    basic,
    cors,
    @"opaque",
};

pub const ParserMetadata = enum {
    /// The empty string.
    empty,
    @"parser-inserted",
    @"not-parser-inserted",
};

/// https://w3c.github.io/webappsec-referrer-policy/#referrer-policy
pub const ReferrerPolicy = enum {
    /// The empty string.
    empty,
    @"no-referrer",
    @"no-referrer-when-downgrade",
    @"same-origin",
    origin,
    @"strict-origin",
    @"origin-when-cross-origin",
    @"strict-origin-when-cross-origin",
    @"unsafe-url",
};

/// A WebTransport certificate hash.
pub const WebTransportHash = struct {
    algorithm: []const u8,
    value: []const u8,
};
