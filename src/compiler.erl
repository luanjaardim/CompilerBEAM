-module(compiler).
-export([tokenize/2, parse/2, tokenize/3, parse/3, convert/1, visit/1, compile/1, compile_dulang_dir/0]).

tokenize(FileName, Type, Output) ->
    {ok, Bin} = file:read_file(FileName),
    {ok, Tks, _} =
        case Type of
            dulang -> lexer:string(binary_to_list(Bin) ++ "\n__EOF__");
            csp -> csp_lexer:string(binary_to_list(Bin) ++ "\n__EOF__");
            _ -> error
        end,
    if Output -> io:format("~p\n", [Tks]); true -> no_output end, Tks.

tokenize(FileName, Type) -> tokenize(FileName, Type, true).

parse(FileName, Type, Output) ->
    Tks = tokenize(FileName, Type, false),
    {ok, Ast} =
        case Type of
            dulang -> parser:parse(Tks);
            csp -> csp_parser:parse(Tks);
            _ -> error
        end,
    if Output -> io:format("~p\n", [Ast]); true -> no_output end, Ast.

parse(FileName, Type) -> parse(FileName, Type, true).

% Transforms an Erlang file into its Abstract Format
convert(FileName) -> 
    {ok, _} = compile:file(FileName, [to_pp, report_errors]),
    FileNameWithoutExt = filename:rootname(FileName),
    {ok, Bin} = file:read_file(FileNameWithoutExt ++ ".P"),
    io:format("~s\n", [binary_to_list(Bin)]), ok.

visit(FileName, Output) ->
    Ast=parse(FileName, dulang, false),
    AbsFormat = lists:map(fun(Mod) -> visit_aux(Mod, 0) end, Ast),
    if Output -> io:format("~p\n", [AbsFormat]); true -> no_output end,
    AbsFormat.

visit(FileName) -> visit(FileName, true).

compile(FileName) ->
    transformer_proc:create(),
    AbsFormat = visit(FileName, false),
    transformer_proc:finish(),
    lists:foreach(fun(ModAbsFormat = [{attribute, _, module, ModuleName} | _]) ->
        case compile:forms(ModAbsFormat, [binary, return_errors, return_warnings]) of
            {ok, _, Bin, _} ->
                io:format("Saving Dulang Module ~p\n", [atom_to_list(ModuleName)]),
                file:write_file(filename:dirname(?FILE) ++ "/../_build/default/lib/dulang/ebin/" ++ atom_to_list(ModuleName) ++ ".beam", Bin);
            Err -> io:format("~p\n", [Err])
        end
    end, lists:droplast(AbsFormat)), ok.

compile_dulang_dir() ->
    Dir = "./src_dulang/",
    {ok, Files} = file:list_dir(Dir),
    lists:foreach(fun(F) -> compile(Dir ++ F) end, Files).

visit_aux({module, {_, Loc}, Var, Behaviors, Definitions}, 0) ->
    ModuleName = case Var of {var, _, N} -> N; {fn_call, _, [N]} -> N end,
    % Visit every Definition inside this module definition creating a transformer process
    ModuleDefinitions = transformer_proc:inside_module(fun() -> visit_list_aux(Definitions, 0) end),
    self() ! done, % Last message on mailbox
    Loop = fun Rec(ExpFunctions) ->
        receive
            % Receive messages from the visit process
            {export_fn, FnName, Arity} -> Rec([{FnName, Arity} | ExpFunctions]);
            done -> ExpFunctions
        end
    end,
    AttrBehaviors = lists:map(fun({atom, L, B}) -> {attribute, L, behavior, B} end, Behaviors),
    [{attribute, Loc, module, ModuleName}, {attribute, Loc, export, Loop([])} | AttrBehaviors ++ ModuleDefinitions];

visit_aux({pub, Def}, 0) ->
    DefAst = visit_aux(Def, 0),
    case DefAst of
        % This will send the function name and its arity as message to be post processed
        {function, _, FnName, Arity, _} -> self() ! {export_fn, FnName, Arity};
        _ -> err
    end,
    DefAst;

% Visitor functions
visit_aux({function, {var, Loc, Name}, Clauses}, 0) ->
    CompName = transformer_proc:add_def(Name),
    [{clause, _, {args, ArgsList}, _, _} | _] = Clauses,
    transformer_proc:inside_scope(fun() ->
        {function, Loc, CompName, length(ArgsList), visit_list_aux(Clauses, 1) }
    end);
% Defining inner functions(Level > 0)
visit_aux({function, {var, Loc, Name}, Clauses}, Level) when Level > 0 ->
    CompName = transformer_proc:add_def(Name),
    transformer_proc:inside_scope(fun() ->
        {match,
            Loc, {var, Loc, CompName},
            {named_fun, Loc, CompName, visit_list_aux(Clauses, Level+1) }
        }
    end);
