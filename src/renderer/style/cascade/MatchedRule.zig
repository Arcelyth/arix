const syntax = @import("../../css/syntax/parsing_results.zig");
const ComponentValue = syntax.ComponentValue;
const QualifiedRule = syntax.QualifiedRule;
const namespace = @import("../../css/namespace.zig");
const Specificity = @import("../../css/selectors/Specificity.zig");

pub const MatchedRule = struct {
    rule: QualifiedRule,
    specificity: Specificity,
};
