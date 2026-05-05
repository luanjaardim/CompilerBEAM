-module(main).
-export([tokenize/1, parse/1, tokenize/2, parse/2, convert/1]).

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