(******************************************************************************
 *
 * Seq OCaml 
 * stmt.ml: Statement AST parsing module
 *
 * Author: inumanag
 *
 ******************************************************************************)

open Core
open Err
open Ast

(** This module is an implementation of [Intf.Stmt] module that
    describes statement AST parser.
    Requires [Intf.Expr] for parsing expressions ([parse] and [parse_type]) *)
module StmtParser (E : Intf.Expr) : Intf.Stmt =
struct
  open ExprNode
  open StmtNode

  (* ***************************************************************
     Public interface
     *************************************************************** *)
  
  (** [parse context expr] dispatches statement AST to the proper parser 
      and finalizes the processed statement. *)
  let rec parse (ctx: Ctx.t) (pos, node) =
    let stmt = match node with
      | Break    p -> parse_break    ctx pos p
      | Continue p -> parse_continue ctx pos p
      | Expr     p -> parse_expr     ctx pos p
      | Assign   p -> parse_assign   ctx pos p
      | Del      p -> parse_del      ctx pos p
      | Print    p -> parse_print    ctx pos p
      | Return   p -> parse_return   ctx pos p
      | Yield    p -> parse_yield    ctx pos p
      | Assert   p -> parse_assert   ctx pos p
      | Type     p -> parse_type     ctx pos p
      | If       p -> parse_if       ctx pos p
      | While    p -> parse_while    ctx pos p
      | For      p -> parse_for      ctx pos p
      | Match    p -> parse_match    ctx pos p
      | Extern   p -> parse_extern   ctx pos p
      | Extend   p -> parse_extend   ctx pos p
      | Import   p -> parse_import   ctx pos p
      | Pass     p -> parse_pass     ctx pos p
      | Try      p -> parse_try      ctx pos p
      | Throw    p -> parse_throw    ctx pos p
      | Global   p -> parse_global   ctx pos p
      | Generic 
        Function p -> parse_function ctx pos p
      | Generic 
        Class    p -> parse_class    ctx pos p 
    in
    finalize ctx stmt pos

  (** [parse_module context module] parses module AST.
      A module is just a simple list of statements. *)
  and parse_module (ctx: Ctx.t) mdl = 
    match mdl with
    | Module stmts -> 
      ignore @@ List.map stmts ~f:(parse ctx)

  (* ***************************************************************
     Node parsers
     ***************************************************************
     Each AST node is dispatched to its parser function.
     Each parser function [f] is called as [f context position data]
     where [data] is a tuple varying from node to node. *)
  
  and parse_pass _ _ _ =
    Llvm.Stmt.pass ()

  and parse_break _ _ _ =
    Llvm.Stmt.break ()
    
  and parse_continue _ _ _ =
    Llvm.Stmt.continue ()

  and parse_expr ctx pos expr =
    match snd expr with
    | Id "___dump___" ->
      Ctx.dump ctx;
      Llvm.Stmt.pass ()
    | _ ->
      let expr = E.parse ctx expr in
      Llvm.Stmt.expr expr

  and parse_assign ctx pos (lh, rh, shadow) =
    match lh, rh with
    | [lhs], [rhs] ->
      let rh_expr = E.parse ctx rhs in
      parse_assign_helper ctx pos (lhs, rh_expr, shadow)
    | lh, rh when List.length lh <> List.length rh ->
      serr ~pos "RHS length must match LHS";
    | _, _ ->
      let var_stmts = List.map rh ~f:(fun rhs ->
        let rh_expr = E.parse ctx rhs in
        finalize ctx (Llvm.Stmt.var rh_expr) pos) 
      in
      List.iter (List.zip_exn lh var_stmts) ~f:(fun ((pos, _) as lhs, varst) ->
        let rh_expr = Llvm.Expr.var (Llvm.Var.var_of_stmt varst) in
        let stmt = parse_assign_helper ctx pos (lhs, rh_expr, shadow) in
        ignore @@ finalize ctx stmt pos);
      Llvm.Stmt.pass ()

  and parse_assign_helper ctx pos ((pos, lhs), rh_expr, shadow) =
    match lhs with
    | Id var ->
      begin match Hashtbl.find ctx.map var with
      | Some (Ctx.Assignable.Var (v, { base; global; _ }) :: _) 
        when (not shadow) && ((ctx.base = base) || global) -> 
        Llvm.Stmt.assign v rh_expr
      | Some (Ctx.Assignable.(Type _ | Func _) :: _) ->
        serr ~pos "cannot assign functions or types"
      | _ ->
        let var_stmt = Llvm.Stmt.var rh_expr in
        Ctx.add ctx var @@ Ctx.var ctx (Llvm.Var.var_of_stmt var_stmt);
        var_stmt
      end
    | Dot(lh_lhs, lh_rhs) -> (* a.x = b *)
      Llvm.Stmt.assign_member (E.parse ctx lh_lhs) lh_rhs rh_expr
    | Index(var_expr, [index_expr]) -> (* a[x] = b *)
      let var_expr = E.parse ctx var_expr in
      let index_expr = E.parse ctx index_expr in
      Llvm.Stmt.assign_index var_expr index_expr rh_expr
    | _ ->
      serr ~pos "assignment requires Id / Dot / Index on LHS"
    
  and parse_del ctx pos exprs =
    List.iter exprs ~f:(fun (pos, node) ->
      match node with
      | Index(lhs, [rhs]) ->
        let lhs_expr = E.parse ctx lhs in
        let rhs_expr = E.parse ctx rhs in
        let stmt = Llvm.Stmt.del_index lhs_expr rhs_expr in
        ignore @@ finalize ctx stmt pos
      | Id var ->
        failwith "stmt/parse_del -- can't remove variable"
      | _ -> 
        serr ~pos "cannot del non-index expression");
    Llvm.Stmt.pass ()

  and parse_print ctx pos exprs =
    let str_node s = 
      (pos, ExprNode.String(s))
    in
    List.iteri exprs ~f:(fun i ((pos, _) as expr) ->
      if i > 0 then begin
        let stmt = Llvm.Stmt.print 
          (E.parse ctx @@ str_node " ") 
        in
        ignore @@ finalize ctx stmt pos
      end;
      let stmt = Llvm.Stmt.print (E.parse ctx expr) in
      ignore @@ finalize ctx stmt pos);
    Llvm.Stmt.print (E.parse ctx @@ str_node "\n")

  and parse_return ctx pos ret =
    match ret with
    | None ->
      Llvm.Stmt.return Ctypes.null
    | Some ret ->
      let expr = E.parse ctx ret in
      let ret_stmt = Llvm.Stmt.return expr in
      Llvm.Func.set_return ctx.base ret_stmt;
      ret_stmt

  and parse_yield ctx pos ret =
    match ret with
    | None ->
      Llvm.Stmt.yield Ctypes.null
    | Some ret -> 
      let expr = E.parse ctx ret in
      let yield_stmt = Llvm.Stmt.yield expr in
      Llvm.Func.set_yield ctx.base yield_stmt;
      yield_stmt

  and parse_assert ctx pos exprs =
    List.iter exprs ~f:(function (pos, _) as expr ->
      let expr = E.parse ctx expr in
      let stmt = Llvm.Stmt.assrt expr in
      ignore @@ finalize ctx stmt pos);
    Llvm.Stmt.pass ()

  and parse_type ctx pos (name, args) =
    let arg_names, arg_types =  
      List.map args ~f:(function
        | (pos, { name; typ = None }) ->
          serr ~pos "type member %s must have type specification" name
        | (_,   { name; typ = Some t }) -> 
          (name, t)) 
      |> List.unzip
    in
    if is_some @@ Ctx.in_scope ctx name then
      serr ~pos "type %s already defined" name;
    let arg_types = List.map arg_types ~f:(E.parse_type ctx) in
    let typ = Llvm.Type.record arg_names arg_types in
    Ctx.add ctx name (Ctx.Assignable.Type typ);
    Llvm.Stmt.pass ()

  and parse_while ctx pos (cond, stmts) =
    let cond_expr = E.parse ctx cond in
    let while_stmt = Llvm.Stmt.while_loop cond_expr in

    let block = Llvm.Stmt.Block.while_loop while_stmt in
    add_block { ctx with block } stmts;

    while_stmt

  (** [parse_for ?next context position data] parses for statement AST. 
      `next` points to the nested for in the generator expression.  *)
  and parse_for ?next ctx pos (for_vars, gen_expr, stmts) =
    let gen_expr = E.parse ctx gen_expr in
    let for_stmt = Llvm.Stmt.loop gen_expr in
    let block = Llvm.Stmt.Block.loop for_stmt in
    let for_ctx = { ctx with block } in

    Ctx.add_block for_ctx;
    let var = Llvm.Var.loop for_stmt in
    begin match for_vars with
      | [name] ->
        Ctx.add for_ctx name (Ctx.var ctx var)
      | for_vars -> 
        let var_expr = Llvm.Expr.var var in
        List.iteri for_vars ~f:(fun idx var_name ->
          let expr = Llvm.Expr.lookup var_expr (Llvm.Expr.int idx) in
          let var_stmt = Llvm.Stmt.var expr in
          ignore @@ finalize for_ctx var_stmt pos;
          let var = Llvm.Var.var_of_stmt var_stmt in
          Ctx.add for_ctx var_name (Ctx.var ctx var))
    end;
    let _ = match next with 
      | Some next -> 
        next ctx for_ctx for_stmt
      | None -> 
        ignore @@ List.map stmts ~f:(parse for_ctx)
    in
    Ctx.clear_block for_ctx;

    for_stmt

  and parse_if ctx pos cases =
    let if_stmt = Llvm.Stmt.cond () in
    List.iter cases ~f:(function (_, { cond; cond_stmts }) ->
      let block = match cond with
        | None ->
          Llvm.Stmt.Block.elseb if_stmt
        | Some cond_expr ->
          let expr = E.parse ctx cond_expr in
          Llvm.Stmt.Block.elseif if_stmt expr
      in
      add_block { ctx with block } cond_stmts);
    if_stmt

  and parse_match ctx pos (what, cases) =
    let what = E.parse ctx what in
    let match_stmt = Llvm.Stmt.matchs what in
    List.iter cases ~f:(fun (_, { pattern; case_stmts }) ->
      let pat, var = match pattern with
        | BoundPattern(name, pat) ->
          Ctx.add_block ctx;
          let pat = parse_pattern ctx pos pat in
          let pat = Llvm.Stmt.Pattern.bound pat in
          Ctx.clear_block ctx;
          pat, Some(name, Llvm.Var.bound_pattern pat)
        | _ as pat ->
          Ctx.add_block ctx;
          let pat = parse_pattern ctx pos pat in
          Ctx.clear_block ctx;
          pat, None
      in
      let block = Llvm.Stmt.Block.case match_stmt pat in
      add_block { ctx with block } case_stmts ~preprocess:(fun ctx ->
        match var with 
        | Some(n, v) -> Ctx.add ctx n (Ctx.var ctx v) 
        | None -> ()));
    match_stmt
  
  and parse_extern ctx pos (lang, dylib, (_, { name; typ }), args) =
    if lang <> "c" && lang <> "C" then
      serr ~pos "only C external functions are currently supported";
    if is_some @@ Ctx.in_block ctx name then
      serr ~pos "function %s already exists" name;
    
    let names, types = 
      List.map args ~f:(fun (_, { name; typ }) ->
        name, E.parse_type ctx (Option.value_exn typ))
      |> List.unzip
    in
    let fn = Llvm.Func.func name in
    Llvm.Func.set_args fn names types;
    Llvm.Func.set_extern fn;
    let typ = E.parse_type ctx (Option.value_exn typ) in
    Llvm.Func.set_type fn typ;
    
    Ctx.add ctx name (Ctx.Assignable.Func fn);
    Llvm.Stmt.func fn

  and parse_extend ctx pos (name, stmts) =
    let typ = match Ctx.in_scope ctx name with
      | Some (Ctx.Assignable.Type t) -> t
      | _ -> serr ~pos "cannot extend non-existing class %s" name
    in
    let new_ctx = { ctx with map = Hashtbl.copy ctx.map } in
    ignore @@ List.map stmts ~f:(function
      | pos, Function f -> parse_function new_ctx pos f ~cls:typ
      | _ -> failwith "classes only support functions as members");

    Llvm.Stmt.pass ()
  
  (** [parse_import ?ext context position data] parses import AST.
      Import file extension is set via [seq] (default is [".seq"]). *)
  and parse_import ?(ext="seq") ctx pos imports =
    List.iter imports ~f:(fun ((pos, what), _) ->
      let file = sprintf "%s/%s.%s" (Filename.dirname ctx.filename) what ext in
      match Sys.file_exists file with
      | `Yes -> 
        ctx.parse_file ctx file
      | `No | `Unknown -> 
        let seqpath = Option.value (Sys.getenv "SEQ_PATH") ~default:"" in
        let file = sprintf "%s/%s.%s" seqpath what ext in
        match Sys.file_exists file with
        | `Yes -> 
          ctx.parse_file ctx file
        | `No | `Unknown -> 
          serr ~pos "cannot locate module %s" what);
    Llvm.Stmt.pass ()

  (** [parse_function ?cls context position data] parses function AST.
      Set `cls` to `Llvm.Types.typ` if you want a function to be 
      a class `cls` method. *)
  and parse_function ?cls ctx pos ((_, { name; typ }), types, args, stmts) =
    if is_some @@ Ctx.in_block ctx name then
      serr ~pos "function %s already exists" name;

    let fn = Llvm.Func.func name in
    begin match cls with 
      | Some cls -> Llvm.Type.add_cls_method cls name fn
      | None -> Ctx.add ctx name (Ctx.Assignable.Func fn)
    end;

    let new_ctx = 
      { ctx with 
        base = fn; 
        stack = Stack.create ();
        block = Llvm.Stmt.Block.func fn;
        map = Hashtbl.copy ctx.map } 
    in
    Ctx.add_block new_ctx;
    let names, types = parse_generics 
      new_ctx 
      types args
      (Llvm.Generics.Func.set_number fn)
      (fun idx name ->
        Llvm.Generics.Func.set_name fn idx name;
        Llvm.Generics.Func.get fn idx) 
    in
    Llvm.Func.set_args fn names types;

    Option.value_map typ
      ~f:(fun typ -> Llvm.Func.set_type fn (E.parse_type new_ctx typ))
      ~default:();

    add_block new_ctx stmts 
      ~preprocess:(fun ctx ->
        List.iter names ~f:(fun name ->
          let var = Ctx.var ctx (Llvm.Func.get_arg fn name) in
          Ctx.add ctx name var));
    Llvm.Stmt.func fn
  
  and parse_class ctx pos ((name, types, args, stmts) as stmt) =
    if is_some @@ Ctx.in_scope ctx name then
      serr ~pos "class %s already exists" name;
    List.iter args ~f:(fun (pos, { name; typ }) ->
      if is_none typ then 
        serr ~pos "class field %s does not have type" name);

    let typ = Llvm.Type.cls name in
    Ctx.add ctx name (Ctx.Assignable.Type typ);

    let new_ctx = 
      { ctx with 
        map = Hashtbl.copy ctx.map;
        stack = Stack.create () } 
    in
    Ctx.add_block new_ctx;
    let names, types = parse_generics 
      new_ctx 
      types args
      (Llvm.Generics.Type.set_number typ)
      (fun idx name ->
        Llvm.Generics.Type.set_name typ idx name;
        Llvm.Generics.Type.get typ idx) 
    in
    Llvm.Type.set_cls_args typ names types;
    ignore @@ List.map stmts ~f:(function
      | pos, Function f -> parse_function new_ctx pos f ~cls:typ
      | _ -> failwith "classes only support functions as members");
    Llvm.Type.set_cls_done typ;

    Llvm.Stmt.pass ()

  and parse_try ctx pos (stmts, catches, finally) =
    let try_stmt = Llvm.Stmt.trycatch () in

    let block = Llvm.Stmt.Block.try_block try_stmt in
    add_block { ctx with block ; trycatch = try_stmt } stmts;

    List.iteri catches ~f:(fun idx (pos, { exc; var; stmts }) ->
      let typ = match exc with
        | Some exc -> E.parse_type ctx (pos, Id(exc)) 
        | None -> Ctypes.null 
      in
      let block = Llvm.Stmt.Block.catch try_stmt typ in
      add_block { ctx with block } stmts
        ~preprocess:(fun ctx ->
          Option.value_map var 
            ~f:(fun var ->
              let v = Llvm.Var.catch try_stmt idx in
              Ctx.add ctx var (Ctx.var ctx v))
            ~default: ()) 
    );

    Option.value_map finally 
      ~f:(fun final ->
        let block = Llvm.Stmt.Block.finally try_stmt in
        add_block { ctx with block } final)
      ~default:();

    try_stmt

  and parse_throw ctx _ expr =
    let expr = E.parse ctx expr in
    Llvm.Stmt.throw expr

  and parse_global ctx _ vars =
    List.iter vars ~f:(fun (pos, var) -> 
      match Hashtbl.find ctx.map var with
      | Some (Ctx.Assignable.Var (v, { base; global; toplevel }) :: rest) ->
        if (ctx.base = base) || global then 
          serr ~pos "symbol '%s' either local or already set as global" var;
        Llvm.Var.set_global v;
        let new_var = Ctx.Assignable.Var 
          (v, Ctx.Assignable.{ base; global = true; toplevel }) 
        in
        Hashtbl.set ctx.map ~key:var ~data:(new_var :: rest)
      | _ ->
        serr ~pos "symbol '%s' not found or not a variable" var
    );
    Llvm.Stmt.pass ()

  (* ***************************************************************
     Helper functions
     *************************************************************** *)

  (** [finalize ~add context statement position] finalizes [Llvm.Types.stmt]
      by setting its base to [context.base], its position to [position]
      and by adding the [statement] to the current block ([context.block])
      if [add] is [true]. Returns the finalized statement. *)
  and finalize ?(add=true) ctx stmt pos =
    Llvm.Stmt.set_base stmt ctx.base;
    Llvm.Stmt.set_pos stmt pos;
    if add then
      Llvm.Stmt.Block.add_stmt ctx.block stmt;
    stmt 
  
  (** [add_block ?preprocess context statements] creates a new block within
      [context[ and adds [statements] to that block. 
      [preprocess context], if provided, is run after the block is created 
      to initialize the block. *)
  and add_block ctx ?(preprocess=(fun _ -> ())) stmts =
    Ctx.add_block ctx;
    preprocess ctx;
    ignore @@ List.map stmts ~f:(parse ctx);
    Ctx.clear_block ctx

  (** Helper for parsing match patterns *)
  and parse_pattern ctx pos = function
    | StarPattern ->
      Llvm.Stmt.Pattern.star ()
    | BoundPattern _ ->
      serr ~pos "invalid bound pattern"
    | IntPattern i -> 
      Llvm.Stmt.Pattern.int i
    | BoolPattern b -> 
      Llvm.Stmt.Pattern.bool b
    | StrPattern s -> 
      Llvm.Stmt.Pattern.str s
    | SeqPattern s -> 
      Llvm.Stmt.Pattern.seq s
    | TuplePattern tl ->
      let tl = List.map tl ~f:(parse_pattern ctx pos) in
      Llvm.Stmt.Pattern.record tl
    | RangePattern (i, j) -> 
      Llvm.Stmt.Pattern.range i j
    | ListPattern tl ->
      let tl = List.map tl ~f:(parse_pattern ctx pos) in
      Llvm.Stmt.Pattern.array tl
    | OrPattern tl ->
      let tl = List.map tl ~f:(parse_pattern ctx pos) in
      Llvm.Stmt.Pattern.orp tl
    | WildcardPattern wild ->
      let pat = Llvm.Stmt.Pattern.wildcard () in
      if is_some wild then begin
        let var = Llvm.Var.bound_pattern pat in
        Ctx.add ctx (Option.value_exn wild) (Ctx.var ctx var)
      end;
      pat
    | GuardedPattern (pat, expr) ->
      let pat = parse_pattern ctx pos pat in
      let expr = E.parse ctx expr in
      Llvm.Stmt.Pattern.guarded pat expr

  (** Helper for parsing generic parameters. 
      Parses generic parameters, assigns names to unnamed generics and
      calls C++ APIs to denote generic functions/classes.
      Also adds generics types to the context. *)
  and parse_generics ctx generic_types args set_generic_count get_generic =
    let names, types = 
      List.map args ~f:(function
        | _, { name; typ = Some (typ) } -> 
          name, typ
        | pos, { name; typ = None }-> 
          name, (pos, ExprNode.Generic (sprintf "``%s" name)))
      |> List.unzip
    in
    let type_args = List.map generic_types ~f:snd in
    let generic_args = List.filter_map types ~f:(fun x ->
      match snd x with
      | Generic(g) when String.is_prefix g ~prefix:"``" -> Some g
      | _ -> None)
    in
    let generics = 
      List.append type_args generic_args
      |> List.dedup_and_sort ~compare in
    set_generic_count (List.length generics);

    List.iteri generics ~f:(fun cnt key ->
      Ctx.add ctx key (Ctx.Assignable.Type (get_generic cnt key)));
    let types = List.map types ~f:(E.parse_type ctx) in
    names, types
end