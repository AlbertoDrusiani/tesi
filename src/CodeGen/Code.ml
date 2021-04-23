open API
open ModulePath
open Naming
(*open Util*)
(*open ModulePath*)
open GIR.BasicTypes
open Config

type code = Code of (code_token list)


and code_token =
      | Line of string
      | Indent of code
      | Group of code
      | IncreaseIndent


let getCode c =
  match c with
  | Code x -> x

let emptyCode =
  Code []


let isCodeEmpty c =
    match c with
    | Code seq_ -> List.length seq_ == 0


let codeSingleton t =
  Code [t]


type named_section =
  | MethodSection
  | PropertySection
  | SignalSection
  | EnumSection
  | FlagSection


type haddock_section =
  | ToplevelSection
  | NamedSubsection of named_section*string


type deps =
  StringSet.t

type symbol_name = string


type export_type =
  | ExportSymbol of haddock_section
  | ExportTypeDecl
  | ExportModule


type export =
  { exportType: export_type;
    exportSymbol: symbol_name;
  }


type module_info =
  { modulePath: module_path;
    moduleCode: code;
    bootCode: code;
    gCode: code;
    cCode: code;
    hCode: code;
    tCode: code;
    submodules: module_info StringMap.t;
    moduleDeps: deps; 
    cDeps: deps;
    moduleExports: export list;
    qualifiedImports: ModulePathSet.t;
    (*sectionDocs*)
  }


type module_flag = ImplicitPervasives

let emptyModule m =
  { modulePath = m;
    moduleCode = emptyCode;
    bootCode = emptyCode;
    cCode = emptyCode;
    tCode = emptyCode;
    hCode = emptyCode;
    gCode = emptyCode;
    submodules = StringMap.empty;
    moduleDeps = StringSet.empty;
    cDeps = StringSet.empty;
    moduleExports = [];
    qualifiedImports = ModulePathSet.empty;
   (* sectionDocs = *)
  }


type code_gen_config = {
  hConfig: config;
  loadedAPIs: api NameMap.t;
  (*c2hMap: TODO da implementare il modulo gtk-doc*) 
}

exception CGErrorNotImplemented of string
exception CGErrorBadIntrospectionInfo of string
exception CGErrorMissingInfo of string


type named_tyvar =
  | SingleCharTyvar of char
  | IndexedTyvar of string*int

type cg_state = {
  cgsNextAvailableTyvar: named_tyvar;
}

let emptyCGState =
  {cgsNextAvailableTyvar = SingleCharTyvar 'b'}

let cleanInfo info =
  { info with 
    moduleCode = emptyCode;
    bootCode = emptyCode;
    cCode = emptyCode;
    tCode = emptyCode;
    hCode = emptyCode;
    gCode = emptyCode;
    submodules = StringMap.empty;
    moduleDeps = StringSet.empty;
    moduleExports = [];
    qualifiedImports = ModulePathSet.empty;
    }


