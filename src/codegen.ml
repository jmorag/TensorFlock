module L = Llvm
module A = Ast
open Sast

module StringMap = Map.Make(String)
let context = L.global_context ()
let the_module = L.create_module context "TensorFlock"

(* Declare the LLVM versions of all built in types *)
let nat_t = L.i32_type context
let bool_t = L.i1_type context
let i8_t = L.i8_type context
let float_t = L.double_type context

let printf_t = L.var_arg_function_type nat_t [| L.pointer_type i8_t |]
let printf_func = L.declare_function "printf" printf_t the_module

let tensor_t = L.struct_type context [|
    nat_t; (* size: number of doubles the tensor holds *)
    nat_t; (* rank *)
    L.pointer_type nat_t; (* shape *)
    L.pointer_type nat_t; (* number of references *)
    L.pointer_type float_t; (* contents *)
  |]

let talloc_t = L.function_type (L.pointer_type tensor_t) 
    [| nat_t; (* size *)
       L.pointer_type nat_t; (* shape *)
       L.pointer_type float_t (* contents *)
    |]
let talloc_func = L.declare_function "talloc" talloc_t the_module

let print_tensor_t = L.function_type i8_t [| L.pointer_type tensor_t |]
let print_tensor_func = L.declare_function "print_tensor" print_tensor_t the_module

let rec codegen_sexpr (typ, detail) builder = 
  let cond_expr pred cons alt = 
      (* Wholesale copying of the Kaleidescope tutorial's conditional
       * expression codegen *)
      let cond = codegen_sexpr pred builder in
      (* Grab the first block so that we might later add the conditional branch
       * to it at the end of the function. *)
      let start_bb = L.insertion_block builder in
      let the_function = L.block_parent start_bb in

      let then_bb = L.append_block context "then" the_function in
      L.position_at_end then_bb builder;
      let then_val = codegen_sexpr cons builder in

      (* Creating a new then bb allows if_then_else 
       * expressions to be nested recursively *)
      let new_then_bb = L.insertion_block builder in

      let else_bb = L.append_block context "else" the_function in
      L.position_at_end else_bb builder;
      let else_val = codegen_sexpr alt builder in

      (* Creating a new else bb allows if_then_else 
       * expressions to be nested recursively *)
      let new_else_bb = L.insertion_block builder in

      (* Create merge basic block to wire everything up *)
      let merge_bb = L.append_block context "ifcont" the_function in
      L.position_at_end merge_bb builder;

      let incoming = [(then_val, new_then_bb); (else_val, new_else_bb)] in
      let phi = L.build_phi incoming "iftmp" builder in

      L.position_at_end start_bb builder;
      ignore (L.build_cond_br cond then_bb else_bb builder);

      L.position_at_end new_then_bb builder; ignore (L.build_br merge_bb builder);
      L.position_at_end new_else_bb builder; ignore (L.build_br merge_bb builder);

      (* Finally, set the builder to the end of the merge block. *)
      L.position_at_end merge_bb builder;

      phi in
  match typ with
  | A.Unit(A.Nat) ->
    begin
      match detail with
      | SLiteral(i) -> L.const_int nat_t i
      | SAop(sexpr1, aop, sexpr2) ->
        let lhs = codegen_sexpr sexpr1 builder in
        let rhs = codegen_sexpr sexpr2 builder in
        begin
          match aop with
          | A.Add -> L.build_add lhs rhs "addnattmp" builder
          | A.Sub -> L.build_sub lhs rhs "subnattmp" builder
          | A.Mult -> L.build_mul lhs rhs "mulnattmp" builder
          | A.Div -> L.build_udiv lhs rhs "divnattmp" builder
          | A.Mod -> L.build_urem lhs rhs "modnattmp" builder
          | A.Expt -> raise (Failure "WIP")
        end
      | SId(_) -> raise (Failure "WIP")
      | SApp(_,_) -> raise (Failure "Not yet implemented")
      | SCondExpr(pred, cons, alt) -> cond_expr pred cons alt
      | _ -> raise (Failure "Internal error: semant should have rejected this")
    end
  | A.Unit(A.Bool) ->
    begin
      match detail with
      | SBoolLit(b) -> L.const_int bool_t (if b then 1 else 0)
      | SId(_) -> raise (Failure "WIP")
      | SBoolop(sexpr1, bop, sexpr2) ->
        let lhs = codegen_sexpr sexpr1 builder in
        let rhs = codegen_sexpr sexpr2 builder in
        begin
          match bop with
          | A.And -> L.build_and lhs rhs "andtmp" builder
          | A.Or  -> L.build_or  lhs rhs "ortmp"  builder
        end
      | SRop(sexpr1, rop, sexpr2) ->
        let lhs = codegen_sexpr sexpr1 builder in
        let rhs = codegen_sexpr sexpr2 builder in
        begin
          match rop with
          | A.Eq  -> L.build_icmp L.Icmp.Eq  lhs rhs "eqtemp"  builder
          | A.Neq -> L.build_icmp L.Icmp.Ne  lhs rhs "neqtemp" builder
          | A.LT  -> L.build_icmp L.Icmp.Ult lhs rhs "lttemp"  builder
          | A.Leq -> L.build_icmp L.Icmp.Ule lhs rhs "leqtemp" builder
          | A.GT  -> L.build_icmp L.Icmp.Ugt lhs rhs "gttemp"  builder
          | A.Geq -> L.build_icmp L.Icmp.Uge lhs rhs "geqtemp" builder
        end
      | SApp(_,_) -> raise (Failure "WIP")
      | SCondExpr(pred, cons, alt) -> cond_expr pred cons alt
      | _ -> raise (Failure "Internal error: semant should have blocked this")
    end
  (* Tensor of empty shape corresponds to single floating point number *)
  | A.Unit(A.Tensor([])) -> 
    begin
      match detail with  
      | SFliteral(s) -> L.const_float_of_string float_t s
      | SUnop(A.Neg, sexpr) -> 
        L.build_fneg (codegen_sexpr sexpr builder) "negfloattmp" builder
      | SId(_s) -> raise (Failure "Not implemented")
      | SAop(sexpr1, aop, sexpr2) ->
        let lhs = codegen_sexpr sexpr1 builder in
        let rhs = codegen_sexpr sexpr2 builder in
        begin
          match aop with
          | A.Add -> L.build_fadd lhs rhs "addfloattmp" builder
          | A.Sub -> L.build_fsub lhs rhs "subfloattmp" builder
          | A.Mult -> L.build_fmul lhs rhs "mulfloattmp" builder
          | A.Div -> L.build_fdiv lhs rhs "divfloattmp" builder
          | A.Mod -> L.build_frem lhs rhs "modfloattmp" builder
          | A.Expt -> raise (Failure "Exponentiation WIP")
            (* let pow_t = L.function_type float_t [| float_t; float_t |] in *)
            (* let pow_func = L.declare_function "pow" pow_t the_module in *)
            (* L.build_call pow_func [| lhs; rhs |] "pow" builder *)
        end
      | SCondExpr(pred, cons, alt) -> cond_expr pred cons alt
      | SRop(sexpr1, rop, sexpr2) ->
        let lhs = codegen_sexpr sexpr1 builder in
        let rhs = codegen_sexpr sexpr2 builder in
        begin
          match rop with
          | A.Eq  -> L.build_fcmp L.Fcmp.Oeq rhs rhs "feqtemp"  builder
          | A.Neq -> L.build_fcmp L.Fcmp.One lhs rhs "fneqtemp" builder
          | A.LT  -> L.build_fcmp L.Fcmp.Olt lhs rhs "flttemp"  builder
          | A.Leq -> L.build_fcmp L.Fcmp.Ole lhs rhs "fleqtemp" builder
          | A.GT  -> L.build_fcmp L.Fcmp.Ogt lhs rhs "fgttemp"  builder
          | A.Geq -> L.build_fcmp L.Fcmp.Oge lhs rhs "fgeqtemp" builder
        end
      | SApp(_,_) -> raise (Failure "Functions not yet implemented")
      | _ -> raise (Failure "Internal error: semant failed")
    end
  | A.Unit(A.Tensor(_shape)) ->
    begin
      match detail with
      | STLit(contents, literal_shape) -> 
        let tsize = List.fold_left (fun acc elt -> acc * elt) 1 literal_shape in
        let trank = List.length literal_shape in
        let tshape = 
          List.map (L.const_int nat_t) literal_shape |>
          Array.of_list |>
          L.const_array (L.array_type nat_t trank) in
        let trefs = 
          L.const_array (L.array_type nat_t 1) [| L.const_int nat_t 1 |] in
        let tcontents = 
          List.map (L.const_float_of_string float_t) contents |>
          Array.of_list |>
          L.const_array (L.array_type float_t tsize) in
        let tensor = 
          L.const_named_struct tensor_t 
            [| L.const_int nat_t tsize; 
               L.const_int nat_t trank; 
               tshape; 
               trefs; 
               tcontents |] in
        let the_ptr = L.build_malloc (tensor_t) "tensor_ptr" builder in
        ignore @@ L.build_store tensor the_ptr builder; the_ptr
      | _ -> raise (Failure "WIP")
    end
  | _ -> raise (Failure "Not yet implemented")

