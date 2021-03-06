open GIR.BasicTypes
open GIR.Property
open GIR.Method
open GIR.Object
open GIR.Interface
open GIR.Arg
open GIR.Callable

open API
open GObject
open Naming
open Code
open Files
open QualifiedNaming
open Util
open Filename
open Signal
open Callable
open Method
open Properties


(* config*cgstate*module_info -> name -> string -> string -> config*cgstate*module_info)*)
let genGObjectCasts (cgstate, minfo) n ctype checkMacro =
  match (NameSet.mem n noCType) with
  | true -> (cgstate, minfo)
  | false -> 
    let minfo = 
      if NameSet.mem n noCheckMacro
        then 
         hline ("#define " ^ objectVal n ^ "(val) ((" ^ ctype ^ "*) (*val)") minfo 
        else
         hline ("#define " ^ objectVal n ^ "(val) check_cast(" ^ checkMacro ^ ", val)") minfo 
    in let minfo = hline ("#define " ^ valObject n ^ " Val_GAnyObject") minfo  in 
    let cgstate, minfo = cline ("Make_Val_option(" ^ ctype ^ "," ^ valObject n ^ ")")  minfo cgstate in 
    let minfo = hline ("value " ^ valOptObject n ^ " (" ^ ctype ^ "*);") minfo  in 
    cgstate, minfo
  

let genSignalClass (cfg, minfo) n o =
  let parents = instanceTree cfg n in
  let ocamlName = ocamlIdentifier n in
  let minfo = gline ("class " ^ ocamlName ^ "_signals obj = object (self)") minfo  in
  let minfo = 
  match parents with
  | [] -> minfo
  | parent::_ ->
    let parentClass = nsOCamlClass minfo parent in
    let parentSignal =
      match List.hd parents with
      | {namespace = "Gtk"; name = "Widget"} -> "GObj.widget_signals_impl"
      | {namespace = "GObject"; name = "Object"} -> "[_] GObj.gobject_signals"
      | {namespace = "Gtk"; name = _} -> parentClass ^ "_signals"
      | {namespace = "GtkSource"; name = _} -> parentClass ^ "_signals"
      | _ -> "[_] GObj.gobject_signals"
    in let minfo = gline ("  inherit " ^ parentSignal ^ " obj") minfo  in
    let minfo = List.fold_left (
        fun minfo iface -> 
            match (o.objSignals = []) || (NameSet.mem iface (NameSet.union buggedIfaces excludeFiles)) with
            | true -> minfo
            | false ->
            let ifaceClass = nsOCamlClass minfo iface in
            let api = findAPIByName cfg iface in
            match api with
            | APIInterface i ->
                begin
                match i.ifSignals with
                | [] -> minfo
                | _ -> gline ("  inherit " ^ ifaceClass ^ "_signals obj") minfo 
                end
            | _ -> assert false 
    ) minfo o.objInterfaces in
    minfo
  in 

  let minfo = List.fold_left (fun info s -> genGSignal s n cfg info) minfo o.objSignals in
  let minfo = gline "end" minfo  in
  gblank minfo



let cTypeInit cTypeName typeInit =
  String.concat "\n" [
      "CAMLprim value ml_gi" ^ cTypeName ^ "_init(value unit) {";
      "    GType t = " ^ typeInit ^ "();";
      "    return Val_GType(t);";
      "}"
  ]


let genCObjectTypeInit cgstate minfo o n =
  match o with
  | obj when obj.objTypeInit <> "" -> 
      let cgstate, minfo = cline (cTypeInit (camelCaseToSnakeCase (n.namespace ^ n.name)) obj.objTypeInit) minfo cgstate  in
      cgstate, minfo
  | _ -> cgstate, minfo


