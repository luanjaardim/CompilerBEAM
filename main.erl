-module(main).
-export([tokenize/1, parse/1, tokenize/2, parse/2, convert/1, visit/1]).

tokenize(FileName, Output) ->
    {ok, Bin} = file:read_file(FileName),
    {ok, GenLexFile} = leex:file("lexer"),
    {ok, Lexer} = compile:file(GenLexFile, [report_errors]),
    {ok, Tks, _}=Lexer:string(binary_to_list(Bin)),
    if Output -> io:format("~p\n", [Tks]); true -> no_output end, Tks.

tokenize(FileName) -> tokenize(FileName, true).

parse(FileName, Output) ->
    Tks = tokenize(FileName, false),
    {ok, GenParFile} = yecc:file("parser"),
    {ok, Parser} = compile:file(GenParFile, [report_errors]),
    {ok, Ast} = Parser:parse(Tks),
    if Output -> io:format("~p\n", [Ast]); true -> no_output end, Ast.

parse(FileName) -> parse(FileName, true).

% Transforms an Erlang file into its Abstract Format
convert(FileName) -> 
    {ok, _} = compile:file(FileName, [to_pp, report_errors]),
    FileNameWithoutExt = filename:rootname(FileName),
    {ok, Bin} = file:read_file(FileNameWithoutExt ++ ".P"),
    io:format("~s\n", [binary_to_list(Bin)]), ok.

visit(FileName, Output) ->
    ModuleName = list_to_atom(filename:rootname(FileName)),
    Ast=parse(FileName, false),
    AbsFormat=lists:map(fun(Def) -> visit_aux(Def, 0) end, Ast),
    AbsFormatMod = [ {attribute, {1, 1}, module, ModuleName} | AbsFormat],
    if Output -> io:format("~p\n", [AbsFormatMod]); true -> no_output end,
    AbsFormatMod.

visit(FileName) -> visit(FileName, true).

% Visitor functions
visit_aux({function, {var, Loc, Name}, Clauses}, 0) ->
    [{clause, _, {args, ArgsList}, _, _} | _] = Clauses,
    {function, Loc, list_to_atom(Name), length(ArgsList), lists:map(fun(C) -> visit_aux(C, 1) end, Clauses) };

visit_aux({clause, {_, Loc}, {args, ArgsList}, {guards, GuardsList}, Body}, Level) ->
    {clause, Loc,
        visit_list_aux(ArgsList, Level),
        visit_list_aux(GuardsList, Level),
        visit_list_aux(Body, Level+1)} ;
visit_aux({clause, {_, Loc}, {'else_kw', LocElse}, Body}, Level) ->
    {clause, Loc, [{atom, LocElse, 'true'}], [], visit_list_aux(Body, Level+1)};

visit_aux({'case', {_, Loc}, Expr, Clauses}, Level) ->
    {'case', Loc, visit_aux(Expr, Level), visit_list_aux(Clauses, Level+1)};

visit_aux({match, {_, Loc}, Lhs, Rhs}, Level) ->
    {match, Loc, visit_aux(Lhs, Level), visit_aux(Rhs, Level)};

visit_aux({tuple, {_, Loc}, Elems}, Level) -> {tuple, Loc, visit_list_aux(Elems, Level)};
visit_aux(Var = {var, Loc, Text}, _) -> {var, Loc, list_to_atom(Text)};
visit_aux(Int = {integer, _, _}, _) -> Int;

visit_aux(Term, Level) -> io:format("term not found: ~p\n", [Term]), err.

visit_list_aux(L, Level) -> lists:map(fun(E) -> visit_aux(E, Level) end, L).

