%%% @doc The `agora_post' aggregate: one stream per post on the record.
%%%
%%% The stream exists because a post is evidence. Its id is the post_id the
%%% speaker minted, so a redelivery -- a mesh that hands the same fact over
%%% twice, a subscriber that reconnects mid-flight -- addresses this same
%%% stream and is refused here with the sanctioned no-op `{ok, []}'.
%%%
%%% That refusal IS the idempotency: no second event, so no second
%%% `agora_post_recorded_v1', so no second fact on the mesh and no second
%%% read-model write. A repeat is heard and counted, and nothing else happens.
-module(agora_post_aggregate).

-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> agora_post_state.

init(PostId) ->
    {ok, agora_post_state:new(PostId)}.

%% ⚠ A STREAM ID IS NOT FREE-FORM, AND THIS ONE WAS NOT VALID.
%%
%% reckon_gater_stream_id:validate/1 accepts exactly
%% `^[a-z]{1,32}-[a-f0-9]{32}$', lowercase LETTERS, ONE hyphen, then 32
%% lowercase hex, and reckon-db checks it on EVERY append. The first version
%% of this function was `<<"agora-post-", PostId/binary>>', which has two
%% hyphens AND carries the speaker's id verbatim, so every append would have
%% failed with `{invalid_stream_id, malformed_user_id, _}', the listener would
%% have counted each post as refused, and the record would have stayed empty
%% forever while the service looked perfectly healthy. No unit test caught it,
%% because every one of them meck'd the dispatch or called execute/2 directly;
%% agora_post_stream_id_tests and mcl_agora_store_tests exist so that cannot
%% happen again.
%%
%% The suffix is DERIVED, not carried: 128 bits of the post id's sha256, hex.
%% Passing the speaker's own id through would make the keeper's storage layout
%% a function of somebody else's identifier format, and a post_id that is not
%% 32 hex characters would silently break the record. Deriving it keeps
%% `post_id' whatever the speaker wants it to be.
%%
%% Deterministic, which is the whole point: a redelivery must address the SAME
%% stream, so the same post_id must always give the same id.
-spec stream_id(binary()) -> binary().
stream_id(PostId) when is_binary(PostId) ->
    <<"agorapost-", (suffix(PostId))/binary>>.

suffix(PostId) ->
    <<Bits:16/binary, _/binary>> = crypto:hash(sha256, PostId),
    binary:encode_hex(Bits, lowercase).

apply(State, Event) ->
    agora_post_state:apply_event(State, Event).

%% `command_type' is read out of the command's own payload (evoq takes it from
%% there, not from the type evoq_command:new/4 was handed), which is why
%% record_agora_post_v1:to_map/1 spells it as a binary.
execute(State, #{command_type := <<"record_agora_post">>} = Payload) ->
    recorded(agora_post_state:recorded(State), Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

recorded(true, _Payload) ->
    %% Already on the record. The no-op: the caller reads it as a duplicate.
    {ok, []};
recorded(false, Payload) ->
    maybe_record_agora_post:handle_from_map(Payload).