let genMlTypeInit minfo nm =
  let namespaceOcamlName = camelCaseToSnakeCase (nm.namespace ^ nm.name) in
  let minfo = line ("external ml_gi" ^ namespaceOcamlName ^ 
    "_init : unit -> unit = \"ml_gi" ^ namespaceOcamlName ^ "_init\"") minfo 
  in line ("let () = ml_gi" ^ namespaceOcamlName ^ "_init ()") minfo
 

let isSetterOrGetter o m =
  let props = o.objProperties in
  let propNames = List.map (fun x -> x.propName |> hyphensToUnderscores) props in
  let mName = m.methodName.name in
  ((isPrefixOf "get" mName) 
  || (isPrefixOf "set" mName))
  && List.exists (fun x -> 
  check_suffix mName x) propNames


let isMakeParamsParent ns nm =
  match ns, nm with
  | _, {namespace = "GObject"; name = "Object"} -> false
  | currNS, {namespace = ns; name = _} -> 
    if currNS <> ns 
    then false
    else true


let genObjectConstructor' constrDecl constCreate n cfg minfo =
  let makeParams nm =
    match nm with
    | {namespace = "Gtk"; name = "Widget"} -> "GtkBase.Widget.size_params"
    | _ -> nm.name ^ ".make_params"

  in let makeParamsCont parent idx =
    match idx with
    | 0 -> indentBy 1 ^ makeParams parent ^ " [] ~cont:("
    | _ -> indentBy (idx+1) ^ "fun pl ->" ^ makeParams parent ^ " pl ~cont:("

  in let packShowLabels parents =
    match List.mem {namespace = "Gtk"; name = "Widget"} parents with
    | true -> "~packing ~show"
    | false -> ""

  in let closedParentheses makeParents =
    String.make (List.length makeParents + 1) ')' 

  in let currNS = currentNS minfo in
  let parents = instanceTree cfg n in
  let makeParamsParents = 
    List.filter (isMakeParamsParent currNS) (List.rev parents)
  in let mkParentsNum = List.length makeParamsParents in
  let minfo = gline ("let " ^ constrDecl ^ " = begin") minfo in
  let minfo = 
    List.fold_left (fun info (p, idx) -> 
    gline (makeParamsCont p idx) info) 
    minfo 
    (List.combine makeParamsParents (List.init (List.length makeParamsParents) (fun x -> x)))
  in let minfo = gline (makeParamsCont n mkParentsNum) minfo in
  let minfo = gline (indentBy (mkParentsNum + 2) ^ (
    if List.mem ({namespace = "Gtk"; name = "Widget"}) parents
    then "fun pl ?packing ?show () -> GObj.pack_return ("
    else "fun pl () -> ("
  )) minfo in
  let minfo = gline constCreate minfo in
  let minfo = 
    gline (indentBy (mkParentsNum +3) ^ packShowLabels parents ^ closedParentheses makeParamsParents) minfo
  in gline "end" minfo

let genDefaultObjectConstructor n ocamlName cfg minfo =
  let currNS = currentNS minfo in
  let parents = instanceTree cfg n in
  let makeParamsParents = 
    List.filter (isMakeParamsParent currNS) (List.rev parents)
  in let mkParentsNum = List.length makeParamsParents in
  let creator = 
    indentBy (mkParentsNum + 3) ^ "new " ^ ocamlName ^ " (" ^ n.name ^ ".create pl))" in
  genObjectConstructor' ocamlName creator n cfg minfo



