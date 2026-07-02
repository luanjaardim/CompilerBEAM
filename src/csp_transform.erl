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
    "            lambda () { manager:manager_listen([], maps:new(), @" ++ atom_to_list(Debug) ++ ") }\n"
    "        );\n"
    "        Send = (ChannelName, Msg) {\n"
    "            manager:send(PID, ChannelName, Msg);\n"
    "        };\n"
    "        Recv = (ChannelName, ParamNumber) {\n"
    "            manager:recv(PID, ChannelName, ParamNumber)\n"
    "        };\n"
    "~s\n"
    "        PID ! @start;\n"
    "        PID\n"
    "    }\n"
    "}\n",
    [ModName, S]),
    case Debug of true -> io:format("S: ~s, Info: ~p\n", [End, Info]); _ -> ok end,
    file:write_file("generated.dulang", list_to_binary(End)),
    compiler:compile("generated.dulang").

from_csp(FileName, ModName, ToProbe) -> from_csp(FileName, ModName, ToProbe, false).

compile({channel, Number, Channels}, _I, {S, Info = #{ channels := DefChannels }}) ->
    Fn = fun Rec(N, [{var, _, ChannelName} | Tail]) -> [{ChannelName, N} | Rec(N, Tail)];
             Rec(_, []) -> [] end,
    {S, Info#{ channels => maps:merge(maps:from_list(Fn(Number, Channels)), DefChannels) }};

compile({proc, Val, {body, ProcBody}}, I, {S, Info = #{ procs := Procs }}) ->
    % TODO: have a proc that can receive parameters
    {ProcName, ProcArgs} = case get_val(Val) of
                       {proc_call, Name, Args} -> {Name, Args};
                       NotProcCall -> {NotProcCall, []}
                   end,
    {S_, Begin} = case Procs of #{ProcName := _} -> {lists:droplast(lists:droplast(S))++"\n", "|"}; _ -> {S, io_lib:format("~s =|", [ProcName])} end,
    Info_ = Info#{ procs => Procs#{ProcName => 0} },
    {Body, _} = compile(ProcBody, I+1, {"", Info_}),
    {
        S_ ++
        indent(I, io_lib:format("~s ~s {\n", [Begin, convert_proc_args_to_str(ProcArgs, {"", Info_})])) ++
        indent(I+1, Body) ++
        indent(I, "};\n"),
        Info_
    };

compile({choices, [Events = {events, _}]}, I, C) ->
    {S, C_} = compile(Events, I, C), {S++"\n", C_};
compile({choices, Branches}, I, Context = { _, #{ channels := Channels, externs := Externs } }) ->
    InitialReq = lists:join(", ",
       lists:map(
         fun(Var) ->
            case treat_event(Var) of
                {recv, Name, _} -> io_lib:format("{@recv, @~s, ~p, self()}", [Name, maps:get(Name, Channels)]);
                {send, Name, Params} ->
                    case Externs of
                        #{Name := {ModName, _}} ->
                             io_lib:format("{@send, @~s, {apply(@~s, @~s, ~s)}, self()}", [Name, ModName, Name, into_list(Params, Context)]);
                        _ -> io_lib:format("{@send, @~s, ~s, self()}", [Name, into_tuple(Params, Context)])
                    end
            end
       end, lists:map(fun({events, Branch}) -> hd(Branch) end, Branches))),
    Separators = ["?"] ++ lists:duplicate(length(Branches)-1, "|"),
    ReceiveBranches = lists:map(
            fun({Sep, {events, B}}) ->
                S = case compile({events, tl(B)}, I+1, Context) of
                    {"", _} -> " @empty ";
                    {Body, _} -> indent(I+1, Body)
                end,
                indent(I, Sep ++ case treat_event(hd(B)) of
                    {send, Name, _} ->
                        io_lib:format("({@~s, {}}) {\n~s\n", [Name, S]) ++ indent(I, "}");
                    {recv, Name, Params} ->
                        io_lib:format("({@~s, ~s}) {\n~s\n", [Name, into_tuple(Params, Context), S]) ++ indent(I, "}")
                end) ++ "\n"
            end, lists:zip(Separators, Branches)),
    { io_lib:format("PID ! [~s];\n", [InitialReq]) ++ ReceiveBranches, Context };

compile({events, Events}, I, Context = {_, #{channels := Channels, procs := Procs, externs := Externs, atoms := Atoms}}) when is_list(Events) ->
    { lists:join("\n"++indent(I, ""), lists:map(fun(Event) ->
            case treat_event(Event) of
                Choices = {choices, _} ->
                    {S, _} = compile(Choices, I, Context), S;
                {proc_call, Name, ProcArgs} ->
                    io_lib:format("~s~s;", [Name, convert_proc_args_to_str(ProcArgs, Context)]);
                {recv, 'STOP', _} -> "manager:emit_stop(PID);";
                {recv, Name, Vars} ->
                    case {Channels, Procs, Externs} of
                        {_, #{ Name := _}, _} -> io_lib:format("~s();", [Name]);
                        {#{ Name := ParamsNumber }, _, _} ->
                            io_lib:format("~s = Recv(@~s, ~p);", [into_tuple(Vars, Context), Name, ParamsNumber]);
                        {_, _, #{ Name := {_, ParamsNumber} }} ->
                            io_lib:format("~s = Recv(@~s, ~p);", [into_tuple(Vars, Context), Name, ParamsNumber]);
                        _ -> throw(io_lib:format("Variable not defined: ~s", [Name]))
                    end;
                {send, Name, Params} ->
                    case Externs of
                        #{ Name := {ModName, _}} ->
                            io_lib:format("Send(@~s, {apply(@~s, @~s, ~s)});", [Name, ModName, Name, into_list(Params, Context)]);
                        _ -> io_lib:format("Send(@~s, ~s);", [Name, into_tuple(Params, Context)])
                    end
            end
        end, Events)), Context };

compile({sync, {_, _, Name}, {sync_channel, P1, P2, Chs}}, _I, {S, Info = #{relations := Relations}}) ->
    {S, Info#{ relations => [{Name, {[get_val(P1), get_val(P2)], Chs}}| Relations]}};

compile({paralel, {_, _, Name}, P1, P2}, _I, {S, Info = #{relations := Relations}}) ->
    {S, Info#{ relations => [{Name, {[get_val(P1), get_val(P2)], []}}| Relations]}};

compile({datatype, Datatypes}, _, {S, Info = #{ atoms := Atoms }}) ->
    {S, Info#{ atoms => maps:merge(Atoms, maps:from_list(lists:map(fun({_,_,D})-> {D, {}} end, Datatypes)))}};

compile({ignore}, _, C) -> C;

compile({extern, {_, _, ModName}, {channel, ParamNumber, Vars}}, _I, {S, Info = #{ externs := Externs }}) ->
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
                case Args of
                  [As] -> indent(I, io_lib:format("manager:spawn_proc(PID, @~s, ~s, ~s)", [Name, Name, into_tuple(As, C)]));
                  [] -> indent(I, io_lib:format("manager:spawn_proc(PID, @~s, ~s, @none)", [Name, Name]));
                  _ -> throw(not_implemented)
                end;
            _ -> throw(io_lib:format("Could not start the Process ~s!", [Name]))
        end
    end, { S ++ SpawnProc(ToProbe, [], I_) ++ ";", Info}.

into_tuple(List, Context) -> into_compound(List, Context, {"{", "}"}).
into_list(List, Context) -> into_compound(List, Context, {"[", "]"}).

into_compound(List, C = {_, #{channels := Channels, atoms := Atoms}}, _Delimiters = {Beg ,End}) ->
    Beg ++
    lists:concat(
    lists:join(", ",
    lists:map(fun Rec(Val) ->
        case {Channels, Atoms} of
            {#{ Val := _ }, _} -> io_lib:format("@~s", [Val]);
            {_, #{ Val := _ }} -> io_lib:format("@~s", [Val]);
            _ when is_atom(Val) -> io_lib:format("~s", [Val]);
            _ when is_tuple(Val) -> 
                case Val of
                    {expr, Op, Lhs, Rhs} ->  io_lib:format("~s ~s ~s", [Rec(Lhs), Op, Rec(Rhs)]);
                    _ -> into_compound(tuple_to_list(Val), C, {"{", "}"})
                end;
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
    get_val(Val);
treat_event(Val = {choices, _}) ->
    Val.

treat_event_aux({op, _, Val, Rest}) -> [get_val(Val) | treat_event_aux(Rest)];
treat_event_aux(Val) -> [get_val(Val)].

get_val({var, _, Val}) -> Val;
get_val({integer, _, Val}) -> Val;
get_val({seq, _, Val}) -> list_to_tuple(lists:map(fun(E) -> get_val(E) end, Val));
get_val({proc_call, {var, _, Name}, Val}) ->
    {proc_call, Name, lists:map(fun(Params) -> lists:map(fun(E) -> get_val(E) end, Params) end, Val)};
get_val({expr, {Op, _}, Lhs, Rhs}) -> {expr, Op, get_val(Lhs), get_val(Rhs)}.

convert_proc_args_to_str(ProcArgs, Context) ->
    case ProcArgs of
        [] -> "()";
        _ -> "(" ++ lists:join(")(", lists:map(fun(Ps) -> into_compound(Ps, Context, {"{", "}"}) end, ProcArgs)) ++ ")"
    end.

indent(I, S) -> lists:concat(lists:duplicate(I, "\t")) ++ S.
