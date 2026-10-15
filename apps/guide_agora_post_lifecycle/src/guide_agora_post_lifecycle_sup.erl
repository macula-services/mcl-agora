%%% @doc Supervises the CMD department's own processes: the mesh emitter that
%%% says each recorded post out loud.
%%%
%%% The listener is NOT here. It is a `macula_subscriber' declared by the
%%% service module (`mcl_agora_service:subscriptions/0') and started by
%%% `mcl_om:boot/1' under its own supervisor, so the one thing that must come
%%% back after a dropped subscription is managed by the layer that knows the
%%% mesh went away. The module lives in this app because it is this
%%% department's input; its supervision does not belong to it.
%%%
%%% No aggregate children either: evoq's own aggregate registry starts
%%% `agora_post_aggregate' on demand, keyed by post id, the first time a
%%% command dispatches against it.
-module(guide_agora_post_lifecycle_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(emit_agora_post_recorded_v1_to_mesh, evoq_event_handler, start_link,
              [emit_agora_post_recorded_v1_to_mesh, #{}, #{}])
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

worker(Id, Module, Function, Args) ->
    #{id       => Id,
      start    => {Module, Function, Args},
      restart  => permanent,
      shutdown => 5000,
      type     => worker,
      modules  => [Module]}.
