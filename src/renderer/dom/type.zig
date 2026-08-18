pub const DomTypeId = enum {
    DOM_Node,

    DOM_Element,
    DOM_CharacterData,
    DOM_Document,
    DOM_DocumentFragment,

    // HTML
    DOM_HTMLElement,
    DOM_HTMLHtmlElement,
    DOM_HTMLBodyElement,
    DOM_HTMLDivElement,
    DOM_HTMLTableElement,

    // CharactData
    DOM_Text,
    DOM_Comment,
    DOM_ProcessingInstruction,

    // Document Fragment
    DOM_ShadowRoot,

    // SVG
    DOM_SVGElement,
};
