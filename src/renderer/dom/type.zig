pub const DomTypeId = enum {
    DOM_Node,

    DOM_Element,
    DOM_CharacterData,
    DOM_Document,
    DOM_DocumentFragment,
    DOM_DocumentType,
    DOM_CharacteData,

    // HTML
    DOM_HTMLElement,
    DOM_HTMLHtmlElement,
    DOM_HTMLBodyElement,
    DOM_HTMLDivElement,
    DOM_HTMLTableElement,

    DOM_HTMLInputElement,

    // CharactData
    DOM_Text,
    DOM_Comment,
    DOM_ProcessingInstruction,

    // Document Fragment
    DOM_ShadowRoot,

    // SVG
    DOM_SVGElement,
};
