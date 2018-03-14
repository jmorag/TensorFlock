open Ast

type sexpr = typ * sexpr_detail
and sexpr_detail = 
    SLiteral of int
  | SFliteral of string
  | SBoolLit of bool
  | STLit of shape * string list 
  | SId of string
  | SUnop of uop * sexpr
  (* | SBinop of sexpr * binop * sexpr *)
  | SAop of sexpr * aop * sexpr
  | SBoolop of sexpr * bop * sexpr
  | SRop of sexpr * rop * sexpr
  | SApp of sexpr * sexpr
  | SCondExpr of sexpr * sexpr * sexpr
  | STensorIdx of shape * string * sexpr list

type sfunc = {
    sfname : string;
    stype : typ;
    sfparams : string list;
    sfexpr : sexpr;
    sscope : sfunc list;
}

type sprogram = sexpr * sfunc list
