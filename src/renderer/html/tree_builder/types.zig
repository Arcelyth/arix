const TokenizerState = @import("../tokenizer/state.zig").TokenizerState;

pub const ProcessResult = union(enum) {
    PR_Done,
    PR_ChangeState: TokenizerState,
    PR_AckSelfClosing,
};
