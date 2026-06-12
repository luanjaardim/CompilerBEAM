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
    AbsFormat = visit(FileName, false),
    lists:foreach(fun(ModAbsFormat = [{attribute, _, module, ModuleName} | _]) ->
        {ok, _, Bin} = compile:forms(ModAbsFormat, [binary]),
        io:format("Saving Dulang Module ~p\n", [atom_to_list(ModuleName)]),
        file:write_file(filename:dirname(?FILE) ++ "/../_build/default/lib/dulang/ebin/" ++ atom_to_list(ModuleName) ++ ".beam", Bin)
    end, lists:droplast(AbsFormat)).

compile_dulang_dir() ->
    Dir = "./src_dulang/",
    {ok, Files} = file:list_dir(Dir),
    lists:foreach(fun(F) -> compile(Dir ++ F) end, Files).

visit_aux({module, _, {var, Loc, ModuleName}, Clauses}, 0) ->
    ModuleDefinitions = visit_list_aux(Clauses, 0),
    self() ! done, % Last message on mailbox
    Loop = fun Loop(ExpFunctions) ->
        receive
            % Receive messages from the visit process
            {export_fn, FnName, Arity} -> Loop([{FnName, Arity} | ExpFunctions]);
            done -> ExpFunctions
        end
    end,
    [{attribute, Loc, module, ModuleName}, {attribute, Loc, export, Loop([])} | ModuleDefinitions];

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
    [{clause, _, {args, ArgsList}, _, _} | _] = Clauses,
    {function, Loc, Name, length(ArgsList), visit_list_aux(Clauses, 1) };
% Defining inner functions(Level > 0)
visit_aux({function, {var, Loc, Name}, Clauses}, Level) when Level > 0 ->
    {match,
        Loc, {var, Loc, Name},
        {named_fun, Loc, Name, visit_list_aux(Clauses, Level+1) }
    };
% Defining anonymous functions
visit_aux({lambda, {_, Loc}, {args, ArgsList}, Body}, Level) ->
    {'fun', Loc, {clauses, [{clause, Loc, visit_list_aux(ArgsList, Level), [], visit_list_aux(Body, Level+1)}]} };

visit_aux({clause, {_, Loc}, {args, ArgsList}, {guards, GuardsList}, Body}, Level) ->
    {clause, Loc,
        visit_list_aux(ArgsList, Level),
        lists:map(fun(L) -> visit_list_aux(L, Level) end, GuardsList),
        visit_list_aux(Body, Level+1)} ;

visit_aux({recv, {_, Loc}, Clauses}, Level) -> {'receive', Loc, visit_list_aux(Clauses, Level)};

visit_aux({'case', {_, Loc}, Expr, Clauses}, Level) ->
    {'case', Loc, visit_aux(Expr, Level), visit_list_aux(Clauses, Level+1)};

visit_aux({match, {_, Loc}, Lhs, Rhs}, Level) ->
    {match, Loc, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};

visit_aux({{fn_call, Loc, [Name]}, Parameters}, Level) ->
    Type = case atom_to_list(Name) of
        [ H | _ ] when H >= $a, H =< $z -> atom;
        _ -> var
    end,
    {call, Loc, {Type, Loc, Name}, visit_list_aux(Parameters, Level+1)};
visit_aux({{fn_call, Loc, [ModName, FnName]}, Parameters}, Level) ->
    {call, Loc, {remote, Loc, {atom, Loc, ModName}, {atom, Loc, FnName}}, visit_list_aux(Parameters, Level+1)};

visit_aux({op, {Operation, Loc}, Lhs, Rhs}, Level) ->
    {op, Loc, Operation, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};

visit_aux({cons, {_, Loc}, Lhs, Rhs}, Level) -> {cons, Loc, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};
visit_aux({nil, {_, Loc}}, _) -> {nil, Loc};
visit_aux({tuple, {_, Loc}, Elems}, Level) -> {tuple, Loc, visit_list_aux(Elems, Level)};
visit_aux(Atom = {atom, _, _}, _) -> Atom;
visit_aux(Var = {var, _, _}, _) -> Var;
visit_aux(Int = {integer, _, _}, _) -> Int;
visit_aux(Str = {string, _, _}, _) -> Str;
visit_aux(EOF = {eof, _}, 0) -> EOF;

visit_aux(Term, Level) -> io:format("term (at level ~p) not found: ~p\n", [Level, Term]), err.

visit_list_aux(L, Level) -> lists:map(fun(E) -> visit_aux(E, Level) end, L).