let genAdditionalObjectConstructor n ocamlClassName m cfg minfo =
  let currNS = currentNS minfo in
  let parents = instanceTree cfg n in
  let makeParamsParents = 
    List.filter (isMakeParamsParent currNS) (List.rev parents)
  in let mkParentsNum = List.length makeParamsParents in
  let ind = indentBy (mkParentsNum + 3) in
  let constrName = ocamlIdentifier m.methodName in
  let argsTextList =
    List.map (fun x -> x.argCName |> camelCaseToSnakeCase |> escapeOCamlReserved) m.methodCallable.args
  in let argsText =
    match argsTextList with
    | [] -> "()"
    | _ -> String.concat " " argsTextList
  in let constrWithArgs = constrName ^ " " ^ argsText in
  let creator' =
    if m.methodCallable.returnMayBeNull
    then [ 
      "let o_opt = " ^ n.name ^ "." ^ constrWithArgs ^ " in";
      "Option.map (fun o ->";
      "  GtkObject._ref_sink o;";
      "  Gobject.set_params o pl;";
      "  new " ^ ocamlClassName ^ " o";
      ") o_opt)"
    ]
    else [
      "let o = " ^ n.name ^ "." ^ constrWithArgs ^ " in";
      "GtkObject._ref_sink o;";
      "Gobject.set_params o pl;";
      "new " ^ ocamlClassName ^ " o)";
    ]
  in let creator =
    (*FIXME da capire meglio quella concatenzionne, riga 396 haskell*)
    String.concat "\n" ((ind :: (noLast creator')) @ (ind :: [List.hd (List.rev creator')]))
  in genObjectConstructor' constrWithArgs creator n cfg minfo





let genObject' (cfg, cgstate, minfo) n o ocamlName =
  let parents = instanceTree cfg n in 
  let name' = upperName n in
  let nspace = n.namespace in
  let objectName = n.name in
  let cgstate, minfo = genCObjectTypeInit cgstate minfo o n in
  let minfo = genSignalClass (cfg, minfo) n o in
  let minfo = gline ("class " ^ ocamlName ^ "_skel obj = object (self)") minfo in
  let minfo = 
  match parents with
  | [] -> minfo
  | parent::_ ->
    let parentClass = nsOCamlClass minfo parent in
    let parentSkelClass =
      begin
      match parent with
      | {namespace = "Gtk"; name = "Widget"} -> "['a] GObj.widget_impl"
      | {namespace = "GObject"; name = "Object"} -> "GObj.gtkobj"
      | {namespace = "Gtk"; name = _} -> parentClass ^ "_skel"
      | {namespace = "GtkSource"; _} -> parentClass ^ "_skel"
      | _ -> "GObj.gtkobj"
      end
    in 
    let minfo = gline ("  inherit " ^ parentSkelClass ^ " obj") minfo in
    let minfo = List.fold_left (
        fun minfo iface ->
          match NameSet.mem iface (NameSet.union buggedIfaces excludeFiles) with
          | true -> minfo
          | false ->
            let ifaceClass = nsOCamlClass minfo iface in
            gline ("  method i" ^ ocamlIdentifier iface ^ " = new " ^ ifaceClass ^ "_skel obj") minfo 
    ) minfo o.objInterfaces 
    in gline ("  method as_" ^ ocamlName ^ " = (obj :> " ^ nsOCamlType n.namespace n ^ " Gobject.obj)") minfo in
  let minfo = genMlTypeInit minfo n in
  let cgstate, minfo = group (
    fun minfo -> 
      let minfo = genObjectProperties cfg cgstate minfo n o in
      let minfo = gblank minfo in
      cgstate, minfo
  ) minfo in
  let cgstate, minfo = 
    match o.objSignals = [] with
    | true -> cgstate, minfo
    | false -> group 
              (fun m -> indent 
                        (fun i -> 
                        let acc = line "open GtkSignal" i 
                        |> line "open Gobject"
                        |> line "open Data"
                        in 
                        cgstate, List.fold_left (fun info s -> genSignal s n cfg info) acc o.objSignals) 
                        (line "module S = struct" m) |> (fun (x, y) -> x, line "end" y)) minfo
  in 
  let cgstate, minfo = group (fun minfo -> cgstate, (line ("let cast w : " ^ 
                        nsOCamlType n.namespace n ^
                        " Gobject.obj = Gobject.try_cast w \"" ^
                        nspace ^ objectName ^ "\"")) minfo ) minfo

  in let cgstate, minfo = group (fun minfo -> cgstate, (line ("let create pl : " ^
                        nsOCamlType n.namespace n ^
                        " Gobject.obj = GtkObject.make \"" ^
                        nspace ^ objectName ^ "\" pl")) minfo) minfo
  in let minfo = gline ("  (* Methods *)") minfo in
  let methods = o.objMethods in
  let methods' = List.filter (fun x -> not(isSetterOrGetter o x)) methods in
  let cgstate, minfo = 
    List.fold_left (fun (cgstate, minfo) f ->
      let action = fun cgstate minfo -> genMethod cfg cgstate minfo n f in
      let fallback = fun cgstate minfo e -> cgstate, line (
        "(* Could not generate method " ^ name' ^ "::" ^ 
        f.methodName.name ^ " *)\n" ^ "(* Error was: " ^ describeCGError e ^ " *)") minfo in
      handleCGExc (cgstate, minfo) fallback action )
      (cgstate, minfo) methods' in
  let minfo = gline "end" minfo in
  let minfo = gblank minfo in
  let minfo = gline (" and " ^ ocamlName ^ " obj = object (self)") minfo in
  let minfo = gline ("  inherit " ^ ocamlName ^ "_skel obj") minfo in
  let minfo = gline ("  method connect = new " ^ ocamlName ^ "_signals obj") minfo in
  let minfo = gline "end" minfo in
  let minfo = gblank minfo in
  let minfo = genDefaultObjectConstructor n ocamlName cfg minfo in
  let constructors = 
    List.filter (fun m -> 
    (m.methodType = Constructor) && (m.methodName.name <> "new")) o.objMethods in
  let cgstate, minfo =
    List.fold_left (fun (cgstate, info) m -> 
                    let cgstate, minfo, canGenerate = canGenerateCallable cfg cgstate info m.methodCallable in
                    if canGenerate
                    then cgstate, genAdditionalObjectConstructor n ocamlName m cfg minfo 
                    else cgstate, gblank minfo)
                    (cgstate, minfo) constructors in
  cgstate, minfo




