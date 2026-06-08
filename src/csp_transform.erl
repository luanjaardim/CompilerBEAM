-module(csp_transform).
-export([main/1, from_csp/2, from_csp/3]).

main(FileName) ->
    Ast = main:parse(FileName, csp),
    {S, Info} = lists:foldl(fun(Elem, Acc) -> manager:print(Elem), compile(Elem, 1, Acc) end, context_create(), Ast),
    io:format("S: ~s,\nInfo: ~p\n", [S, Info]).

context_create() -> {"", #{ channels => #{}, procs => #{}, externs => #{}, relations => [] }}.

from_csp(FileName, ModName, Debug) ->
    Ast = main:parse(FileName, csp, false),
    Context = lists:foldl(fun(Elem, Acc) -> compile(Elem, 1, Acc) end, context_create(), Ast),
    {S, Info} = compile(spawn_and_start_procs, 1, Context),
    End = io_lib:format(
    "mod ~s {\n"
    "    pub main = () {\n"
    "        Wait = () { ?(@start) { @ok } };\n"
    "        PID = spawn(\n"
    "            lambda () { manager:manager_listen([], maps:new(), @false) }\n"
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

from_csp(FileName, ModName) -> from_csp(FileName, ModName, true).

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

compile(Events, _, Context = {_, #{channels := Channels, procs := Procs, externs := Externs}}) when is_list(Events) ->
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

compile({sync, {_, _, Name}, {sync_channel, {_, _, P1}, {_, _, P2}, Chs}}, I, {S, Info = #{relations := Relations}}) ->
    {S, Info#{ relations => [{Name, {[P1, P2], Chs}}| Relations]}};

compile({ignore}, _, C) -> C;

compile({extern, {_, _, ModName}, ParamNumber, Vars}, I, {S, Info = #{ externs := Externs }}) ->
    {S, Info#{ externs => maps:merge(Externs, maps:from_list(lists:map(fun({'var', _, Name}) -> {Name, {ModName, ParamNumber}} end, Vars)))}};

compile(spawn_and_start_procs, I, {S, Info = #{ procs := Procs}}) ->
    ProcsNames = lists:map(fun ({N, _}) -> N end, maps:to_list(Procs)),
    Spawns = lists:map(fun(Name) ->
          indent(I, io_lib:format("~s_PID = spawn(lambda () { Wait(); ~s({}) });\n", [Name, Name]))
    end, ProcsNames),
    Relations = add_relations(I, {"", Info}),
    Start = indent(I, lists:foldr(fun(Name, Acc)-> io_lib:format("~s_PID ! ~s", [Name, Acc]) end, "@start", ProcsNames)),
    { S ++ Spawns ++ Relations ++ Start, Info }.

add_relations(I, Context = {_, Info = #{channels := Channels, procs := Procs, relations := Relations}}) ->
    Dependencies = lists:foldr(fun({Name, {Ks = [P1, P2], Chs}}, M)->
                    {L, Ch} = case {M, M} of
                        {#{ P1 := { P1s, Ch1s }}, #{ P2 := { P2s, Ch2s } }} -> {P1s ++ P2s, Chs ++ Ch1s ++ Ch2s};
                        {#{ P1 := {P1s, Ch1s} }, _} -> {P1s ++ [P2], Chs ++ Ch1s};
                        {_, #{ P2 := {P2s, Ch2s} }} -> {[P1] ++ P2s, Chs ++ Ch2s};
                        {_, _} -> {[P1, P2], Chs}
                    end,
                    maps:without(Ks, M#{ Name => {
                        lists:uniq(L),
                        lists:uniq(
                            lists:map(fun({_, _, V})-> V;
                                         (V)-> V end, Ch))
                    }})
                end, #{}, Relations),
    Pairs = fun Rec([]) ->
                    [];
                Rec([H | T]) ->
                    [{H, X} || X <- T] ++ Rec(T)
            end,
              manager:print(Dependencies),
    maps:fold(fun(_, {SyncProcs, SyncChannels}, S) ->
              P = Pairs(SyncProcs),
              S ++ lists:concat(
                  lists:map(fun({P1, P2}) ->
                      indent(I, io_lib:format("manager:addRelation(PID, ~s_PID, ~s_PID, maps:from_list(~s));\n",
                      [P1, P2, into_list(lists:map(fun(V)-> {V, maps:get(V, Channels)} end, SyncChannels), Context)]))
              end, P))
    end, "", Dependencies).

into_tuple(List, Context) -> into_compound(List, Context, {"{", "}"}).
into_list(List, Context) -> into_compound(List, Context, {"[", "]"}).

into_compound(List, C = {_, #{channels := Channels}}, Delimiters = {Beg ,End}) ->
    % TODO: Fix the usage of Atoms from datatype
    Beg ++
    lists:concat(
    lists:join(", ", 
    lists:map(fun(Val) ->
        case Channels of
            #{ Val := _ } -> io_lib:format("@~s", [Val]);
            _ when is_atom(Val) -> io_lib:format("~s", [Val]);
            _ when is_tuple(Val) -> into_compound(tuple_to_list(Val), C, {"{", "}"});
            _ when is_list(Val) -> into_compound(Val, C, {"[", "]"});
            _ -> io_lib:format("~p", [Val])
        end
    end, List))) ++ End.

treat_event({var, _, Name}) ->
    {recv, Name, []};
treat_event({op, {'!', _}, {var, _, Name}, Rest}) ->
    {send, Name, treat_event_aux(Rest)};
treat_event({op, {'?', _}, {var, _, Name}, Rest}) ->
    {recv, Name, treat_event_aux(Rest)}.

treat_event_aux({_, _, Val}) -> [Val];
treat_event_aux({op, _, {_, _, Val}, Rest}) -> [Val | treat_event_aux(Rest)].

indent(I, S) -> lists:concat(lists:duplicate(I, "\t")) ++ S.