let translate sprogram =

  let main_ty = L.function_type (nat_t) [||] in
  let main = L.define_function "main" main_ty the_module in
  let builder = L.builder_at_end context (L.entry_block main) in
  let int_format_str = L.build_global_stringptr "%d\n" "fmt" builder in
  let bool_format_str = L.build_global_stringptr "%s\n" "fmt" builder in
  let float_format_str = L.build_global_stringptr "%g\n" "fmt" builder in
  let true_str = L.build_global_stringptr "True" "true_str" builder in
  let false_str = L.build_global_stringptr "False" "false_str" builder in

  let the_expression = codegen_sexpr (fst sprogram) builder
  in ignore @@ (match fst (fst sprogram) with 
    | A.Unit(A.Nat) -> L.build_call printf_func [| int_format_str ; the_expression |]
                 "printf" builder
    | A.Unit(A.Bool) -> L.build_call printf_func [| bool_format_str ; 
            if the_expression = L.const_int bool_t 0 then false_str else true_str |]
                 "printf" builder
    | A.Unit(A.Tensor([])) -> L.build_call printf_func 
                                [| float_format_str ; the_expression |]
                 "printf" builder
    | A.Unit(A.Tensor(_)) -> L.build_call print_tensor_func [| the_expression |]
                 "print_tensor" builder
    | A.Arrow(_,_) -> raise (Failure "Internal error: semant failed")
    );
    ignore @@ L.build_ret (L.const_int nat_t 0) builder;

  the_module