% Defining anonymous functions
visit_aux({lambda, {_, Loc}, Clauses}, Level) ->
    ClausesWithLoc = lists:map(fun({clause, none, Args, Guards, Body}) -> {clause, {none, Loc}, Args, Guards, Body} end, Clauses),
    transformer_proc:inside_scope(fun() ->
        {'fun', Loc, {clauses, visit_list_aux(ClausesWithLoc, Level+1)} }
    end);

visit_aux({clause, {_, Loc}, {args, ArgsList}, {guards, GuardsList}, Body}, Level) ->
    {clause, Loc,
        visit_list_aux(ArgsList, -1),
        lists:map(fun(L) -> visit_list_aux(L, Level) end, GuardsList),
        visit_list_aux(Body, Level)};

visit_aux({recv, {_, Loc}, Clauses}, Level) ->
    transformer_proc:inside_scope(fun() ->
        {'receive', Loc, visit_list_aux(Clauses, Level+1)}
    end);

visit_aux({'case', {_, Loc}, Expr, Clauses}, Level) ->
    transformer_proc:inside_scope(fun() ->
        {'case', Loc, visit_aux(Expr, Level), visit_list_aux(Clauses, Level+1)}
    end);

visit_aux({match, {_, Loc}, Lhs, Rhs}, Level) ->
    % Passing Level -1 to LHS
    {match, Loc, visit_aux(Lhs, -1), visit_aux(Rhs, Level)};

visit_aux({call, {_, Loc}, Lhs, Parameters}, Level) ->
    {call, Loc, visit_aux(Lhs, Level), visit_list_aux(Parameters, Level)};
visit_aux({{fn_call, Loc, [Name]}, Parameters}, Level) ->
    % If a definition is found, the Type will be 'var' for every Definition above level 0, otherwise 'atom'.
    {CompName, Type} = case transformer_proc:find_def(Name) of 
        [{Name_, DefLevel} | _] when DefLevel > 0 -> {Name_, var}; _ -> {Name, atom} end,
    {call, Loc, {Type, Loc, CompName}, visit_list_aux(Parameters, Level)};
visit_aux({{fn_call, Loc, [ModName, FnName]}, Parameters}, Level) ->
    {call, Loc, {remote, Loc, {atom, Loc, ModName}, {atom, Loc, FnName}}, visit_list_aux(Parameters, Level)};

visit_aux({op, {Operation, Loc}, Lhs, Rhs}, Level) ->
    {op, Loc, Operation, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};

visit_aux({map, {_, Loc}, Elems}, Level) -> {map, Loc, visit_list_aux(Elems, Level)};
visit_aux({map, {_, Loc}, Map, Elems}, Level) -> {map, Loc, visit_aux(Map, Level), visit_list_aux(Elems, Level)};
visit_aux({map_field_assoc, {_, Loc}, Lhs, Rhs}, Level) -> {map_field_assoc, Loc, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};
visit_aux({map_field_exact, {_, Loc}, Lhs, Rhs}, Level) -> {map_field_exact, Loc, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};

visit_aux({cons, {_, Loc}, Lhs, Rhs}, Level) -> {cons, Loc, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};
visit_aux({nil, {_, Loc}}, _) -> {nil, Loc};
visit_aux({tuple, {_, Loc}, Elems}, Level) -> {tuple, Loc, visit_list_aux(Elems, Level)};
visit_aux({'true', Loc}, _) -> {atom, Loc, 'true'};
visit_aux({'false', Loc}, _) -> {atom, Loc, 'false'};
visit_aux(Atom = {atom, _, _}, _) -> Atom;
visit_aux(Int = {integer, _, _}, _) -> Int;
visit_aux(Str = {string, _, _}, _) -> Str;
visit_aux(EOF = {eof, _}, 0) -> EOF;
% If Level is equal to -1 it means that we are in the Left Hand Side of a match expression
visit_aux({var, Loc, Name}, -1) -> CompName = transformer_proc:add_def(Name), {var, Loc, CompName};
visit_aux({var, Loc, Name}, _) ->
    case transformer_proc:find_def(Name) of
        [{CompName, _} | _] -> {var, Loc, CompName};
        _ -> error(io_lib:format("Variable '~s' not defined.", [Name]))
    end;

visit_aux(Term, Level) -> io:format("term (at level ~p) not found: ~p\n", [Level, Term]), err.

visit_list_aux(L, Level) -> lists:map(fun(E) -> visit_aux(E, Level) end, L).
