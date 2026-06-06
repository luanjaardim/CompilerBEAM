-module(csp_transform).
-export([main/1]).

main(FileName) ->
    Ast = main:parse(FileName, csp),
    {S, Info} = lists:foldl(fun(Elem, Acc) -> manager:print(Elem), compile(Elem, 1, Acc) end, context_create(), Ast),
    io:format("S: ~s,\nInfo: ~p\n", [S, Info]).

context_create() -> {"", #{ channels => #{}, procs => #{} }}.

compile({channel, Number, Channels}, I, {S, Info = #{ channels := DefChannels }}) ->
    Fn = fun Rec(N, [{var, _, ChannelName} | Tail]) -> [{ChannelName, N} | Rec(N, Tail)];
             Rec(_, []) -> [] end,
    {S, Info#{ channels => maps:merge(maps:from_list(Fn(Number, Channels)), DefChannels) }};

compile({proc, {var, _, Name}, Choices}, I, {S, Info = #{ procs := Procs }}) ->
    % TODO: have a proc that can receive parameters
    Info_ = Info#{ procs => Procs#{Name => 0} },
    {Body, _} = compile(Choices, I+1, {"", Info_}),
    {
        S ++ io_lib:format("~s = ({}) {\n~s\n}", [Name, Body]) ++ ";\n",
        Info_
    };

compile({choices, Branches}, I, Context = { _, #{ channels := Channels } }) ->
    InitialReq = lists:join("; ",
       lists:map(
         fun(Var) ->
            case treat_event(Var) of
                {recv, Name, _} -> io_lib:format("PID ! {~p, ~p}", [Name, maps:get(Name, Channels)]);
                {send, Name, Params} -> io_lib:format("PID ! {~p, ~s}", [Name, list_to_tuple(Params)])
            end
       end, lists:map(fun(Branch) -> hd(Branch) end, Branches))),
    Separators = ["?"] ++ lists:duplicate(length(Branches)-1, "|"),
    ReceiveBranches = lists:map(
            fun({Sep, B}) ->
                {S, _} = compile(tl(B), I, Context),
                indent(I, Sep ++ case treat_event(hd(B)) of
                    {send, Name, _} ->
                        io_lib:format("({~s, {}}) { ~s }", [Name, S]);
                    {recv, Name, Params} ->
                        io_lib:format("({~s, ~p}) { ~s }", [Name, list_to_tuple(Params), S])
                end) ++ "\n"
            end, lists:zip(Separators, Branches)),
    { indent(I, InitialReq ++ ";\n") ++ ReceiveBranches, Context };

compile(Events, _, Context = {_, #{channels := Channels, procs := Procs}}) when is_list(Events) ->
    { lists:join("; ",
        lists:map(fun(Event) ->
            case treat_event(Event) of
                {recv, Name, Vars} ->
                    case {Channels, Procs} of
                        {_, #{ Name := _}} -> io_lib:format("~s(~p)", [Name, list_to_tuple(Vars)]);
                        {#{ Name := _ }, _} ->
                            io_lib:format("~p = Recv(~s, ~p)", [list_to_tuple(Vars), Name, maps:get(Name, Channels)]);
                        _ -> throw(io_lib:format("Variable not defined: ~s", [Name]))
                    end;
                {send, Name, Params} -> io_lib:format("Send(~s, ~p)", [Name, list_to_tuple(Params)])
            end
        end, Events)), Context }.

treat_event({var, _, Name}) ->
    {recv, Name, []};
treat_event({op, {'!', _}, {var, _, Name}, Rest}) ->
    {send, Name, treat_event_aux(Rest)};
treat_event({op, {'?', _}, {var, _, Name}, Rest}) ->
    {recv, Name, treat_event_aux(Rest)}.

treat_event_aux({_, _, Val}) -> [Val];
treat_event_aux({op, _, {_, _, Val}, Rest}) -> [Val | treat_event_aux(Rest)].

indent(I, S) -> lists:concat(lists:duplicate(I, "\t")) ++ S.
