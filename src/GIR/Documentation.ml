open XMLUtils


type documentation = {
    rawDocText: string option;
    sinceVersion: string option;
}

(* xml -> dumentation *)
let queryDocumentation element =
  let doc = match firstChildWithLocalName "doc" element with
    | Some d -> getElementContent d
    | None -> None
  in
  { rawDocText = doc;
    sinceVersion = lookupAttr "version" element
  }
