-module(testing).
-export([get_log/2, spawn_procs/2, assert_relation/3, assert_start/0, assert_not_false/1, times/2, loop/1, all_of/1, any_of/1, before/2,
        synched/3, received/2, sent/3, expect/2, show_state/0]).

get_log(FileName, ToProbe) ->
    file:delete(".log"),
    csp_transform:from_csp(FileName, test, ToProbe, log),
    test:main(), % Execute the compiled CSP file
    % A predefined time before read the log file
    io:format("Running ~s from ~s...\n", [ToProbe, FileName]),
    timer:sleep(1000),
    {ok, Logs} = file:consult(".log"), Logs.

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

before(L, P) ->
    fun(S) ->
        {Before, After} = lists:splitwith(fun(E) -> P([E]) == false end, S),
        case lists:all(fun(F) -> lists:any(fun(Msg) -> F([Msg]) == [] end, Before) end, L) of
            false -> false;
            true -> lists:filter(fun(E) -> (any_of(L))([E]) == false end, Before) ++ tl(After)
        end
    end.


spawn_procs(ProcsArgs, State) ->
    {Spawns, Rest} = lists:split(length(ProcsArgs), State),
    {lists:map(fun({ProcName, Args})->
        FindProc = fun Rec(P, As, [{spawn, P, As, PID} | _]) -> PID;
                       Rec(P, As, [{spawn, _, _, _} | Tl]) -> Rec(P, As, Tl);
                       Rec(_, _, []) -> throw(not_found) end,
        FindProc(ProcName, Args, Spawns)
    end, ProcsArgs), Rest}.

assert_relation(P1, P2, Chs) ->
    fun(S) ->
        case hd(S) of
        {add_relation, P1, P2, Chs} -> tl(S);
        {add_relation, P2, P1, Chs} -> tl(S);
        _ -> throw(relation_not_found)
        end
    end.

assert_start() -> fun(S) -> {start} = hd(S), tl(S) end.

assert_not_false(false) -> throw(is_false);
assert_not_false(S) -> S.

received(ChName, PID) -> fun(S) -> case S of [{recv, ChName, PID} | Rest] -> Rest; _ -> false end end.
sent(ChName, Msg, PID) -> fun(S) -> case S of [{send, ChName, Msg, PID} | Rest] -> Rest; _ -> false end end.

synched(ChName, P1, P2) -> fun(S) ->
    case S of [{sync, ChName, P1, P2} | Rest] -> Rest; [{sync, ChName, P2, P1} | Rest] -> Rest; _ -> false end end.

show_state() -> fun(S) -> utils:print(S), S end.

expect(F, S) -> case F(S) of [] -> utils:print(ok); _ -> throw(test_fail) end.
