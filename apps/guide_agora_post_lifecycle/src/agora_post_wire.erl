%%% @doc The record's one outbound shape.
%%%
%%% A recorded post leaves this service in exactly two ways -- as the
%%% `agora_post_recorded_v1' fact on the mesh, and as a row in a
%%% `get_posts_page' reply -- and both are the same post, so both are built
%%% here. Two builders would be two contracts, and the second one would drift.
%%%
%%% Text goes out tagged as CBOR text (`{text, Bin}'), so a consumer outside the
%%% BEAM gets a string and not a byte dump; `publisher' is the one exception,
%%% hex-encoded because a node id is bytes and a reader wants to compare it to
%%% one it already has. Times stay integers. Absent fields are OMITTED rather
%%% than sent as null, so a reader can tell "there was none" from "it was
%%% empty".
-module(agora_post_wire).

-export([to_wire/1]).

-spec to_wire(map()) -> map().
to_wire(Post) ->
    maps:filter(fun(_Key, Value) -> Value =/= undefined end,
                #{post_id     => text_of(post_id, Post),
                  from        => text_of(from, Post),
                  publisher   => publisher_of(Post),
                  body        => text_of(body, Post),
                  in_reply_to => text_of(in_reply_to, Post),
                  item_id     => text_of(item_id, Post),
                  kind        => text_of(kind, Post),
                  posted_at   => maps:get(posted_at, Post, undefined),
                  recorded_at => maps:get(recorded_at, Post, undefined),
                  stimulus    => agora_post_stimulus:to_wire(
                                   maps:get(stimulus, Post, undefined)),
                  publisher_verified => maps:get(publisher_verified, Post, undefined),
                  stimulus_verified  => maps:get(stimulus_verified, Post, undefined)}).

%% A node id is 32 raw bytes and is published in hex, as mcl-sentinel publishes
%% a warden id, so a reader can match it against an id it knows.
publisher_of(Post) ->
    binary_hex(maps:get(publisher, Post, undefined)).

binary_hex(Key) when is_binary(Key), byte_size(Key) =:= 32 ->
    {text, binary:encode_hex(Key, lowercase)};
binary_hex(_AbsentOrNotAKey) ->
    undefined.

text_of(Key, Map) ->
    text(maps:get(Key, Map, undefined)).

text(Bin) when is_binary(Bin), Bin =/= <<>> -> {text, Bin};
text(_AbsentOrEmptyOrNotText)               -> undefined.
