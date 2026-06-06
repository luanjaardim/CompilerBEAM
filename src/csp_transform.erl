-module(csp_transform).
-export([main/1, from_csp/3]).

main(FileName) ->
    Ast = main:parse(FileName, csp),
    {S, Info} = lists:foldl(fun(Elem, Acc) -> manager:print(Elem), compile(Elem, 1, Acc) end, context_create(), Ast),
    io:format("S: ~s,\nInfo: ~p\n", [S, Info]).

context_create() -> {"", #{ channels => #{}, procs => #{}, extern => #{} }}.

from_csp(FileName, ModName, ExternalModules = []) ->
    Ast = main:parse(FileName, csp, false),
    Context = lists:foldl(fun(Elem, Acc) -> compile(Elem, 1, Acc) end, context_create(), Ast),
    {S, Info} = compile(spawn_and_start_procs, 1, Context),
    End = io_lib:format(
    "mod ~s {\n"
    "    pub main = () {\n"
    "        Wait = () { ?(@start) { @ok } };\n"
    "        PID = spawn(\n"
    "            lambda () { manager:manager_listen([], maps:new()) }\n"
    "        );\n"
    "        Send = (ChannelName, Msg) {\n"
    "            manager:send(PID, ChannelName, Msg);\n"
    "        };\n"
    "        Recv = (ChannelName, ParamNumber) {\n"
    "            manager:recv(PID, ChannelName, ParamNumber)\n"
    "        };\n"
    "~s\n"
    "    }\n"
    "}\n",
    [ModName, S]), io:format("S: ~s, Info: ~p", [End, Info]),
    file:write_file("generated.dulang", list_to_binary(End)),
    main:compile("generated.dulang").

compile({channel, Number, Channels}, I, {S, Info = #{ channels := DefChannels }}) ->
    Fn = fun Rec(N, [{var, _, ChannelName} | Tail]) -> [{ChannelName, N} | Rec(N, Tail)];
             Rec(_, []) -> [] end,
    {S, Info#{ channels => maps:merge(maps:from_list(Fn(Number, Channels)), DefChannels) }};

compile({proc, {var, _, Name}, Choices}, I, {S, Info = #{ procs := Procs }}) ->
    % TODO: have a proc that can receive parameters
    Info_ = Info#{ procs => Procs#{Name => 0} },
    {Body, _} = compile(Choices, I+1, {"", Info_}),
    {
        S ++ indent(I, io_lib:format("~s = ({}) {\n", [Name])) ++ Body ++ indent(I, "};\n"),
        Info_
    };

compile({choices, Branches}, I, Context = { _, #{ channels := Channels } }) ->
    InitialReq = lists:join("; ",
       lists:map(
         fun(Var) ->
            case treat_event(Var) of
                {recv, Name, _} -> io_lib:format("PID ! {@recv, @~s, ~p, self()}", [Name, maps:get(Name, Channels)]);
                {send, Name, Params} -> io_lib:format("PID ! {@send, @~s, ~s, self()}", [Name, into_tuple(Params, Context)])
            end
       end, lists:map(fun(Branch) -> hd(Branch) end, Branches))),
    Separators = ["?"] ++ lists:duplicate(length(Branches)-1, "|"),
    ReceiveBranches = lists:map(
            fun({Sep, B}) ->
                {S, _} = compile(tl(B), I, Context),
                indent(I, Sep ++ case treat_event(hd(B)) of
                    {send, Name, _} ->
                        io_lib:format("({@~s, {}}) { ~s }", [Name, S]);
                    {recv, Name, Params} ->
                        io_lib:format("({@~s, ~s}) { ~s }", [Name, into_tuple(Params, Context), S])
                end) ++ "\n"
            end, lists:zip(Separators, Branches)),
    { indent(I, InitialReq ++ ";\n") ++ ReceiveBranches, Context };

compile(Events, _, Context = {_, #{channels := Channels, procs := Procs, extern := Externs}}) when is_list(Events) ->
    { lists:map(fun(Event) ->
            case treat_event(Event) of
                {recv, 'STOP', _} -> "";
                {recv, Name, Vars} ->
                    case {Channels, Procs, Externs} of
                        {_, #{ Name := _}, _} -> io_lib:format("~s(~s); ", [Name, into_tuple(Vars, Context)]);
                        {#{ Name := ParamsNumber }, _, _} ->
                            io_lib:format("~s = Recv(@~s, ~p); ", [into_tuple(Vars, Context), Name, ParamsNumber]);
                        {_, _, #{ Name := {_, ParamsNumber} }} ->
                            io_lib:format("~s = Recv(@~s, ~p); ", [into_tuple(Vars, Context), Name, ParamsNumber]);
                        _ -> throw(io_lib:format("Variable not defined: ~s", [Name]))
                    end;
                {send, Name, Params} ->
                    case Externs of
                        #{ Name := {ModName, _}} ->
                            io_lib:format("Send(@~s, ~s:~s(~s)); ", [Name, ModName, Name, into_tuple(Params, Context)]);
                        _ -> io_lib:format("Send(@~s, ~s); ", [Name, into_tuple(Params, Context)])
                    end
            end
        end, Events), Context };

compile({ignore}, _, C) -> C;

compile({extern, {_, _, ModName}, ParamNumber, Vars}, I, {S, Info = #{ extern := Extern }}) ->
    {S, Info#{ extern => maps:merge(Extern, maps:from_list(lists:map(fun({'var', _, Name}) -> {Name, {ModName, ParamNumber}} end, Vars)))}};

compile(spawn_and_start_procs, I, {S, Info = #{ procs := Procs}}) ->
    ProcsNames = lists:map(fun ({N, _}) -> N end, maps:to_list(Procs)),
    Spawns = lists:map(fun(Name) ->
          indent(I, io_lib:format("~s_PID = spawn(lambda () { Wait(); ~s({}) });\n", [Name, Name]))
    end, ProcsNames),
    Start = indent(I, lists:foldr(fun(Name, Acc)-> io_lib:format("~s_PID ! ~s", [Name, Acc]) end, "@start", ProcsNames)),
    { S ++ Spawns ++ Start, Info }.


into_tuple(List, C = {_, #{channels := Channels}}) ->
    "{" ++
    lists:concat(
    lists:join(", ", 
    lists:map(fun(Val) ->
        case Channels of
            #{ Val := _ } -> io_lib:format("@~s", [Val]);
            _ when is_atom(Val) -> io_lib:format("~s", [Val]);
            _ -> io_lib:format("~p", [Val])
        end
    end, List))) ++ "}".

treat_event({var, _, Name}) ->
    {recv, Name, []};
treat_event({op, {'!', _}, {var, _, Name}, Rest}) ->
    {send, Name, treat_event_aux(Rest)};
treat_event({op, {'?', _}, {var, _, Name}, Rest}) ->
    {recv, Name, treat_event_aux(Rest)}.

treat_event_aux({_, _, Val}) -> [Val];
treat_event_aux({op, _, {_, _, Val}, Rest}) -> [Val | treat_event_aux(Rest)].

indent(I, S) -> lists:concat(lists:duplicate(I, "\t")) ++ S.
