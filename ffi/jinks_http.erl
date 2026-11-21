%% SPDX-License-Identifier: Apache-2.0

%% A small development transport, not a production HTTP stack. OTP decodes
%% request lines and headers; Pooka decides paths, MIME types, and responses.
%% Passive sockets have bounded reads, headers and concurrent connections.
%% https://www.erlang.org/doc/apps/kernel/gen_tcp.html
-module(jinks_http).
-export([start/4, stop/1, update/2, target/2, alive/1, digest/1]).

start(Host, Port, Live, Handler) ->
    Parent = self(),
    Ref = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() -> boot(Parent, Ref, Host, Port, Live, Handler) end),
    receive
        {Ref, Reply} -> erlang:demonitor(Monitor, [flush]), Reply;
        {'DOWN', Monitor, process, Pid, Reason} -> failure(Reason)
    after 5000 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end,
        receive {Ref, _} -> ok after 0 -> ok end,
        {error, <<"development server startup timed out">>}
    end.

boot(Parent, Ref, Host, Port, Live, Handler) ->
    case inet:parse_address(binary_to_list(Host)) of
        {ok, Address} ->
            Family = case tuple_size(Address) of 8 -> [inet6]; _ -> [] end,
            Options = Family ++ [binary, {ip, Address}, {active, false},
                {packet, http_bin}, {packet_size, 16384}, {reuseaddr, true},
                {send_timeout, 2000}, {send_timeout_close, true}, {backlog, 64}],
            case gen_tcp:listen(Port, Options) of
                {ok, Listen} ->
                    process_flag(trap_exit, true),
                    Owner = erlang:monitor(process, Parent),
                    Table = ets:new(jinks_preview, [set, public]),
                    ets:insert(Table, {view, Handler, <<"{\"revision\":0,\"error\":\"\"}">>}),
                    {ok, Actual} = inet:port(Listen),
                    Parent ! {Ref, {ok, {{self(), Table}, Actual}}},
                    accept(Listen, Table, Live, Owner, []);
                {error, Reason} -> Parent ! {Ref, failure(Reason)}
            end;
        _ -> Parent ! {Ref, {error, <<"invalid listen address">>}}
    end.

accept(Listen, Table, Live, Owner, Workers) ->
    receive
        {stop, From, Ref} ->
            shutdown(Listen, Workers),
            From ! {Ref, ok};
        {'DOWN', Owner, process, _, _} -> shutdown(Listen, Workers);
        {'EXIT', Worker, _} -> accept(Listen, Table, Live, Owner, lists:delete(Worker, Workers))
    after 0 ->
        case gen_tcp:accept(Listen, 100) of
            {ok, Socket} when length(Workers) < 64 ->
                Worker = spawn_link(fun() ->
                    receive {socket, S} ->
                        try request(S, Table, Live) catch _:_ -> ok
                        after gen_tcp:close(S) end
                    end
                end),
                case gen_tcp:controlling_process(Socket, Worker) of
                    ok -> Worker ! {socket, Socket}, accept(Listen, Table, Live, Owner, [Worker | Workers]);
                    _ -> gen_tcp:close(Socket), exit(Worker, kill), accept(Listen, Table, Live, Owner, Workers)
                end;
            {ok, Socket} -> gen_tcp:close(Socket), accept(Listen, Table, Live, Owner, Workers);
            {error, timeout} -> accept(Listen, Table, Live, Owner, Workers);
            {error, _} -> shutdown(Listen, Workers)
        end
    end.

shutdown(Listen, Workers) ->
    gen_tcp:close(Listen),
    lists:foreach(fun(Pid) ->
        Monitor = erlang:monitor(process, Pid),
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end
    end, Workers).

request(Socket, Table, Live) ->
    case gen_tcp:recv(Socket, 0, 2000) of
        {ok, {http_request, Method, {abs_path, Path}, Version}}
                when Version == {1, 0}; Version == {1, 1} ->
            case headers(Socket, 0, 0) of
                ok -> dispatch(Socket, Table, Live, Method, Path);
                error -> response(Socket, false, {400, <<"text/plain; charset=utf-8">>, <<"Bad request">>})
            end;
        _ -> response(Socket, false, {400, <<"text/plain; charset=utf-8">>, <<"Bad request">>})
    end.