(*let evalCodeGen cfg apis mPath cg =
  let initialInfo = emptyModule mPath in
  let cfg' = {hConfig = cfg; loadedAPIs = apis} in
  unwrapCodeGen cg cfg' (emptyCGState, initialInfo)
*)

 (*TODO questa è la funzione che mi faccio per creare il contesto per poi passarlo in giro
   * la semantica dovrebbe essere simile allo stato della monade. Sta roba viene fatta
   * nell'evalCodegen in Haskell, potevo chiamarla così ma qua non valuto niente*)
  (* config -> Map (name, api) -> module_path -> (codegen_config, cgstate, module_info)*)
  
let setContext cfg apis mPath =
    let initialInfo = emptyModule mPath in
    let cfg' = { hConfig = cfg; loadedAPIs = apis; (*c2hMap = cToHaskellMap (NameMap.to_seq apis |> List.of_seq)*)} in
     cfg', emptyCGState, initialInfo 


let rec mergeInfoState oldState newState =
  let newDeps = StringSet.union (oldState.moduleDeps) (newState.moduleDeps) in
  let newCDeps = StringSet.union (oldState.cDeps) (newState.cDeps) in
  let union_f _ m1 m2 = Some (mergeInfo m1 m2) in
  let newSubmodules = StringMap.union union_f oldState.submodules newState.submodules in
  let newExports = oldState.moduleExports @ newState.moduleExports in
  let newImports = ModulePathSet.union oldState.qualifiedImports newState.qualifiedImports in
  let newCCode = Code ((getCode oldState.cCode) @ (getCode newState.cCode)) in
  let newHCode = Code ((getCode oldState.hCode) @ (getCode newState.hCode)) in
  let newTCode = Code ((getCode oldState.tCode) @ (getCode newState.tCode)) in
  let newGCode = Code ((getCode oldState.gCode) @ (getCode newState.gCode)) in
  let newBoot = Code ((getCode oldState.bootCode) @ (getCode newState.bootCode)) in
  {oldState with 
   moduleDeps = newDeps;
   cDeps = newCDeps;
   submodules = newSubmodules;
   moduleExports = newExports;
   qualifiedImports = newImports;
   bootCode = newBoot;
   cCode = newCCode;
   tCode = newTCode;
   hCode = newHCode;
   gCode = newGCode;
  }

and mergeInfo oldInfo newInfo =
  let info = mergeInfoState oldInfo newInfo in
  { info with moduleCode = Code (getCode (oldInfo.moduleCode) @ getCode (newInfo.moduleCode))}



let addSubmodule minfo mName smInfo =
  match StringMap.mem mName minfo.submodules with
  | true -> {minfo with submodules = StringMap.add mName (mergeInfo smInfo minfo) minfo.submodules} 
  | false -> {minfo with submodules = StringMap.add mName smInfo minfo.submodules}


(*TODO qua viene fatta la runCodeGen e può sollevarsi un errore, gestisco in seguito*)
(*FIXME sta roba è bacatissima sicuro, manca la gestione del cgstate e la runcodegen come funziona?*)
(* code_gen_config -> cgstate -> module_info -> string -> (cfg * cgstate *)
let submodule' (cfg, cgstate, minfo) mName =
  let info = emptyModule ({modulePathToList = minfo.modulePath.modulePathToList @ [mName]}) in
  cfg, cgstate, (addSubmodule minfo mName info)


(* code_gen_config*cgstate*module_info -> module_path -> (cfg * cgstate * minfo *)
let rec submodule (cfg, cgstate, minfo) mPath =
  match mPath.modulePathToList with
  | [] -> cfg, cgstate, minfo
  | m::ms -> submodule' (submodule (cfg, cgstate, minfo) {modulePathToList = ms}) m


let addCDep minfo dep =
  {minfo with cDeps = StringSet.add dep (minfo.cDeps)}

let findAPIByName cfg n =
  let apis = cfg.loadedAPIs in
  match NameMap.find_opt n apis with
  | Some api -> api
  | None -> assert false (*FIXME gestione errori*)




(* module_info -> code_token -> module_info *)
let tellCode minfo c =
  { minfo with moduleCode = Code (getCode(minfo.moduleCode) @ [c])}

(* module_info -> string -> module_info *)
let line minfo s =
  tellCode minfo (Line s)


(* module_info -> code_token -> module_info *)
let tellGCode minfo c =
  { minfo with gCode = Code (getCode(minfo.gCode) @ [c])}

(* module_info -> string -> module_info *)
let gline minfo s =
  tellGCode minfo (Line s)

(*let group' (cfg, cgstate, minfo) codeTeller blanker =*)
  

(*let group (cfg, cgstate, minfo) =
  group' (cfg, cgstate, minfo) tellCode blank*)
  

let cline minfo l =
  let info = cleanInfo minfo in
  let info = line info l in
  let code = info.moduleCode in
  let minfo = mergeInfoState minfo info in
  { minfo with cCode = Code ((getCode(minfo.cCode)) @ getCode(code))}


(* module_info -> code_token -> module_info *)
let tellHCode minfo c =
  { minfo with hCode = Code (getCode(minfo.hCode) @ [c])}

(* module_info -> string -> module_info *)
let hline minfo s =
  tellHCode minfo (Line s)

(* module_info -> code_token -> module_info *)
let tellTCode minfo c =
  { minfo with tCode = Code (getCode(minfo.tCode) @ [c]) }

(* module_info -> string -> module_info *)
let tline minfo s =
  tellTCode minfo (Line s)


let commentLine minfo t =
  line minfo ("(* " ^ t ^ " *)")

let blank minfo =
  line minfo ""

let gblank minfo =
  gline minfo ""


let indent minfo f param =
  let info = cleanInfo minfo in
  let info = f info param in
  let code = info.moduleCode in
  let minfo = mergeInfoState minfo info in
  minfo = tellCode minfo (Indent code)


let gindent minfo f param =
  let info = cleanInfo minfo in
  let info = f info param in
  let code = info.moduleCode in
  let minfo = mergeInfoState minfo info in
  minfo = tellGCode minfo (Indent code)


let group minfo f param =
  let info = cleanInfo minfo in
  let info = f info param in
  let code = info.moduleCode in
  let minfo = mergeInfoState minfo info in
  let minfo = tellCode minfo (Group code) in
  blank minfo


let ggroup minfo f param =
  let info = cleanInfo minfo in
  let info = f info param in
  let code = info.moduleCode in
  let minfo = mergeInfoState minfo info in
  let minfo = tellGCode minfo (Group code) in
  gblank minfo


let nameToClassType n =
  let ocamlId = ocamlIdentifier n in
  String.concat "\n"
    ["class type " ^ ocamlId ^ "_o = object";
     "  method as_" ^ ocamlId ^ " : t Gobject.obj";
     "end"]

(* name list -> string *)
let ifacesTypes n =
  match n with
  | [] -> ""
  | xs -> " | `" ^ String.concat " | `" (List.map ocamlIdentifierNs xs)

(* string -> string *)
let typeDeclText t =
  "type t = " ^ t

(* name -> name option -> name list -> string *)
let textToOCamlType n mn nl =
  match n, mn, nl with
  | {namespace = "GObject"; name = "Object"}, _, _ -> typeDeclText "[`giu]"
  | {namespace = "Gtk"; name = "Widget"}, _, _ -> typeDeclText "[`giu | `widget]"
  | n, None, ifaces -> 
    typeDeclText ("[ " ^ ocamlIdentifierNs n ^ ifacesTypes ifaces ^ "]")
  | n, (Some {namespace = "GObject"; name = "Object"}), ifaces ->
    typeDeclText ("[`giu | `]" ^ ocamlIdentifierNs n ^ ifacesTypes ifaces ^ "]")
  | n, (Some nm), ifaces when n.namespace = nm.namespace ->
    typeDeclText  ("[" ^ nsOCamlType n.namespace nm ^ " | `" ^ ocamlIdentifierNs n ^ ifacesTypes ifaces ^ "]")
  | n, Some pn, ifaces ->
    typeDeclText ("[" ^ nsOCamlType n.namespace pn ^ " | `" ^ ocamlIdentifierNs n ^ ifacesTypes ifaces ^ "]")


let getParent' api =
  let rename n =
    match n with
    | Some {namespace = "GObject"; name = "InitiallyUnowned"} -> Some ({namespace = "GObject"; name = "Object"})
    | x -> x
  in match api with
  | APIObject o -> rename o.objParent 
  | _ -> None


let rec instanceTree cfg n =
  let api = findAPIByName cfg n in
  match getParent' api with
  | Some p -> p :: (instanceTree cfg p)
  | None -> []


let dotWithPrefix mp = dotModulePath mp


(* code_gen_config -> module_info -> name -> module_info *)
let addTypeFile cfg minfo n =
  let api = findAPIByName cfg n in
  match api with
  | APIConst _ -> minfo
  | APIFunction _ -> minfo
  | APICallback _ -> minfo
  | APIEnum _ -> minfo
  | APIFlags _ -> minfo
  | APIInterface _ ->
    let step1 = tline minfo (textToOCamlType n None []) in
    let step2 = tline step1 "" in
    tline step2 (nameToClassType n)
  | APIObject o ->
    let parents = instanceTree cfg n in
    let info = 
      begin
      match parents with
       | [] -> tline minfo (textToOCamlType n None o.objInterfaces)
       | parent::_ -> tline minfo (textToOCamlType n (Some parent) o.objInterfaces)
      end
    in let step1 = tline info "" in
    tline step1 (nameToClassType n)
  | APIStruct _ -> tline minfo "type t"
  | APIUnion _ -> tline minfo "type t"




