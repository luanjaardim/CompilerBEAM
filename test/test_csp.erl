-module(test_csp).
-export([test_all/0, sync_qp/0, sync_rp/0, sync_xz/0, sync_xzy/0, sync_main/0, basic_p/0, basic_q/0, basic_synt_p/0, basic_synt_r/0, basic_synt_main/0, procs_q/0, procs_s/0, communication_pq/0, external_main/0]).

test_all() ->
    TestFunctions = lists:filter(
        fun({Name, _}) when Name /= module_info, Name /= test_all -> true; (_) -> false end, module_info(exports)),
    {PassedAmount, FailedTests} = lists:foldl(
      fun({Name, _}, {Acc, FailedList}) ->
        try apply(test_csp, Name, []) of ok -> {1 + Acc, FailedList}
        catch test_fail -> {Acc, [io_lib:format("\n\t~s", [Name]) | FailedList]}
        end
      end,
    {0, []}, TestFunctions),
    io:format("\nPassed ~p of ~p tests.\n", [PassedAmount, length(TestFunctions)]),
    case FailedTests of
      [] -> ok;
      _ -> io:format("Failed:"), lists:foreach(fun(T) -> io:format("~s", [T]) end, FailedTests)
    end.


sync_qp() ->
    Logs = testing:get_log("./test/sync.csp", 'SYN_QP'),
    {[Q, P], C} = testing:spawn_procs([{'Q', none}, {'P', none}], Logs),
    testing:expect(
        testing:all_of([
            testing:assert_relation(Q, P, #{a => 0, b => 0}),
            testing:assert_start(),
            testing:times(2, testing:any_of([
                testing:received(c, Q),
                testing:sent(c, {1}, P)
            ])),
            testing:before([
                testing:received(a, P), testing:received(a, Q)
            ],  testing:synched(a, P, Q)),
            testing:before([
                testing:received(b, P), testing:received(b, Q)
            ],  testing:synched(b, P, Q)),
            testing:times(3, testing:any_of([
                    testing:before([
                        testing:received(b, P), testing:received(b, Q)
                    ],  testing:synched(b, P, Q)),
                    testing:received(c, P),
                    testing:received(c, Q)
                ])),
            testing:before([
                testing:received(a, P), testing:received(a, Q)
            ],  testing:synched(a, P, Q)),
            testing:times(2, testing:any_of([testing:assert_stop(Q), testing:assert_stop(P)]))
        ]), C).

sync_rp() ->
    Logs = testing:get_log("./test/sync.csp", 'SYN_RP'),
    {[P, R], C} = testing:spawn_procs([{'P', none}, {'R', none}], Logs),
    testing:expect(
        testing:all_of([
            testing:assert_relation(P, R, #{c => 1}),
            testing:assert_start(),
            testing:before([
                testing:sent(c, {1}, P),
                testing:received(c, R)
            ], testing:synched(c, P, R)),
            testing:loop(testing:any_of([
                testing:received(a, P),
                testing:received(b, P),
                testing:received(c, P),
                testing:before([
                    testing:sent(c, {1}, R),
                    testing:received(c, P)
                ], testing:synched(c, P, R)),
                testing:any_of([testing:assert_stop(R), testing:assert_stop(P)])
            ]))
        ]),
        C).

sync_xz() ->
    Logs = testing:get_log("./test/sync.csp", 'SYN_XZ'),
    {[X, Z], C} = testing:spawn_procs([{'X', none}, {'Z', none}], Logs),
    testing:expect(
        testing:all_of([
            testing:assert_relation(X, Z, #{w => 0, x => 0, y => 0, z => 0}),
            testing:assert_start(),
            testing:before([
                testing:received(w, X),
                testing:received(w, Z)
            ], testing:synched(w, X, Z)),
            testing:before([
                testing:received(x, X),
                testing:received(x, Z)
            ], testing:synched(x, X, Z)),
            testing:contains(testing:assert_stop(X)),

            % At this point Z will block in 'w' and 'y'
            testing:loop(testing:any_of([
                testing:received(w, Z),
                testing:received(y, Z)
            ]))
        ]),
        C).

sync_xzy() ->
    Logs = testing:get_log("./test/sync.csp", 'SYN_XZY'),
    {[X, Z, Y], C} = testing:spawn_procs([{'X', none}, {'Z', none}, {'Y', none}], Logs),
    testing:expect(testing:all_of([
        % Relations
        testing:times(3, testing:any_of([
            testing:assert_relation(X, Z, #{w => 0, x => 0, y => 0, z => 0}),
            testing:assert_relation(Z, Y, #{w => 0, x => 0, y => 0, z => 0}),
            testing:assert_relation(X, Y, #{w => 0, x => 0, y => 0, z => 0})
        ])),
        testing:assert_start(),
        testing:before([
            testing:received(w, X),
            testing:received(w, Z)
        ], testing:synched(w, X, Z)),
        testing:before([
            testing:received(x, X),
            testing:received(x, Z)
        ], testing:synched(x, X, Z)),
        testing:before([
            testing:received(y, Y),
            testing:received(y, Z)
        ], testing:synched(y, Y, Z)),
        testing:before([
            testing:received(z, Y),
            testing:received(z, Z)
        ], testing:synched(z, Y, Z)),
        testing:times(2,
            testing:contains(testing:any_of([
                testing:assert_stop(X),
                testing:assert_stop(Y)])
        )),

        % At this point Z will block in 'w' and 'y'
        testing:loop(testing:any_of([
            testing:received(w, Z),
            testing:received(y, Z)
        ]))
    ]), C).

sync_main() ->
    Logs = testing:get_log("./test/sync.csp", 'MAIN'),
    {[X, Y, WX, WY], C} = testing:spawn_procs([{'X', none}, {'Y', none}, {'W', none}, {'W', none}], Logs),
    testing:expect(testing:all_of([
        testing:assert_relation(X, WX, #{w => 0,x => 0,y => 0}),
        testing:assert_relation(Y, WY, #{w => 0,y => 0,z => 0}),
        testing:discart_empty_relations(),
        testing:assert_start(),
        testing:before([
            testing:received(y, Y),
            testing:received(y, WY)
        ], testing:synched(y, Y, WY)),
        testing:before([
            testing:received(z, Y),
            testing:received(z, WY)
        ], testing:synched(z, Y, WY)),
        testing:before([
            testing:received(w, X),
            testing:received(w, WX)
        ], testing:synched(w, X, WX)),
        testing:before([
            testing:received(x, X),
            testing:received(x, WX)
        ], testing:synched(x, X, WX)),
        testing:loop(testing:any_of([
            testing:received(w, WY),
            testing:received(y, WX),
            testing:assert_stop(WX),
            testing:assert_stop(X),
            testing:assert_stop(WY),
            testing:assert_stop(Y)]))
    ]), C).

basic_p() ->
    Logs = testing:get_log("./test/basic.csp", 'P', 500),
    {[P], C} = testing:spawn_procs([{'P', none}], Logs),
    testing:expect(testing:all_of([
      testing:assert_start(),
      % Here we ready 200 cycles of P, the last one can be incomplete, so we use the loop below
      testing:times(200,
        testing:all_of([
          testing:received(a, P),
          testing:received(b, P),
          testing:sent(c, {1}, P),
          testing:sent(c, {2}, P)
        ])
      ),
      % At the time we are reading the messages after the execution time the full cycle can be incomplete
      testing:loop(testing:any_of([
          testing:received(a, P),
          testing:received(b, P),
          testing:sent(c, {1}, P),
          testing:sent(c, {2}, P)
      ]))
    ]), C).

basic_q() ->
    Logs = testing:get_log("./test/basic.csp", 'Q', 500),
    {[Q], C} = testing:spawn_procs([{'Q', none}], Logs),
    testing:expect(testing:all_of([
      testing:assert_start(),
      % Here we ready 200 cycles of Q, the last one can be incomplete, so we use the loop below
      testing:times(200,
        testing:any_of([
          testing:before(
            [ testing:received(a, Q) ],
            testing:sent(c, {1}, Q)
          ),
          testing:before(
            [ testing:received(b, Q) ],
            testing:sent(c, {2}, Q)
          )
        ])
      ),
      % At the time we are reading the messages after the execution time the full cycle can be incomplete
      testing:loop(testing:any_of([
          testing:received(a, Q),
          testing:received(b, Q),
          testing:sent(c, {1}, Q),
          testing:sent(c, {2}, Q)
      ]))
    ]), C).

basic_synt_p() ->
    Logs = testing:get_log("./test/basic_syntax.csp", 'P'),
    {[P], C} = testing:spawn_procs([{'P', none}], Logs),
    testing:expect(testing:all_of([
        testing:assert_start(),
        testing:loop(testing:any_of([
            testing:sequential([testing:received(x, P), testing:received(y, P), testing:assert_stop(P)]),
            testing:before([testing:received(x, P)], testing:received(z, P)),
            testing:received(a, P),
            testing:received(b, P)
        ]))
    ]), C).

basic_synt_r() ->
    Logs = testing:get_log("./test/basic_syntax.csp", 'R'),
    {[R], C} = testing:spawn_procs([{'R', none}], Logs),
    testing:expect(testing:all_of([
        testing:assert_start(),
        testing:sent(c, {'ONE'}, R),
        testing:received(c, R),
        testing:sent(d, {1, 'TWO'}, R),
        testing:received(d, R),
        testing:assert_stop(R)
    ]), C).

basic_synt_main() ->
    Logs = testing:get_log("./test/basic_syntax.csp", 'MAIN'),
    {[S, I], C} = testing:spawn_procs([{'S', {'ONE'}}, {'INC', none}], Logs),
    testing:expect(testing:all_of([
        testing:discart_empty_relations(),
        testing:assert_start(),
        % Sequence of the INC proccess
        testing:sequential([
            testing:received(c, I),
            testing:sent(c, {'TWO'}, I),
            testing:received(c, I),
            testing:sent(c, {'THREE'}, I)
        ]),
        % Sequence of the S proccess
        testing:sequential([
            testing:sent(c, {'ONE'}, S),
            testing:received(c, S),
            testing:sent(c, {'TWO'}, S),
            testing:received(c, S),
            testing:assert_stop(S)
        ]),
        testing:loop(testing:received(c, I))
    ]), C).

procs_q() ->
    Logs = testing:get_log("./test/procs.csp", 'Q'),
    {[Q], C} = testing:spawn_procs([{'Q', none}], Logs),
    testing:expect(testing:all_of([
        testing:assert_start(),
        testing:sent(c, {1}, Q),
        testing:loop(testing:any_of([
            testing:all_of([
              testing:received(a, Q),
              testing:received(b, Q),
              testing:any_of(lists:map(fun(V) -> testing:sent(c, {V}, Q) end, lists:seq(2, 10)))
            ]),
            testing:assert_stop(Q)
        ]))
    ]), C).

procs_s() ->
    Logs = testing:get_log("./test/procs.csp", 'S'),
    {[S], C} = testing:spawn_procs([{'S', none}], Logs),
    testing:expect(testing:all_of([
        testing:assert_start(),
        testing:received(a, S),
        testing:received(b, S),
        testing:sent(c, {1}, S),
        testing:sent(c, {2}, S),
        testing:sent(c, {3}, S),
        testing:assert_stop(S)
    ]), C).

communication_pq() ->
    Logs = testing:get_log("./test/communication.csp", 'PQ'),
    {[P, Q], C} = testing:spawn_procs([{'P', none}, {'Q', none}], Logs),
    testing:expect(testing:all_of([
      testing:assert_relation(P, Q, #{}),
      testing:assert_start(),
      testing:all_of([
        testing:before(
          [testing:sent(a, {'SOME'}, P)],
          testing:sent(b, {'SOME'}, P)),
        testing:before(
          [testing:received(a, Q)],
          testing:received(b, Q))
      ]),
      testing:all_of([
        testing:before(
          [testing:sent(a, {'NONE'}, Q)],
          testing:received(b, Q)),
        testing:before(
          [testing:received(a, P)],
          testing:sent(b, {'NONE'}, P)),
        testing:assert_stop(P),
        testing:assert_stop(Q)
      ])
    ]), C).

external_main() ->
    Logs = testing:get_log("./test/external.csp", 'MAIN'),
    {[P], C} = testing:spawn_procs([{'MAIN', none}], Logs),
    testing:expect(testing:all_of([
        testing:assert_start(),
        testing:all_of(
            lists:foldl(fun(I, Acc) ->
                [ testing:sent(exp, {math:exp(I)}, P),
                  testing:received(exp, P),
                  testing:sent(log, {float(I)}, P),
                  testing:received(log, P) ] ++ Acc
            end, [], lists:seq(2, 10))
        ),
        testing:assert_stop(P)
    ]), C).
