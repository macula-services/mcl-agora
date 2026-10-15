%% @doc This service's reckon-db store, opened by mcl_agora_app BEFORE
%% mcl_om:boot/1, so the departments, already started, find it up.
%%
%% mcl-agora's own copy of the canonical wiring (from mcl_om 0.35 on, mcl_om
%% opens no store; each service owns its persistence, mcl-om#10): start the
%% store, wait until reckon_db lists it, start the per-store evoq subscription
%% so projections and event handlers receive every event. The store's id,
%% directory, indexes, mode and integrity come from
%% mcl_agora_service:event_store/0.
%%
%% FOR A KEEPER THE STORE IS THE PRODUCT, not a cache behind it. The event log
%% under MCL_DATA_DIR holds the record of what every mind said; the
%% get_posts_page read model is rebuilt from this on boot and holds nothing of
%% its own. A node that runs this service without the data directory mounted
%% loses the record on the first container recreate, which is the same as not
%% keeping one.
%%
%% ⚠ config/sys.config.src MUST CARRY THE `evoq' BLOCK: the subscription reads
%% the global log through evoq, which crashes on
%% `{not_configured, event_store_adapter}' without it.
-module(mcl_agora_store).

-include_lib("reckon_db/include/reckon_db.hrl").

-export([open/1, ensure/2, ensure/5]).

-define(READY_TIMEOUT_MS, 30_000).

%% @doc Opens the store the service describes, or stops the boot naming why: a
%% keeper whose store is not there would otherwise start green and drop every
%% post it heard.
-spec open(#{id := atom(), dir := string(), indexes := [term()],
             mode := single | cluster, integrity := disabled | map()}) -> ok.
open(#{id := Id, dir := Dir, indexes := Indexes, mode := Mode, integrity := Integrity}) ->
    opened(ensure(Id, Dir, Indexes, Mode, Integrity)).

opened(ok) -> ok;
opened({error, Why}) -> error({mcl_agora_store_failed, Why}).

%% @doc A single-node store with no indexes, at <Dir>/<Id>/, and its
%% subscription. Idempotent. The tests open their store with it.
-spec ensure(atom(), file:filename_all()) -> ok | {error, term()}.
ensure(Id, Dir) ->
    ensure(Id, Dir, [], single, disabled).

-spec ensure(atom(), file:filename_all(), [term()], single | cluster, disabled | map()) ->
    ok | {error, term()}.
ensure(Id, Dir, Indexes, Mode, Integrity) ->
    subscribed(started(Id, Dir, Indexes, Mode, Integrity), Id).

subscribed(ok, Id) -> subscription(evoq_store_subscription:start_link(Id));
subscribed({error, _} = Err, _Id) -> Err.

started(Id, Dir, Indexes, Mode, Integrity) ->
    SubDir = filename:join(Dir, atom_to_list(Id)),
    ok = filelib:ensure_path(SubDir),
    Config = #store_config{store_id = Id,
                           data_dir = SubDir,
                           mode = Mode,
                           indexes = Indexes,
                           integrity = Integrity,
                           writer_pool_size = 5,
                           reader_pool_size = 5,
                           gateway_pool_size = 1,
                           options = #{}},
    store_start(reckon_db_sup:start_store(Config), Id).

store_start({ok, _Pid}, Id) -> wait_loop(Id, erlang:monotonic_time(millisecond) + ?READY_TIMEOUT_MS);
store_start({error, {already_started, _Pid}}, _Id) -> ok;
store_start({error, Reason}, _Id) -> {error, {start_store_failed, Reason}}.

wait_loop(Id, Deadline) ->
    wait_ready(listed(Id), Id, Deadline).

%% try/catch on purpose: reckon_db_sup can refuse the call while reckon_db is
%% still starting, and that means "not listed yet", which the deadline covers.
listed(Id) ->
    try lists:member(Id, reckon_db_sup:which_stores())
    catch _:_ -> false
    end.

wait_ready(true, _Id, _Deadline) ->
    ok;
wait_ready(false, Id, Deadline) ->
    wait_retry(erlang:monotonic_time(millisecond) > Deadline, Id, Deadline).

wait_retry(true, Id, _Deadline) ->
    {error, {store_not_ready, Id}};
wait_retry(false, Id, Deadline) ->
    timer:sleep(100),
    wait_loop(Id, Deadline).

subscription({ok, _Pid}) -> ok;
subscription({error, {already_started, _Pid}}) -> ok;
subscription({error, Reason}) -> {error, {start_subscription_failed, Reason}}.
