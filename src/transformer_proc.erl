-module(transformer_proc).
-export([create/0, inside_module/1, inside_scope/1, add_def/1, find_def/1, debug/0]).
-record(transformer, {
    seed = 0,
    scopes = [#{}],
    level = 0
}).

create() -> register(transformer_proc, spawn(fun() -> main(#transformer{}) end)).

main(T = #transformer { seed = Seed, scopes = Sc = [ScH | ScTl], level = L}) ->
    T_ = receive
        next_level -> T#transformer { level = L+1, scopes = [#{} | Sc] };
        prev_level -> T#transformer { level = L-1, scopes = ScTl};
        {def, FnName, From} ->
            CompName = case L of 0 -> FnName; _ -> list_to_atom("def" ++ integer_to_list(Seed)) end,
            From ! {created, CompName},
            T#transformer { scopes = [ScH#{FnName => {CompName, L}} | ScTl], seed = Seed+1 };
        {find, Name, From} ->
            % Get all the scopes that the Name was defined.
            Filtered = lists:filtermap(fun(S) -> case maps:is_key(Name, S) of true -> {true, maps:get(Name, S)}; F -> F end end, Sc),
            % Return the List to the requester
            From ! {found, Filtered}, T;
        free -> #transformer{};
        debug -> io:format("~p~n", [T]), T
    end, main(T_).

inside_module(M) -> transformer_proc ! free, M().

inside_scope(F) ->
    transformer_proc ! next_level,
    Ret = F(),
    transformer_proc ! prev_level, Ret.

add_def(Name) -> transformer_proc ! {def, Name, self()}, receive {created, CompName} -> CompName end.
find_def(Name) -> transformer_proc ! {find, Name, self()}, receive {found, L} -> L end.
debug() -> transformer_proc ! debug.
