%%% @doc Where the square is, and where the record is said out loud.
%%%
%%% THE SQUARE IS NOT THE KEEPER'S TOPIC. Its org segment names the SPEAKERS,
%%% the schema owner. That segment is NOT an access check: macula verifies who
%%% signed a publication, not who may publish on a topic, so any node in the
%%% realm can publish on the square, on the news wire, or on the keeper's own
%%% record topic. Who counts is decided by asking the realm whether the
%%% publisher is an admitted member of the org that owns the topic
%%% (`mcl_om:org_member/2' with `speakers/0' or `news_sensor/0'), never by the
%%% topic a fact arrived on.
%%%
%%% The square is a set of speaker-owned topics rather than one topic: today
%%% there is one speaker and therefore one topic. Nothing here is built for a
%%% second one, and adding one is a second entry in `square_topics/0'.
%%%
%%% Both paths are canonical macula app facts, `realm/org/app/domain/name_vN',
%%% the org segment being the schema owner. They are fixed here rather than read
%%% from the environment, because they are the contract, not placement.
%%%
%%% The realm NAME the topic carries is checked at start against the realm the
%%% pool publishes in: a keeper listening on a topic nobody publishes to looks
%%% exactly like a quiet square.
-module(agora_post_topic).

-export([realm_name/0, check_realm_name/0, check_realm_name/2]).
-export([square_topics/0, square_topic/1, record_topic/1, conflict_topic/1]).
-export([news_topics/0, news_topic/1, speakers/0, news_sensor/0]).

-define(APP, guide_agora_post_lifecycle).
-define(SPEAKERS, <<"mcl-spartan">>).
-define(KEEPER, <<"mcl-agora">>).
-define(NEWS, <<"mcl-news">>).

%% @doc The org whose admitted nodes are the square's speakers.
-spec speakers() -> binary().
speakers() -> ?SPEAKERS.

%% @doc The org whose admitted nodes report the news a card must match.
-spec news_sensor() -> binary().
news_sensor() -> ?NEWS.

%% @doc The news wire the keeper hears itself, to check every card against.
-spec news_topics() -> [binary()].
news_topics() ->
    [news_topic(realm_name())].

-spec news_topic(binary()) -> binary().
news_topic(RealmName) ->
    macula_topic:app_fact(RealmName, ?NEWS, <<"news">>, <<"wire">>,
                          <<"news_item_reported">>, 1).

%% @doc Every topic a post on the square is published to.
-spec square_topics() -> [binary()].
square_topics() ->
    [square_topic(realm_name())].

%% @doc The square, owned by the speakers. The keeper only ever subscribes.
-spec square_topic(binary()) -> binary().
square_topic(RealmName) ->
    macula_topic:app_fact(RealmName, ?SPEAKERS, <<"agora">>, <<"wire">>,
                          <<"agora_post_published">>, 1).

%% @doc The record, said out loud, under the keeper's own org.
-spec record_topic(binary()) -> binary().
record_topic(RealmName) ->
    macula_topic:app_fact(RealmName, ?KEEPER, <<"agora">>, <<"wire">>,
                          <<"agora_post_recorded">>, 1).

%% @doc A contradiction on the record, said out loud under the keeper's own org.
-spec conflict_topic(binary()) -> binary().
conflict_topic(RealmName) ->
    macula_topic:app_fact(RealmName, ?KEEPER, <<"agora">>, <<"wire">>,
                          <<"agora_post_conflict_detected">>, 1).

%% @doc The realm name the topics carry, from the app env.
-spec realm_name() -> binary().
realm_name() ->
    named(application:get_env(?APP, realm_name, undefined)).

named(Name) when is_list(Name), Name =/= "" -> unicode:characters_to_binary(Name);
named(Name) when is_binary(Name), Name =/= <<>> -> Name;
named(_Unset) -> error({mcl_agora_realm_name_unset, realm_name}).

%% @doc Refuse to start when the realm name is not the realm the pool publishes
%% in: the facts would go where nobody subscribed, and a keeper hearing nothing
%% looks exactly like a quiet square.
-spec check_realm_name() -> ok.
check_realm_name() ->
    configured(realm_name(), mcl_om:realm()).

configured(Name, {ok, Tag}) -> check_realm_name(Name, Tag);
configured(Name, Other)     -> error({mcl_agora_realm_unset, Name, Other}).

%% The topics are built here too, not just hashed: a name that hashes right but
%% is not a valid topic segment would pass the hash and then fail every fact,
%% at publish time and once per post rather than once at boot.
-spec check_realm_name(binary(), binary()) -> ok.
check_realm_name(Name, Tag) ->
    _ = square_topic(Name),
    _ = record_topic(Name),
    _ = conflict_topic(Name),
    _ = news_topic(Name),
    matched(crypto:hash(sha256, Name) =:= Tag, Name, Tag).

matched(true, _Name, _Tag) -> ok;
matched(false, Name, Tag)  -> error({mcl_agora_realm_name_mismatch, Name, Tag}).
