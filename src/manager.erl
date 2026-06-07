-module(manager).
-export([manager_listen/2, addRelation/4, send/3, recv/3, print/1]).

% Links is a list of triples: {Dest, From, Synced Channels}
% PendingMessages is a map with Key: ChannelName and Value:
%       {sent, sync or async (to know if the PendingMessage is from a channel that is sync or not), PID From, Tuple of Values} 
%       or {expect, sync or async, PID From, Arity of Expected Tuple}
manager_listen(Links, PendingMessages) ->
    receive
        {recv, ChannelName, ParamNumber, From} ->
            case {manager_search_relations(Links, From), PendingMessages} of
                {
                 {Dest, #{ ChannelName := ParamNumber }}, % ChannelName is sync between Dest and From
                 #{ChannelName := {sent, sync, Dest, Msg}} % And also Dest has already sent Msg on PendingMessages
                } -> From ! {ChannelName, Msg}, Dest ! {ChannelName, {}},
                    manager_listen(Links, maps:remove(ChannelName, PendingMessages));

                {
                 {Dest, #{ ChannelName := 0 }},      % ChannelName is sync between Dest and From, but its a simple event( ParamNumber = 0)
                 #{ChannelName := {expect, sync, Dest, 0}} % And also Dest has already sent Msg on PendingMessages
                } -> From ! {ChannelName, {}}, Dest ! {ChannelName, {}},
                    manager_listen(Links, maps:remove(ChannelName, PendingMessages));

                % ChannelName is sync between Dest and From, but will need to wait for Dest to sync
                { {_Dest, #{ ChannelName := ParamNumber }}, _} ->
                    manager_listen(Links, PendingMessages#{ChannelName => {expect, sync, From, ParamNumber}});

                % ChannelName is not synched, but there is already a process expecting a value from this channel
                { _, #{ChannelName := {sent, async, AnyDest, Msg}}} ->
                    From ! {ChannelName, Msg}, AnyDest ! {ChannelName, {}},
                    manager_listen(Links, maps:remove(ChannelName, PendingMessages));

                % if it is an event (ParamNumber == 0) and not synched, just ack the receiver and continue
                _ when ParamNumber == 0 -> From ! {ChannelName, {}}, manager_listen(Links, PendingMessages);

                % Here we just wait for the value
                _ -> manager_listen(Links, PendingMessages#{ChannelName => {expect, async, From, ParamNumber}})
            end;
        {send, ChannelName, Msg, From} ->
            case {manager_search_relations(Links, From), PendingMessages} of
                {
                 {Dest, #{ ChannelName := ParamNumber }},      % ChannelName is sync between Dest and From
                 #{ChannelName := {expect, sync, Dest, ParamNumber}} % And also Dest is already expecting for Msg on PendingMessages
                } ->
                    From ! {ChannelName, {}}, Dest ! {ChannelName, Msg},
                    manager_listen(Links, maps:remove(ChannelName, PendingMessages));

                % ChannelName is sync between Dest and From, but will need to wait for Dest to sync
                { {_Dest, #{ ChannelName := _ParamNumber }}, _} ->
                    manager_listen(Links, PendingMessages#{ChannelName => {sent, sync, From, Msg}});

                % ChannelName is not synched, but there is already a process expecting a value from this channel
                { _, #{ChannelName := {expect, async, AnyDest, _ParamNumber}}} ->
                    From ! {ChannelName, {}}, AnyDest ! {ChannelName, Msg},
                    manager_listen(Links, maps:remove(ChannelName, PendingMessages));

                % Here we send the value and continue the execution(ack), as we are not synching
                _ -> From ! {ChannelName, {}}, manager_listen(Links, PendingMessages#{ChannelName => {sent, async, From, Msg}})
            end;
        {relation, First, Second, SyncedChs } ->
            manager_listen([{First, Second, SyncedChs} | Links], PendingMessages);
        debug ->
            io:format("Links: ~p, PendingMessages: ~p\n", [Links, PendingMessages])
    % after 500 -> manager_listen(Links, PendingMessages)
    end.

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

% Relations are a list of triples, with the PIDs
% from the sync processes and Chs are the list of sync channels
manager_search_relations([H | T], PID) ->
    case H of
        {PID, Other, Chs} -> {Other, Chs};
        {Other, PID, Chs} -> {Other, Chs};
        _ -> manager_search_relations(T, PID)
    end;
manager_search_relations([], _) -> no_relation.
