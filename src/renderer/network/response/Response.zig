//! https://fetch.spec.whatwg.org/#responses
const Response = @This();
const std = @import("std");
const Url = @import("../url/Url.zig");
const HeaderList = @import("../header/HeaderList.zig");
const types = @import("types.zig");
const Body = @import("../Body.zig");

allocator: std.mem.Allocator,
type: types.Type = .default,
/// Whether the developer or user intentionally aborted the request.
aborted: bool = false,
/// URLs followed while fetching this response.
url_list: std.ArrayList(Url) = .empty,
/// HTTP status, from 0 through 999. Network errors use 0.
status: u16 = 200,
status_message: []const u8 = "",
header_list: HeaderList,
body: ?*Body = null,
cache_state: types.CacheState = .empty,
/// Header names that a CORS filtered response may expose.
cors_exposed_header_name_list: std.ArrayList([]const u8) = .empty,
range_requested: bool = false,
request_includes_credentials: bool = true,
timing_allow_passed: bool = false,
/// Timing-Allow-Origin values from each redirect response.
navigation_timing_allow_values_list: std.ArrayList([]const []const u8) = .empty,
body_info: types.BodyInfo = .{},
service_worker_timing_info: ?*const types.ServiceWorkerTimingInfo = null,
redirect_taint: types.RedirectTaint = .@"same-origin",

pub fn init(allocator: std.mem.Allocator) Response {
    return .{
        .allocator = allocator,
        .header_list = HeaderList.init(allocator),
    };
}

pub fn deinit(self: *Response) void {
    self.header_list.deinit();
    self.url_list.deinit(self.allocator);
    self.cors_exposed_header_name_list.deinit(self.allocator);
    self.navigation_timing_allow_values_list.deinit(self.allocator);
}

pub fn url(self: *const Response) ?*const Url {
    if (self.url_list.items.len == 0) return null;
    return &self.url_list.items[self.url_list.items.len - 1];
}

/// Creates a network error with status 0, empty headers, and no body.
/// https://fetch.spec.whatwg.org/#concept-network-error
pub fn networkError(allocator: std.mem.Allocator) Response {
    var response = Response.init(allocator);
    response.type = .@"error";
    response.status = 0;
    return response;
}

/// Creates a network error with its aborted flag set.
/// https://fetch.spec.whatwg.org/#concept-aborted-network-error
pub fn abortedNetworkError(allocator: std.mem.Allocator) Response {
    var response = Response.networkError(allocator);
    response.aborted = true;
    return response;
}
