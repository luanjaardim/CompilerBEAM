-module(main).
-export([run/0, run_tk/0, tokenize/1, to_ast/1]).

to_ast(FileName) ->
    {ok, Bin} = file:read_file(FileName),
    {ok, GenLexFile} = leex:file("lexer"),
    {ok, Lexer} = compile:file(GenLexFile, [report_errors]),
    {ok, Tks, _} = Lexer:string(binary_to_list(Bin)),
    {ok, GenParFile} = yecc:file("parser"),
    {ok, Parser} = compile:file(GenParFile, [report_errors]),
    Parser:parse(Tks).

tokenize(FileName) ->
    {ok, Bin} = file:read_file(FileName),
    {ok, GenLexFile} = leex:file("lexer"),
    {ok, Lexer} = compile:file(GenLexFile, [report_errors]),
    Lexer:string(binary_to_list(Bin)).

run() ->
     io:format("~p", [to_ast("test.dulang")]).

run_tk() ->
    {ok, Tks, _}=tokenize("test.dulang"),
    io:format("~p", [Tks]).
