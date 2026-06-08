-module(manager).
-export([manager_listen/2, manager_listen/3, addRelation/4, send/3, recv/3, print/1]).

% Links is a list of triples: {Dest, From, Synced Channels}
% PendingMessages is a map with Key: ChannelName and Value:
%       {sent, sync or async (to know if the PendingMessage is from a channel that is sync or not), PID From, Tuple of Values} 
%       or {expect, sync or async, PID From, Arity of Expected Tuple}
manager_listen(Links, PendingMessages, Debug) ->
    receive
        {recv, ChannelName, ParamNumber, From} ->
            debug("Received a 'recv' with (~s, ~p) from ~p.", [ChannelName, ParamNumber, From], Debug),
            MatchChannelNotSynced = fun() ->
                case PendingMessages of
                % ChannelName is not synched, but there is already a process expecting a value from this channel
                #{ChannelName := {sent, async, AnyDest, Msg}} ->
                    debug("~p received with ~s an async Msg(~p) from ~p", [From, ChannelName, Msg, AnyDest], Debug),
                    From ! {ChannelName, Msg}, AnyDest ! {ChannelName, {}},
                    maps:remove(ChannelName, PendingMessages);

                % if it is an event (ParamNumber == 0) and not synched, just ack the receiver and continue
                _ when ParamNumber == 0 ->
                    debug("an async event(~s) was received by ~p", [ChannelName, From], Debug),
                    From ! {ChannelName, {}}, PendingMessages;

                % Here we just wait for the value
                _ ->
                    debug("~p expects to async receive an Msg of ~p params with ~s", [From, ParamNumber, ChannelName], Debug),
                    PendingMessages#{ChannelName => {expect, async, From, ParamNumber}}
                end
            end,
            manager_listen(Links,
                case manager_search_relations(Links, From) of
                    % TODO: if it is an event it should wait for everyone that has a relation with it to sync
                    Relations -> 
                        debug("~p will try sync with '~s' on relations: ~p.", [From, ChannelName, Relations], Debug),
                        SearchAnyRelOnPendingMessages = 
                            fun Rec([{Dest, #{ ChannelName := _}} | T], _) ->
                                    case PendingMessages of
                                         % Dest has already sent Msg on PendingMessages
                                         #{ChannelName := {sent, sync, Dest, Msg}} -> 
                                            debug("Sync with ~s between (~p, ~p): ~p", [ChannelName, From, Dest, Msg], Debug),
                                            From ! {ChannelName, Msg}, Dest ! {ChannelName, {}},
                                            maps:remove(ChannelName, PendingMessages);
                                         #{ChannelName := {expect, sync, Dest, 0}} -> 
                                            debug("Sync with ~s between (~p, ~p): {}", [ChannelName, From, Dest], Debug),
                                            From ! {ChannelName, {}}, Dest ! {ChannelName, {}},
                                            maps:remove(ChannelName, PendingMessages);
                                         _ -> Rec(T, sync)
                                    end;
                                % The Relation does not sync with ChannelName
                                Rec([{_Dest, _} | T], SyncOrAsync) -> Rec(T, SyncOrAsync);
                                Rec([], sync) ->
                                    % No Pending Relation was found, so we just wait to sync
                                    debug("~p is waiting any of ~p to receive and sync with ~s", [From, Relations, ChannelName], Debug),
                                    PendingMessages#{ChannelName => {expect, sync, From, ParamNumber}};
                                Rec([], async) ->
                                    debug("but ~s is not a synced channel", [ChannelName], Debug),
                                    MatchChannelNotSynced()
                            end, SearchAnyRelOnPendingMessages(Relations, async);
                    [] -> MatchChannelNotSynced()
                end, Debug);
        {send, ChannelName, Msg, From} ->
            debug("Received a 'send' with (~s, ~p) from ~p.", [ChannelName, Msg, From], Debug),
            MatchChannelNotSynced = fun() ->
                case PendingMessages of
                % ChannelName is not synched, but there is already a process expecting a value from this channel
                #{ChannelName := {expect, async, AnyDest, _ParamNumber}} ->
                    debug("~p is async sending a Msg(~p) with ~s to ~p", [From, Msg, ChannelName, AnyDest], Debug),
                    From ! {ChannelName, {}}, AnyDest ! {ChannelName, Msg},
                    maps:remove(ChannelName, PendingMessages);

                % Here we send the value and continue the execution(ack), as we are not synching
                _ -> debug("~p is async sending a Msg(~p) with ~s to anyone that wants it", [From, Msg, ChannelName], Debug),
                    From ! {ChannelName, {}}, PendingMessages#{ChannelName => {sent, async, From, Msg}}
                end
            end,
            manager_listen(Links,
                case manager_search_relations(Links, From) of
                    Relations ->
                        SearchAnyRelOnPendingMessages = 
                            fun Rec([{Dest, #{ ChannelName := _}} | T], _) ->
                                    case PendingMessages of
                                         % Dest has already sent Msg on PendingMessages
                                         #{ChannelName := {expect, sync, Dest, ParamNumber}} ->
                                            debug("Sync with ~s between (~p, ~p): ~p", [ChannelName, From, Dest, Msg], Debug),
                                            From ! {ChannelName, {}}, Dest ! {ChannelName, Msg},
                                            maps:remove(ChannelName, PendingMessages);
                                         _ -> Rec(T, sync)
                                    end;
                                Rec([{_Dest, _} | T], SyncOrAsync) -> Rec(T, SyncOrAsync);
                                Rec([], sync) ->
                                    % No Pending Relation was found, so we just wait to sync
                                    debug("~p is waiting any of ~p to send ~p and sync with ~s", [From, Relations, Msg, ChannelName], Debug),
                                    PendingMessages#{ChannelName => {sent, sync, From, Msg}};
                                Rec([], async) ->
                                    debug("but ~s is not a synced channel", [ChannelName], Debug),
                                    MatchChannelNotSynced()
                            end, SearchAnyRelOnPendingMessages(Relations, async);
                    [] -> MatchChannelNotSynced()
                end, Debug);
        {relation, First, Second, SyncedChs } ->
            debug("Adding a relation between (~p, ~p) with ~p", [First, Second, SyncedChs], Debug),
            manager_listen([{First, Second, SyncedChs} | Links], PendingMessages, Debug)
    end.
manager_listen(Links, PendingMessages) -> manager_listen(Links, PendingMessages, false).

addRelation(ManPID, First, Second, Channels) -> ManPID ! {relation, First, Second, Channels}.

send(ManPID, ChannelName, Msg) ->
    ManPID ! {send, ChannelName, Msg, self()},
    receive {ChannelName, {}} -> {} end.

recv(ManPID, ChannelName, 0) ->
    ManPID ! {recv, ChannelName, 0, self()},
    receive { ChannelName, {} } -> {} end;
recv(ManPID, ChannelName, ParamNumber) ->
    ManPID ! {recv, ChannelName, ParamNumber, self()},
    receive { ChannelName, Data } -> Data end.

print(E) -> io:format("~p\n", [E]), E.

debug(S, Es, true) -> io:format(S++"\n", Es);
debug(_, _, false) -> ok.

% Relations are a list of triples, with the PIDs
% from the sync processes and Chs are the list of sync channels
manager_search_relations([H | T], PID) ->
    case H of
        {PID, Other, Chs} -> [{Other, Chs} | manager_search_relations(T, PID)];
        {Other, PID, Chs} -> [{Other, Chs} | manager_search_relations(T, PID)];
        _ -> manager_search_relations(T, PID)
    end;
manager_search_relations([], _) -> [].
