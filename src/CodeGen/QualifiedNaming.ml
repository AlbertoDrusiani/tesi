open Util
open API
open ModulePath
open Naming
open Code
(*open ModulePath*)
open GIR.BasicTypes

let signalHaskellName sn =
  match String.split_on_char '-' sn with
  | w::ws -> w ^ (String.concat "" (List.map ucFirst ws))
  | [] -> ""


let submoduleLocation n api =
  match n, api with
  | _, APIConst _ -> {modulePathToList = ["Constants"]}
  | _, APIFunction _ -> {modulePathToList = ["Functions"]}
  | _, APICallback _ -> {modulePathToList = ["Callbacks"]}
  | _, APIEnum _ -> {modulePathToList = ["Enums"]}
  | _, APIFlags _ -> {modulePathToList = ["Enums"]}
  | n, APIInterface _ -> {modulePathToList = [(upperName n)]}
  | n, APIObject _ -> {modulePathToList = [(upperName n)]}
  | n, APIStruct _ -> {modulePathToList = [(upperName n)]}
  | n, APIUnion _ -> {modulePathToList = [(upperName n)]}


let nsOCamlClass minfo nm =
  match nm with
  | {namespace = "Gtk"; name = "Widget"} -> "GObj.widget"
  | _ ->
    let currNs = minfo.modulePath |> modulePathNS in
    let currMod = minfo.modulePath |> dotWithPrefix |> String.split_on_char '.' |> List.rev |> List.hd in
    match (currNs = nm.namespace), (currMod = nm.name) with
    | true, true -> ocamlIdentifier nm
    | true, false -> nm.name ^ "G." ^ ocamlIdentifier nm
    | false, _ -> "GI" ^ nm.namespace ^ "." ^ nm.name ^ "G." ^ ocamlIdentifier nm
