-module(csp_transform).
-export([from_csp/3, from_csp/4]).

context_create() -> {"", #{ channels => #{}, procs => #{}, externs => #{}, relations => [], atoms => #{} }}.

from_csp(FileName, ModName, ToProbe, Debug) ->
    Ast = compiler:parse(FileName, csp, false),
    Context = lists:foldl(fun(Elem, Acc) -> compile(Elem, 1, Acc) end, context_create(), Ast),
    {S, Info} = compile({spawn_and_start_procs, ToProbe}, 1, Context),
    End = io_lib:format(
    "mod ~s {\n"
    "    pub main = () {\n"
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
    "        PID ! @start\n"
    "    }\n"
    "}\n",
    [ModName, S]),
    manager:debug("S: ~s, Info: ~p", [End, Info], Debug),
    file:write_file("generated.dulang", list_to_binary(End)),
    compiler:compile("generated.dulang").

from_csp(FileName, ModName, ToProbe) -> from_csp(FileName, ModName, ToProbe, true).

compile({channel, Number, Channels}, _I, {S, Info = #{ channels := DefChannels }}) ->
    Fn = fun Rec(N, [{var, _, ChannelName} | Tail]) -> [{ChannelName, N} | Rec(N, Tail)];
             Rec(_, []) -> [] end,
    {S, Info#{ channels => maps:merge(maps:from_list(Fn(Number, Channels)), DefChannels) }};

compile({proc, Val, Choices}, I, {S, Info = #{ procs := Procs }}) ->
    % TODO: have a proc that can receive parameters
    {ProcName, ProcArgs} = case get_val(Val) of
                       {proc_call, Name, Args} -> {Name, Args};
                       NotProcCall -> {NotProcCall, []}
                   end,
    Info_ = Info#{ procs => Procs#{ProcName => 0} },
    {Body, _} = compile(Choices, I+1, {"", Info_}),
    {
        S ++
        indent(I, io_lib:format("~s = ~s {\n", [ProcName, convert_proc_args_to_str(ProcArgs, {"", Info_})])) ++
        Body ++
        indent(I, "};\n"),
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
                {proc_call, Name, ProcArgs} ->
                    io_lib:format("~s~s; ", [Name, convert_proc_args_to_str(ProcArgs, Context)]);
                {recv, 'STOP', _} -> "";
                {recv, Name, Vars} ->
                    case {Channels, Procs, Externs} of
                        {_, #{ Name := _}, _} -> io_lib:format("~s(); ", [Name]);
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

compile({sync, {_, _, Name}, {sync_channel, P1, P2, Chs}}, _I, {S, Info = #{relations := Relations}}) ->
    {S, Info#{ relations => [{Name, {[get_val(P1), get_val(P2)], Chs}}| Relations]}};

compile({datatype, Datatypes}, _, {S, Info = #{ atoms := Atoms }}) ->
    {S, Info#{ atoms => maps:merge(Atoms, maps:from_list(lists:map(fun({_,_,D})-> {D, {}} end, Datatypes)))}};

compile({ignore}, _, C) -> C;

compile({extern, {_, _, ModName}, ParamNumber, Vars}, _I, {S, Info = #{ externs := Externs }}) ->
    {S, Info#{ externs => maps:merge(Externs, maps:from_list(lists:map(fun({'var', _, Name}) -> {Name, {ModName, ParamNumber}} end, Vars)))}};

% TODO: receive args for the ToProbe process
compile({spawn_and_start_procs, ToProbe}, I_, C={S, Info = #{ procs := Procs, relations := Relations, channels := Channels }}) ->
    SpawnProc = fun Rec(Name, Args, I) ->
        case {Procs, maps:from_list(Relations)} of
            {_, #{Name := {[P1, P2], SyncChannels}}} ->
              S1 = case P1 of {proc_call, N1, A1s} -> Rec(N1, A1s, I+1); _ -> Rec(P1, [], I+1) end,
              S2 = case P2 of {proc_call, N2, A2s} -> Rec(N2, A2s, I+1); _ -> Rec(P2, [], I+1) end,
              indent(I, "manager:add_relation(PID,\n") ++
              lists:join(",\n",
                  [ S1, S2, indent(I+1, into_list(lists:map(fun(V)-> Val = get_val(V), {Val, maps:get(Val, Channels)} end, SyncChannels), C))])
              ++ "\n" ++ indent(I, ")")
              ;
            {#{Name := _}, _} ->
                utils:print(Args),
                case Args of
                  [As] -> indent(I, io_lib:format("manager:spawn_proc(PID, @~s, ~s, ~s)", [Name, Name, into_tuple(As, C)]));
                  [] -> indent(I, io_lib:format("manager:spawn_proc(PID, @~s, ~s, @none)", [Name, Name]));
                  _ -> throw(not_implemented)
                end;
            _ -> throw("Could not start the Process")
        end
    end, { S ++ SpawnProc(ToProbe, [], I_) ++ ";", Info}.

into_tuple(List, Context) -> into_compound(List, Context, {"{", "}"}).
into_list(List, Context) -> into_compound(List, Context, {"[", "]"}).

into_compound(List, C = {_, #{channels := Channels, atoms := Atoms}}, _Delimiters = {Beg ,End}) ->
    Beg ++
    lists:concat(
    lists:join(", ",
    lists:map(fun(Val) ->
        case {Channels, Atoms} of
            {#{ Val := _ }, _} -> io_lib:format("@~s", [Val]);
            {_, #{ Val := _ }} -> io_lib:format("@~s", [Val]);
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
    {recv, Name, treat_event_aux(Rest)};
treat_event(Val = {proc_call, {var, _, _Name}, _Args}) ->
    get_val(Val).

treat_event_aux({op, _, Val, Rest}) -> [get_val(Val) | treat_event_aux(Rest)];
treat_event_aux(Val) -> [get_val(Val)].

get_val({var, _, Val}) -> Val;
get_val({integer, _, Val}) -> Val;
get_val({seq, _, Val}) -> list_to_tuple(lists:map(fun(E) -> get_val(E) end, Val));
get_val({proc_call, {var, _, Name}, Val}) ->
    {proc_call, Name, lists:map(fun(Params) -> lists:map(fun(E) -> get_val(E) end, Params) end, Val)}.

convert_proc_args_to_str(ProcArgs, Context) ->
    case ProcArgs of
        [] -> "()";
        _ -> "(" ++ lists:join(")(", lists:map(fun(Ps) -> into_compound(Ps, Context, {"{", "}"}) end, ProcArgs)) ++ ")"
    end.

indent(I, S) -> lists:concat(lists:duplicate(I, "\t")) ++ S.
