-module(crawler_sup).
-compile(export_all).

-import(crawler).

start() ->
    supervisor:start_link(?MODULE, []).

stop(Sup) ->
    Shutdown = fun({_, Pid, _, _}) -> crawler:stop(Pid) end,
    lists:foreach(Shutdown, supervisor:which_children(Sup)).

add(Sup) ->
    add(Sup, 1).

add(_, 0) ->
    ok;

add(Sup, N) ->
    supervisor:start_child(Sup, []),
    add(Sup, N - 1).

init([]) ->
    {ok, {{simple_one_for_one, 1, 1}, [{1, {crawler, start, []}, transient, 1, 
                    worker, [crawler]}]}}.