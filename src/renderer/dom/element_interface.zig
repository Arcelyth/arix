pub const OptionElement = struct {
    selectedness: bool,
};

pub const ElementInterface = union(enum) {
    option: OptionElement,
};
