%% SPDX-License-Identifier: Apache-2.0
%% A narrow transport boundary for explicitly registered data providers.
%% OTP enforces the response limit while reading, including chunked bodies;
%% Pooka owns JSON decoding, caching, pagination and fallback policy.
-module(jinks_fetch).
-export([get/3]).

get(Url, Timeout, Limit) ->
    try
        {ok, _} = application:ensure_all_started([inets, ssl]),
        TLS = case uri_string:parse(Url) of
            #{scheme := <<"https">>} ->
                [{verify, verify_peer},
                 {cacerts, public_key:cacerts_get()},
                 {depth, 4},
                 {customize_hostname_check,
                  [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}];
            _ -> []
        end,
        Options = [{timeout, Timeout}, {connect_timeout, min(Timeout, 5000)},
                   {autoredirect, false}, {ssl, TLS}],
        RequestOptions = [{body_format, binary}, {max_body_size, Limit},
                          {max_header_size, 16384}],
        case httpc:request(get, {binary_to_list(Url), [{"accept", "application/json"}]},
                           Options, RequestOptions) of
            {ok, {{_, Code, _}, _, Body}} when Code >= 200, Code < 300 ->
                {ok, Body};
            {ok, {{_, Code, _}, _, _}} ->
                {error, iolist_to_binary(io_lib:format("HTTP ~B", [Code]))};
            {error, Reason} ->
                {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:Unexpected -> {error, iolist_to_binary(io_lib:format("~p", [Unexpected]))}
    end.
