(*
open BasicTypes

(*open GObject_introspection*)

module GI = GObject_introspection
module B = Bindings

(*da sistemare i due campi mancanti e value in stringa *)
type constant = { 
    constantType: type_ml option;
    constantValue: GI.Types.argument_t Ctypes.union Ctypes.ptr;
   (*constantCType: string;
    constantDocumentation: string;*)
    constantIsDeprecated: bool;
    }
   

(*passo alla funzione la constant_info da fuori perché sto già facendo pattern matching*)
let parseConstant constant_info = 
    prerr_endline("pppppppppppp CONSTANT ppppppppppp");
    let name = GI.Constant_info.to_baseinfo constant_info |> getName in
    (name,
    { constantValue = GI.Constant_info.get_value constant_info;
      constantType = GI.Constant_info.get_type constant_info |> cast_to_type_ml;
      constantIsDeprecated = GI.Constant_info.to_baseinfo constant_info |> GI.Base_info.is_deprecated;
    })*)