let getObjCheckMacro o =
  String.uppercase_ascii (breakOnFirst "_get_type" o.objTypeInit)

(* config*cgstate*module_info -> nListame -> object -> module_info)*)
let genObject cfg cgstate minfo n o =
  let isGO = isGObject cfg (TInterface n) in 
  if not isGO
  then (cgstate, minfo)
  else
    let objectName = n.name in 
    let ocamlName = escapeOCamlReserved (camelCaseToSnakeCase objectName) in 
    let minfo = addTypeFile cfg minfo n in 
    let minfo = addCDep minfo (n.namespace ^ n.name) in 
    let (cgstate, minfo) = 
      match o.objCType with
      | None -> cgstate, minfo
      | Some ctype -> genGObjectCasts (cgstate, minfo) n ctype (getObjCheckMacro o)
    in if NameSet.mem n excludeFiles 
    then cgstate, minfo
    else genObject' (cfg, cgstate, minfo) n o ocamlName


let getIfCheckMacro i =
  let typeInit = i.ifTypeInit in
  match typeInit with
  | None -> None
  | Some t -> Some (breakOnFirst "_get_type" t |> String.uppercase_ascii)


let genCInterfaceTypeInit cgstate minfo i n =
  match i with
  | iface when Option.is_some iface.ifTypeInit -> 
    cline (cTypeInit (camelCaseToSnakeCase (n.namespace ^ n.name)) (Option.get iface.ifTypeInit)) minfo cgstate
  | _ -> cgstate, minfo 



