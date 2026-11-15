//! https://streams.spec.whatwg.org/#readablestreambyobrequest
const ReadableStreamBYOBRequest = @This();
const ReadableByteStreamController = @import("ReadableByteStreamController.zig");

// FIXME: need ECMAScript's TypedArray type.
const TypedArray = opaque {};

controller: ?*ReadableByteStreamController = null,
view: ?*TypedArray = null,
