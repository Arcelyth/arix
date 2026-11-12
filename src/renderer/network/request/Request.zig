//! https://fetch.spec.whatwg.org/#requests
const Request = @This();
const std = @import("std");
const Url = @import("../url/Url.zig");
const HeaderList = @import("../header/HeaderList.zig");
pub const types = @import("types.zig");

allocator: std.mem.Allocator,
method: []const u8 = "GET",
local_urls_only: bool = false,
header_list: HeaderList,
unsafe_request: bool = false,
body: ?types.RequestBody = null,
client: ?*types.EnvironmentSettingsObject,
reserved_client: ?*types.Environment = null,
replaces_client_id: []const u8 = "",
traversable_for_user_prompts: types.TraversableForUserPrompts = .client,
keepalive: bool = false,
initiator_type: ?types.InitiatorType = null,
service_workers_mode: types.ServiceWorkersMode = .all,
initiator: types.Initiator = .empty,
destination: types.Destination = .empty,
priority: types.Priority = .auto,
internal_priority: ?*const types.InternalPriority = null,
origin: types.RequestOrigin = .client,
top_level_navigation_initiator_origin: ?*const types.Origin = null,
policy_container: types.RequestPolicyContainer = .client,
referrer: types.Referrer = .client,
referrer_policy: types.ReferrerPolicy = .empty,
mode: types.Mode = .@"no-cors",
use_cors_preflight: bool = false,
credentials_mode: types.CredentialsMode = .@"same-origin",
use_url_credentials: bool = false,
cache_mode: types.CacheMode = .default,
redirect_mode: types.RedirectMode = .follow,
integrity_metadata: []const u8 = "",
cryptographic_nonce_metadata: []const u8 = "",
parser_metadata: types.ParserMetadata = .empty,
reload_navigation: bool = false,
history_navigation: bool = false,
user_activation: bool = false,
webdriver_navigation_id: ?[]const u8 = null,
render_blocking: bool = false,
webtransport_hash_list: std.ArrayList(types.WebTransportHash) = .empty,
url_list: std.ArrayList(Url) = .empty,
redirect_count: usize = 0,
response_tainting: types.ResponseTainting = .basic,
prevent_no_cache_cache_control_header_modification: bool = false,
done: bool = false,
timing_allow_failed: bool = false,
navigation_timing_allow_values_list: std.ArrayList([]const []const u8) = .empty,
webdriver_id: [36]u8,

pub fn init(
    allocator: std.mem.Allocator,
    io: std.Io,
    initial_url: Url,
    client: ?*types.EnvironmentSettingsObject,
) !Request {
    var request: Request = .{
        .allocator = allocator,
        .header_list = HeaderList.init(allocator),
        .client = client,
        .webdriver_id = try generateWebDriverId(io),
    };
    errdefer request.deinit();
    try request.url_list.append(allocator, initial_url);
    return request;
}

pub fn deinit(self: *Request) void {
    self.header_list.deinit();
    self.url_list.deinit(self.allocator);
    self.webtransport_hash_list.deinit(self.allocator);
    self.navigation_timing_allow_values_list.deinit(self.allocator);
}

/// Returns the initial URL, the first item in the URL list.
pub fn url(self: *const Request) *const Url {
    return &self.url_list.items[0];
}

/// Returns the last URL in the URL list.
/// https://fetch.spec.whatwg.org/#concept-request-current-url
pub fn currentUrl(self: *const Request) *const Url {
    return &self.url_list.items[self.url_list.items.len - 1];
}

/// Whether the destination makes this a subresource request.
/// https://fetch.spec.whatwg.org/#subresource-request
pub fn isSubresource(self: *const Request) bool {
    return switch (self.destination) {
        .empty,
        .audio,
        .audioworklet,
        .font,
        .image,
        .json,
        .manifest,
        .paintworklet,
        .script,
        .style,
        .text,
        .track,
        .video,
        .xslt,
        => true,
        else => false,
    };
}

/// Whether the destination makes this a non-subresource request.
/// https://fetch.spec.whatwg.org/#non-subresource-request
pub fn isNonSubresource(self: *const Request) bool {
    return self.isNavigation() or switch (self.destination) {
        .report, .serviceworker, .sharedworker, .worker => true,
        else => false,
    };
}

/// Whether the destination makes this a navigation request.
/// https://fetch.spec.whatwg.org/#navigation-request
pub fn isNavigation(self: *const Request) bool {
    return switch (self.destination) {
        .document, .embed, .frame, .iframe, .object => true,
        else => false,
    };
}

/// Adds a Range header using buffer for the value.
/// https://fetch.spec.whatwg.org/#concept-request-add-range-header
pub fn addRangeHeader(self: *Request, buffer: []u8, first: u64, last: ?u64) !void {
    std.debug.assert(last == null or first <= last.?);
    const value = if (last) |end|
        try std.fmt.bufPrint(buffer, "bytes={d}-{d}", .{ first, end })
    else
        try std.fmt.bufPrint(buffer, "bytes={d}-", .{first});
    try self.header_list.append("Range", value);
}

// Generates the UUID required when a request is created.
// https://w3c.github.io/webcrypto/#dfn-generate-a-random-uuid
fn generateWebDriverId(io: std.Io) ![36]u8 {
    var bytes: [16]u8 = undefined;
    try io.randomSecure(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    var id: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&id, "{s}-{s}-{s}-{s}-{s}", .{
        hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32],
    }) catch unreachable;
    return id;
}
