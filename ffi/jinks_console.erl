%% SPDX-License-Identifier: Apache-2.0
%% Ask the output device rather than guessing from TERM in a redirected shell.
-module(jinks_console).
-export([terminal/0]).
terminal() ->
    try io:columns() of {ok, _} -> true; _ -> false
    catch _:_ -> false end.
