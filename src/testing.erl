-module(testing).
-export([get_log/2, get_log/3, spawn_procs/2, assert_relation/3, discart_empty_relations/0, assert_start/0, assert_stop/1, times/2, loop/1, all_of/1, any_of/1, before/2, sequential/1, contains/1,
        synched/3, received/2, sent/3, expect/2, show_state/0]).

get_log(FileName, ToProbe, Time) ->
    code:purge(test),
    file:delete(".log"),
    csp_transform:from_csp(FileName, test, ToProbe, log),
    code:load_file(test),
    MAN_PID = test:main(), % Execute the compiled CSP file
    % A predefined time before read the log file
    io:format("Running ~s from ~s...\n", [ToProbe, FileName]),
    timer:sleep(Time),
    MAN_PID ! kill, % Cleaning remaining procs
    {ok, Logs} = file:consult(".log"), Logs.

get_log(FileName, ToProbe) -> get_log(FileName, ToProbe, 50).

all_of(L) -> fun(S) -> lists:foldl(fun (_, false)-> false; (F, S_)-> F(S_) end, S, L) end.
any_of(L) ->
    fun(S) ->
        case lists:dropwhile(fun(F)-> F(S) == false end, L) of
            [Fn | _] -> Fn(S);
            _ -> false
    end end.

times(N, F) ->
    fun(S) ->
        case {N, S} of
            {_, false} -> false;
            {0, _} -> S;
            _ -> (times(N-1, F))(F(S))
        end
    end.

loop(F) ->
    fun(S) ->
        case F(S) of
            [] -> [];
            false -> false;
            S_ -> (loop(F))(S_)
        end
    end.

% TODO: make 'before' P able to watch more than only one Msg at a time
before(L, P) ->
    fun(S) ->
        {Before, After} = lists:splitwith(fun(E) -> P([E]) == false end, S),
        case lists:all(fun(F) -> lists:any(fun(Msg) -> F([Msg]) == [] end, Before) end, L) of
            false -> false;
            true -> lists:filter(fun(E) -> (any_of(L))([E]) == false end, Before) ++ tl(After)
        end
    end.

sequential(L) ->
    fun(S) ->
        case lists:mapfoldl(
          fun(E, []) -> {E, []};
          (E, Ls = [H | Tl]) -> case H([E]) of [] -> {false, Tl}; false -> {E, Ls} end
          end, L, S) of
        {Elems, []} -> lists:filter(fun(false) -> false; (_) -> true end, Elems);
        {_, _} -> false
        end
    end.

contains(F) ->
    fun(S) ->
        FindNotFalse = fun Rec(L) -> case F(L) of false -> Rec(tl(L)); Res -> Res end end,
        FindNotFalse(S)
    end.

spawn_procs(ProcsArgs, State) ->
    {Spawns, Rest} = lists:split(length(ProcsArgs), State),
    {element(1, lists:mapfoldl(fun({ProcName, Args}, ToSearch)->
        FindProc = fun Rec(P, As, [E = {spawn, P, As, PID} | _]) -> {PID, lists:delete(E, ToSearch)};
                       Rec(P, As, [{spawn, _, _, _} | Tl]) -> Rec(P, As, Tl);
                       Rec(_, _, []) -> throw(not_found) end,
        FindProc(ProcName, Args, ToSearch)
    end, Spawns, ProcsArgs)), Rest}.

assert_relation(P1, P2, Chs) ->
    fun(S) ->
        % Find the relation that is expected
        {L, Rest} = lists:splitwith(
            fun({add_relation, P1_, P2_, Chs_}) when P1 =/= P1_; P2 =/= P2_; Chs =/= Chs_ -> true;
            (_) -> false
        end, S),
        case hd(Rest) of
        {add_relation, P1, P2, Chs} -> L ++ tl(Rest);
        {add_relation, P2, P1, Chs} -> L ++ tl(Rest);
        _ -> false
        end
    end.

discart_empty_relations() ->
    fun(S) ->
        lists:dropwhile(
          fun({add_relation, _, _, #{}}) -> true;
          (_) -> false end, S)
    end.

assert_start() -> fun(S) -> {start} = hd(S), tl(S) end.
assert_stop(P) -> fun([{stop, P_} | Tl]) when P_ =:= P -> Tl; (_) -> false end.

received(ChName, PID) -> fun(S) -> case S of [{recv, ChName, PID} | Rest] -> Rest; _ -> false end end.
sent(ChName, Msg, PID) -> fun(S) -> case S of [{send, ChName, Msg, PID} | Rest] -> Rest; _ -> false end end.

synched(ChName, P1, P2) -> fun(S) ->
    case S of [{sync, ChName, P1, P2} | Rest] -> Rest; [{sync, ChName, P2, P1} | Rest] -> Rest; _ -> false end end.

show_state() -> fun(S) -> utils:print(S), S end.

expect(F, S) -> case F(S) of [] -> utils:print(ok), ok; _ -> throw(test_fail) end.
