-module(manager).
-export([manager_listen/2, manager_listen/3, add_relation/4, spawn_proc/4, send/3, recv/3, debug/4]).

% Links is a list of triples: {Dest, From, Synced Channels}
% PendingMessages is a map with Key: ChannelName and Value:
%       {sent, sync or async (to know if the PendingMessage is from a channel that is sync or not), PID From, Tuple of Values} 
%       or {expect, sync or async, PID From, Arity of Expected Tuple}
% Context contain all spawned procs and their PID
manager_listen(Links, PendingMessages, Context, Debug) ->
    receive
        {recv, ChannelName, ParamNumber, From} ->
            debug("Received a 'recv' with (~s, ~p) from ~p.", {recv, ChannelName, pid_to_list(From)}, [ChannelName, ParamNumber, From], Debug),
            MatchChannelNotSynced = fun() ->
                case PendingMessages of
                % ChannelName is not synched, but there is already a process expecting a value from this channel
                #{ChannelName := {sent, async, AnyDest, Msg}} ->
                    debug("~p received with ~s an async Msg(~p) from ~p", {}, [From, ChannelName, Msg, AnyDest], Debug),
                    From ! {ChannelName, Msg}, AnyDest ! {ChannelName, {}},
                    maps:remove(ChannelName, PendingMessages);

                % if it is an event (ParamNumber == 0) and not synched, just ack the receiver and continue
                _ when ParamNumber == 0 ->
                    debug("an async event(~s) was received by ~p", {}, [ChannelName, From], Debug),
                    From ! {ChannelName, {}}, PendingMessages;

                % Here we just wait for the value
                _ ->
                    debug("~p expects to async receive an Msg of ~p params with ~s", {}, [From, ParamNumber, ChannelName], Debug),
                    PendingMessages#{ChannelName => {expect, async, From, ParamNumber}}
                end
            end,
            manager_listen(Links,
                case manager_search_relations(Links, From) of
                    % TODO: if it is an event it should wait for everyone that has a relation with it to sync
                    Relations = [ _ | _ ] ->
                        debug("~p will try sync with '~s' on relations: ~p.", {}, [From, ChannelName, Relations], Debug),
                        SearchAnyRelOnPendingMessages = 
                            fun Rec([{Dest, #{ ChannelName := _}} | T], _) ->
                                    case PendingMessages of
                                         % Dest has already sent Msg on PendingMessages
                                         #{ChannelName := {sent, sync, Dest, Msg}} ->
                                            debug("Sync with ~s between (~p, ~p): ~p", {sync, ChannelName, pid_to_list(From), pid_to_list(Dest)}, [ChannelName, From, Dest, Msg], Debug),
                                            From ! {ChannelName, Msg}, Dest ! {ChannelName, {}},
                                            maps:remove(ChannelName, PendingMessages);
                                         #{ChannelName := {expect, sync, Dest, 0}} ->
                                            debug("Sync with ~s between (~p, ~p): {}", {sync, ChannelName, pid_to_list(From), pid_to_list(Dest)}, [ChannelName, From, Dest], Debug),
                                            From ! {ChannelName, {}}, Dest ! {ChannelName, {}},
                                            maps:remove(ChannelName, PendingMessages);
                                         _ -> Rec(T, sync)
                                    end;
                                % The Relation does not sync with ChannelName
                                Rec([{_Dest, _} | T], SyncOrAsync) -> Rec(T, SyncOrAsync);
                                Rec([], sync) ->
                                    % No Pending Relation was found, so we just wait to sync
                                    debug("~p is waiting any of ~p to receive and sync with ~s", {}, [From, Relations, ChannelName], Debug),
                                    PendingMessages#{ChannelName => {expect, sync, From, ParamNumber}};
                                Rec([], async) ->
                                    debug("but ~s is not a synced channel", {}, [ChannelName], Debug),
                                    MatchChannelNotSynced()
                            end, SearchAnyRelOnPendingMessages(Relations, async);
                    [] -> MatchChannelNotSynced()
                end, Context, Debug);
        {send, ChannelName, Msg, From} ->
            debug("Received a 'send' with (~s, ~p) from ~p.", {send, ChannelName, Msg, pid_to_list(From)}, [ChannelName, Msg, From], Debug),
            MatchChannelNotSynced = fun() ->
                case PendingMessages of
                % ChannelName is not synched, but there is already a process expecting a value from this channel
                #{ChannelName := {expect, async, AnyDest, _ParamNumber}} ->
                    debug("~p is async sending a Msg(~p) with ~s to ~p", {}, [From, Msg, ChannelName, AnyDest], Debug),
                    From ! {ChannelName, {}}, AnyDest ! {ChannelName, Msg},
                    maps:remove(ChannelName, PendingMessages);

                % Here we send the value and continue the execution(ack), as we are not synching
                _ -> debug("~p is async sending a Msg(~p) with ~s to anyone that wants it", {}, [From, Msg, ChannelName], Debug),
                    From ! {ChannelName, {}}, PendingMessages#{ChannelName => {sent, async, From, Msg}}
                end
            end,
            manager_listen(Links,
                case manager_search_relations(Links, From) of
                    Relations = [_ | _] ->
                        SearchAnyRelOnPendingMessages = 
                            fun Rec([{Dest, #{ ChannelName := _}} | T], _) ->
                                    case PendingMessages of
                                         % Dest has already sent Msg on PendingMessages
                                         #{ChannelName := {expect, sync, Dest, _}} ->
                                            debug("Sync with ~s between (~p, ~p): ~p", {sync, ChannelName, pid_to_list(From), pid_to_list(Dest)}, [ChannelName, From, Dest, Msg], Debug),
                                            From ! {ChannelName, {}}, Dest ! {ChannelName, Msg},
                                            maps:remove(ChannelName, PendingMessages);
                                         _ -> Rec(T, sync)
                                    end;
                                Rec([{_Dest, _} | T], SyncOrAsync) -> Rec(T, SyncOrAsync);
                                Rec([], sync) ->
                                    % No Pending Relation was found, so we just wait to sync
                                    debug("~p is waiting any of ~p to send ~p and sync with ~s", {}, [From, Relations, Msg, ChannelName], Debug),
                                    PendingMessages#{ChannelName => {sent, sync, From, Msg}};
                                Rec([], async) ->
                                    debug("but ~s is not a synced channel", {}, [ChannelName], Debug),
                                    MatchChannelNotSynced()
                            end, SearchAnyRelOnPendingMessages(Relations, async);
                    [] -> MatchChannelNotSynced()
                end, Context, Debug);
        {relation, First, Second, SyncedChs} ->
            debug("Adding a relation between (~p, ~p) with ~p", {add_relation, pid_to_list(First), pid_to_list(Second), maps:from_list(SyncedChs)}, [First, Second, SyncedChs], Debug),
            manager_listen([{First, Second, maps:from_list(SyncedChs)} | Links], PendingMessages, Context, Debug);
        {spawn_proc, Proc, ProcFunction, Args, From} ->
            #{pids := Pids} = Context,
            % TODO: Args is none a list a of lists(so we can call: P(1)(2)), define a function that create a inner function for each params
            SpawnProc = fun() ->
                receive
                    {start, As} -> case As of none -> ProcFunction(); _ -> ProcFunction(As) end
                end
            end,
            PID = spawn(SpawnProc),
            From ! PID,
            debug("Creating a Proc ~s with args: ~p -> ~p", {spawn, Proc, Args, pid_to_list(PID)}, [Proc, Args, PID], Debug),
            NewContext = case Pids of
                #{Proc := L} ->  #{pids => Pids#{ Proc => [{PID, Args} | L]}};
                _ -> #{pids => Pids#{ Proc => [{PID, Args}]}}
            end, manager_listen(Links, PendingMessages, NewContext, Debug);
        start ->
            debug("Starting all created Procs...", {start}, [], Debug),
            maps:foreach(fun(_, PIDs) ->
                lists:foreach(fun({PID, Arguments}) ->
                     PID ! {start, Arguments} end, PIDs) end, maps:get(pids, Context)),
            manager_listen(Links, PendingMessages, Context, Debug)
    end.
manager_listen(Links, PendingMessages, Debug) -> manager_listen(Links, PendingMessages, create_context(), Debug).
manager_listen(Links, PendingMessages) -> manager_listen(Links, PendingMessages, create_context(), false).

create_context() -> #{pids => #{}}.

% Lhs and Rhs
add_relation(ManPID, Lhs, Rhs, Channels) ->
    lists:foreach(fun(X)->
        lists:foreach(fun(Y)-> ManPID ! {relation, X, Y, Channels} end, Rhs) end, Lhs),
    Lhs ++ Rhs.
spawn_proc(ManPID, Proc, Func, Args) -> ManPID ! {spawn_proc, Proc, Func, Args, self()}, receive PID -> [PID] end.

send(ManPID, ChannelName, Msg) ->
    ManPID ! {send, ChannelName, Msg, self()},
    receive {ChannelName, {}} -> {} end.

recv(ManPID, ChannelName, 0) ->
    ManPID ! {recv, ChannelName, 0, self()},
    receive { ChannelName, {} } -> {} end;
recv(ManPID, ChannelName, ParamNumber) ->
    ManPID ! {recv, ChannelName, ParamNumber, self()},
    receive { ChannelName, Data } -> Data end.

debug(S, _, Es, true) -> io:format(S++"\n", Es);
debug(_, {}, _, log) -> ok;
debug(_, Log, _, log) -> {ok, Fd} = file:open(".log", [append]), io:format(Fd, "~p.\n", [Log]), file:close(Fd);
debug(_, _, _, false) -> ok.

% Relations are a list of triples, with the PIDs
% from the sync processes and Chs are the list of sync channels
manager_search_relations([H | T], PID) ->
    case H of
        {PID, Other, Chs} -> [{Other, Chs} | manager_search_relations(T, PID)];
        {Other, PID, Chs} -> [{Other, Chs} | manager_search_relations(T, PID)];
        _ -> manager_search_relations(T, PID)
    end;
manager_search_relations([], _) -> [].
