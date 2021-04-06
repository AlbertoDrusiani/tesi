open BasicTypes
open Deprecation
open Documentation
open XMLUtils


(*module KnownAliases = Map.make(String)*)

(* xml -> string *)
let elementDescription element =
    match lookupAttr "name" element with
    | Some n -> localName (Xml.tag element) ^ " [" ^ n ^ "]"
    | None -> localName (Xml.tag element)


let nameInCurrentNS ns n =
    { namespace = ns;  name = Some n;}


(*let resolveQualifiedTypeName name knownAliases =
    match a*)
(*TODO non so fare le mappe*)


(* string -> xml -> string *)
let getAttr attr element =
    match lookupAttr attr element with
    | Some v -> v
    | None -> "Errore in getAttr"

(* string -> string -> xml -> string *)
let getAttrWithNamespace ns attr element =
    match lookupAttrWithNamespace ns attr element with
    | Some v -> v
    | None -> "Errore in getAttrWithNamespace"

(* string -> xml -> string option *)
let queryAttr attr element =
    lookupAttr attr element

(* GIRXMLNamespace -> string -> xml -> string option *)
let queryAttrWithNamespace ns attr element =
    lookupAttrWithNamespace ns attr element

(* string -> string -> xml -> string *)
let optionalAttr attr def element =
    match queryAttr attr element with
    | Some a -> a
    | None -> def

(* string -> string -> BasicTypes.name*)
let qualifyName n ns =
    match String.split_on_char '.' n with
    | x::[] -> nameInCurrentNS ns x
    | x::xs::[] -> {namespace = x; name = Some xs;}
    | _ -> assert false

(* xml -> string -> BasicTypes.name *)
let parseName element ns =
    qualifyName (getAttr "name" element) ns

(* xml -> _DeprecationInfo option *)
let parseDeprecation element =
    queryDeprecated element  

(* xml -> documentation *)
let parseDocumentation element =
   queryDocumentation element 

(* string -> int option *)
let parseIntegral str =
    try Some (int_of_string str)
    with Failure _ -> assert false
 
(* string -> bool *)    
let parseBool str =
    match str with
    | "0" -> false
    | "1" -> true
    | _ -> assert false
   

(* string -> xml -> xml list *)
let parseChildrenWithLocalName n element =
    let introspectable e = 
        ((lookupAttr "introspectable" e) != (Some "0")) && ((lookupAttr "shadowed-by" e) == None)
    in  List.filter introspectable (childElemsWithLocalName n element)

(* string -> xml -> xml list *)
let parseAllChildrenWithLocalName n element =
    childElemsWithLocalName n element


(* GIRXMLNamespace -> string -> xml list *)    
let parseChildrenWithNSName ns n element =
    let introspectable e = (lookupAttr "introspectable" e) != (Some "0") in
    List.filter introspectable (childElemsWithNSName ns n element)




