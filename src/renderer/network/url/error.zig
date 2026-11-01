/// URL validation errors.
/// https://url.spec.whatwg.org/#validation-error
pub const ParserError = enum {
    HostInvalidCodePoint,
    IPv6Unclosed,
    InvalidUrlUnit,
    SpecialSchemeMissingFollowingSolidus,
    MissingSchemeNonRelativeUrl,
    InvalidReverseSolidus,
    InvalidCredentials,
    HostMissing,
    PortOutOfRange,
    PortInvalid,
    FileInvalidWindowsDriveLetter,
    FileInvalidWindowsDriveLetterHost,
};