let genInterface cfg cgstate minfo n iface =
  prerr_endline ("______GENINTERFACE");
  let name' = upperName n in
  let ocamlName = escapeOCamlReserved (camelCaseToSnakeCase n.name) in
  let isGO = apiIsGObject cfg n (APIInterface iface) in
  let minfo = addTypeFile cfg minfo n in
  let minfo = addCDep minfo (n.namespace ^ n.name) in
  let cgstate, minfo =
    match (iface.ifCType, getIfCheckMacro iface) with
    | (Some ctype, Some checkMacro) ->
      let cgstate, minfo  = genGObjectCasts (cgstate, minfo) n ctype checkMacro in
      let minfo = genMlTypeInit minfo n in
      let cgstate, minfo = genCInterfaceTypeInit cgstate minfo iface n in
      cgstate, minfo
    | (_, _) -> cgstate, minfo
  in 
    match NameSet.mem n excludeFiles with
    | true -> cgstate, minfo
    | false ->
      let minfo = (*QUI*)
        if isGO
        then
          let minfo = gline ("class virtual " ^ ocamlName ^ "_signals obj = object (self)") minfo in
          let minfo = gline ("  method private virtual connect : 'b. ('a,'b) GtkSignal.t -> callback:'b -> GtkSignal.id") minfo in
          let minfo = List.fold_left (fun minfo s -> genGSignal s n cfg minfo ) minfo iface.ifSignals in
          let minfo = gline "end" minfo in
          gblank minfo
        else
          minfo 
      in let minfo = gline ("class " ^ ocamlName ^ "_skel obj = object (self)") minfo in
      let minfo = gline ("  method as_" ^ ocamlName ^ " = (obj :> " ^ (nsOCamlType n.namespace n) ^ " Gobject.obj)") minfo in
      let minfo = gblank minfo in
      let cgstate, minfo =
        if isGO
        then
          let cgstate, minfo = group (fun minfo -> cgstate, genInterfaceProperties cfg cgstate minfo n iface) minfo in
          let cgstate, minfo =
          if not (iface.ifSignals = [])
          then
            group (
              fun minfo ->
                let minfo = line "module S = struct" minfo in
                let cgstate, minfo = indent (
                  fun minfo ->
                    let minfo = line "open GtkSignal" minfo in
                    let minfo = line "open Gobject" minfo in
                    let minfo = line "open Data" minfo in
                    let cgstate, minfo = List.fold_left (
                      fun (cgstate, minfo) s ->
                        let action = fun cgstate minfo -> cgstate, genSignal s n cfg minfo in
                        let str = String.concat "" [
                        "Could not generate signal ";
                        name';
                        "::";
                        s.sigName;
                        " *)\n";
                        "(* Error was :";
                         ]
                        in let fallback = fun cgstate minfo e -> cgstate, commentLine minfo (str ^ describeCGError e) in
                        handleCGExc (cgstate, minfo) fallback action
                     ) (cgstate, minfo) iface.ifSignals
                    in let minfo = line "end" minfo in
                (cgstate, minfo)
                ) minfo
              in cgstate, minfo) minfo
          else 
          
            cgstate, minfo
          in cgstate, minfo      
        else
          cgstate, minfo
      in let propNames = List.map (fun x -> x.propName |> hyphensToUnderscores) iface.ifProperties in
      let getSets = (List.map (fun x -> "get_" ^ x) propNames) @ (List.map (fun x -> "set_" ^ x) propNames) in
      let cgstate, minfo =
        group (fun minfo ->
          List.fold_left (fun (cgstate, minfo) m ->
              let mn = m.methodName in
              if not (List.mem (ocamlIdentifier mn) getSets)
              then
                let action = fun cgstate minfo -> genMethod cfg cgstate minfo n m in
                let str = "(* Could not generate method " ^ name' ^ "::" ^ mn.name ^ " *)\n" ^ "(* Error was: " in
                let fallback = fun cgstate minfo e -> cgstate, (line (str ^ describeCGError e ^ " *)") minfo) in
                handleCGExc (cgstate, minfo) fallback action
              else cgstate, minfo
            ) (cgstate, minfo) iface.ifMethods
          ) minfo
      in let minfo = gline "end" minfo in
      cgstate, gblank minfo

