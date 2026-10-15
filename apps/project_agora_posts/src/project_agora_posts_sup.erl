%%% @doc Supervises the PRJ department: the read-model store every QRY desk
%%% reads through, and the projection that fills it.
%%%
%%% Order matters here and nothing else enforces it: the store starts first, so
%%% the ETS tables exist before the projection's first replayed event arrives.
-module(project_agora_posts_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(project_agora_posts_store, project_agora_posts_store, start_link, []),
        worker(agora_post_recorded_v1_to_posts, evoq_projection, start_link,
              [agora_post_recorded_v1_to_posts, #{}, #{}])
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

worker(Id, Module, Function, Args) ->
    #{id       => Id,
      start    => {Module, Function, Args},
      restart  => permanent,
      shutdown => 5000,
      type     => worker,
      modules  => [Module]}.
