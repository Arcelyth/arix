pub const OptionElement = struct {
    selectedness: bool = false,
};

pub const SelectElement = struct {};
pub const SelectedContentElement = struct {
    disabled: bool = false,
};

pub const ElementInterface = union(enum) {
    option: OptionElement,
    select: SelectElement,
    selectedcontent: SelectedContentElement,
};
