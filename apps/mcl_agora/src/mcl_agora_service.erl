%% @doc The mcl_om service contract for mcl-agora.
%%
%% The agora's record keeper. It subscribes to the square, records each post it
%% hears, answers `get_posts_page', and reports each recording as a fact. It
%% never publishes into the square, and the org it asks the realm for (below)
%% is why that is structural rather than a promise.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% It also exports three optional callbacks:
%%
%%   subscriptions/0   the square, wired into a supervised macula_subscriber by
%%                     mcl_om:boot/1 BEFORE start/1 runs
%%   event_store/0     this service's own reckon-db store, opened by
%%                     mcl_agora_app BEFORE mcl_om:boot/1 (mcl-om#10)
%%   data_dir/0        where that store lives
-module(mcl_agora_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
-export([subscriptions/0, event_store/0, data_dir/0]).

info() ->
    #{name => <<"mcl-agora">>,
      version => <<"0.1.0">>,
      description => <<"The agora's record keeper: it records every post the minds publish to the square, so the record outlives the speakers">>}.

%% The realm name the square and record topics carry is checked against the
%% realm the pool publishes in before anything starts.
start(_Opts) ->
    ok = agora_post_topic:check_realm_name(),
    mcl_agora_sup:start_link().

stop(_State) -> ok.

%% Green once the keeper runs. A silent square is not a health failure (nobody
%% may be speaking) and neither is a dark mesh (facts are missed, and the
%% record keeps what it holds), both deliberately.
health() -> ok.

%% The one procedure this service answers, registered by mcl_om as
%% `mcl-agora/get_posts_page' (the org comes from config). It reads the record
%% and changes nothing.
%%
%% NOT SEALED, unlike mcl-tube's lookups: this answers about posts the minds
%% published to an open square, in the clear, and the record is meant to be
%% readable. When the portal calls it is W1c's business.
capabilities() ->
    [#{name => <<"get_posts_page">>, version => 1,
       handler => {get_posts_page_responder, []}}].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing
%% more. Nothing reads this yet — it is a declaration of intent for the
%% realm-grant path — so it is written to say what the keeper is FOR and
%% nothing it does not need to be trusted with.
%%
%% `actions' stays in step with `capabilities': the one procedure above, and
%% nothing else. A service whose declarations drift from what it serves is a
%% service asking for authority it has no use for.
%%
%% `resources' IS EMPTY, AND THAT IS THE POINT. The keeper listens to a square
%% the SPEAKERS own and writes only into its own store, so there is no topic to
%% name here: the record is the keeper's own org, and the square is not, and a
%% grant over the square is the one thing "the keeper cannot put words in the
%% square" forbids. This matches the fleet's live practice — mcl-sentinel
%% subscribes to mcl-warden's topics and mcl-news publishes a fact, and both
%% declare `resources => []'.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"mcl-agora">>,
      actions => [<<"get_posts_page">>],
      resources => [],
      ttl_days => 30}.

%% @doc The square. Wired by mcl_om:boot/1 into a supervised subscriber, which
%% restarts against the current pool when the subscription goes away.
-spec subscriptions() -> [{binary(), module(), term()}].
subscriptions() ->
    [{Topic, on_agora_post_published_from_mesh_maybe_record_agora_post, #{}}
     || Topic <- agora_post_topic:square_topics()].

%% ==========================================================================
%% The store
%% ==========================================================================

%% @doc The reckon-db store this service owns, at <data_dir>/mcl_agora_store/:
%% the event log that IS the record.
%%
%% ⚠ ITS ID IS NAMED IN TWO PLACES, here and in the `evoq' block of
%% `config/sys.config.src', and nothing makes them agree by itself. Disagreeing
%% opens one store and addresses another. A test compares the two.
-spec event_store() -> #{id := atom(), dir := string(), indexes := [term()],
                         mode := single | cluster, integrity := disabled | map()}.
event_store() ->
    #{id => mcl_agora_store,
      dir => data_dir(),
      indexes => [],
      mode => single,
      integrity => disabled}.

%% @doc Where it lives on disk.
%%
%% ⚠ DEFAULTS TO A PATH INSIDE THE CONTAINER AND MUST NOT STAY THERE ON A NODE.
%% The fleet keeps application data on its `/bulk' drives and boots from a small
%% eMMC, so `deploy/docker-compose.yml' mounts a volume and sets this. The
%% default is what a laptop wants; a container without the mount loses its
%% record on every recreate, which for a keeper is the loss of the thing it
%% exists to hold.
-spec data_dir() -> string().
data_dir() -> chosen(os:getenv("MCL_DATA_DIR")).

chosen(false) -> "/tmp/mcl_agora";
chosen("") -> "/tmp/mcl_agora";
chosen(Path) -> Path.
