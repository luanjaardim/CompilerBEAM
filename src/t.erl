-module(t).
-export([t/0]).

t() ->
    Wait = fun() -> receive start -> ok end end,
    % Start the Manager Thread.
    PID = spawn(fun() -> manager:manager_listen([], #{}) end),
    Send = fun(ChannelName, Msg) -> manager:send(PID, ChannelName, Msg) end,
    Recv = fun(ChannelName, ParamNumber) -> manager:recv(PID, ChannelName, ParamNumber) end,
    P_PID = spawn(fun() -> Wait(), manager:print("start P"), V = Recv(a, 1), Send(b, V), manager:print(V) end),
    Q_PID = spawn(fun() -> Wait(), manager:print("start Q"), Send(a, oioi), V = Recv(b, 1), Recv(c, 0), manager:print(V) end),
    manager:addRelation(PID, P_PID, Q_PID, #{a => 1, b => 1}),
    P_PID ! Q_PID ! start.
