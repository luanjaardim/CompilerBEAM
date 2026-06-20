-module(test_csp).
-export([sync_qp/0, sync_rp/0, sync_xz/0, basic_p/0, basic_q/0]).

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
            ],  testing:synched(a, P, Q))
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
                ], testing:synched(c, P, R))
            ]))
        ]),
        C).

sync_xz() ->
    Logs = testing:get_log("./test/sync.csp", 'SYN_XZ'),
    {[X, Z], C} = testing:spawn_procs([{'X', none}, {'Z', none}], Logs),
    testing:expect(
        testing:all_of([
            testing:assert_relation(X, Z, #{a => 0, b => 0}),
            testing:assert_start(),
            testing:before([
                testing:received(a, X),
                testing:received(a, Z)
            ], testing:synched(a, X, Z)),
            testing:before([
                testing:received(b, X),
                testing:received(b, Z)
            ], testing:synched(b, X, Z)),

            % At this point Z will block in 'a' and 'b'
            testing:times(2, testing:any_of([
                testing:received(a, Z),
                testing:received(b, Z)
            ]))
        ]),
        C).

% TODO: complete this test.
% sync_xyz() -> Logs = testing:get_log("./test/sync.csp", 'SYN_XYZ').

basic_p() ->
    Logs = testing:get_log("./test/basic.csp", 'P'),
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
    Logs = testing:get_log("./test/basic.csp", 'Q'),
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