headers(_Socket, Count, Bytes) when Count > 64; Bytes > 32768 -> error;
headers(Socket, Count, Bytes) ->
    case gen_tcp:recv(Socket, 0, 2000) of
        {ok, http_eoh} -> ok;
        {ok, {http_header, _, _, Name, Value}} ->
            headers(Socket, Count + 1, Bytes + byte_size(Name) + byte_size(Value));
        _ -> error
    end.

dispatch(Socket, Table, true, Method, <<"/__jinks/status">>) when Method == 'GET'; Method == 'HEAD' ->
    [{view, _Handler, State}] = ets:lookup(Table, view),
    response(Socket, Method == 'HEAD', {200, <<"application/json">>, State});
dispatch(Socket, Table, true, 'GET', <<"/__jinks/events">>) ->
    gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n">>),
    inet:setopts(Socket, [{active, once}]),
    stream(Socket, Table, undefined, 0);
dispatch(Socket, Table, _Live, Method, Path) ->
    [{view, Handler, State}] = ets:lookup(Table, view),
    Verb = case Method of Atom when is_atom(Atom) -> atom_to_binary(Atom); Bin -> Bin end,
    Reply = try Handler(Verb, Path, State) catch _:_ -> {500, <<"text/plain">>, <<"Preview request failed">>} end,
    response(Socket, Method == 'HEAD', Reply).

response(Socket, Head, {Status, Type, Body}) ->
    Reason = case Status of
        200 -> <<"OK">>; 400 -> <<"Bad Request">>; 403 -> <<"Forbidden">>;
        404 -> <<"Not Found">>; 405 -> <<"Method Not Allowed">>; _ -> <<"Internal Server Error">>
    end,
    Header = [<<"HTTP/1.1 ">>, integer_to_binary(Status), <<" ">>, Reason,
        <<"\r\nContent-Type: ">>, Type, <<"\r\nContent-Length: ">>, integer_to_binary(byte_size(Body)),
        <<"\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n">>,
        case Status of 405 -> <<"Allow: GET, HEAD\r\n">>; _ -> <<>> end, <<"\r\n">>],
    gen_tcp:send(Socket, [Header, case Head of true -> <<>>; false -> Body end]).

%% Handler and revision share one ETS row, so an HTTP page cannot be stamped
%% with a revision read from a different output target.
%% Each connection reads a small shared snapshot. A disconnect is noticed by
%% the next event or heartbeat; send_timeout keeps an abandoned tab bounded.
stream(Socket, Table, Previous, Ticks) ->
    [{view, _Handler, State}] = ets:lookup(Table, view),
    Send = case State =/= Previous of
        true -> gen_tcp:send(Socket, [<<"data: ">>, State, <<"\n\n">>]);
        false when Ticks rem 40 == 0 -> gen_tcp:send(Socket, <<": still here\n\n">>);
        false -> ok
    end,
    case Send of
        ok -> receive
            {tcp_closed, Socket} -> ok;
            {tcp_error, Socket, _} -> ok;
            {tcp, Socket, _} -> ok
        after 250 -> stream(Socket, Table, State, Ticks + 1) end;
        _ -> ok
    end.

stop({Pid, _Table}) ->
    Monitor = erlang:monitor(process, Pid),
    Ref = make_ref(),
    Pid ! {stop, self(), Ref},
    receive
        {Ref, ok} ->
            receive {'DOWN', Monitor, process, Pid, _} -> {ok, nil} end;
        {'DOWN', Monitor, process, Pid, _} -> {ok, nil}
    after 5000 ->
        erlang:demonitor(Monitor, [flush]),
        {error, <<"development server did not stop in time">>}
    end.

update({_Pid, Table}, State) ->
    try ets:update_element(Table, view, {3, State}), {ok, nil}
    catch error:badarg -> {error, <<"development server has stopped">>} end.

target({_Pid, Table}, Handler) ->
    try ets:update_element(Table, view, {2, Handler}), {ok, nil}
    catch error:badarg -> {error, <<"development server has stopped">>} end.

alive({Pid, _Table}) -> is_process_alive(Pid).
digest(Bytes) -> crypto:hash(sha256, Bytes).

failure(Reason) -> {error, unicode:characters_to_binary(io_lib:format("development server: ~p", [Reason]))}.
