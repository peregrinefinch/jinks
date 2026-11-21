%% SPDX-License-Identifier: Apache-2.0

%% Keep a tag's display spelling, but give canonically equivalent text the
%% same Unicode form. Slugs retain letters, marks and numbers from any script;
%% punctuation becomes one hyphen, never a filesystem separator.
%% https://www.erlang.org/doc/apps/stdlib/unicode.html#characters_to_nfc_binary/1
%% https://www.erlang.org/doc/apps/stdlib/re.html#replace/4
-module(jinks_text).
-export([normalize/1, slug/1]).

normalize(Text) ->
    unicode:characters_to_nfc_binary(string:trim(Text)).

slug(Text) ->
    Lower = unicode:characters_to_nfc_binary(string:lowercase(normalize(Text))),
    Joined = re:replace(Lower, <<"[^\\p{L}\\p{M}\\p{N}]+">>, <<"-">>,
                        [global, unicode, {return, binary}]),
    string:trim(Joined, both, "-").
