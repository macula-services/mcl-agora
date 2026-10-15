%% @doc Supervises the service's own processes. It has none.
%%
%% The keeper is a listener, a store and a query: the subscriber is supervised
%% by mcl_om (it is declared in mcl_agora_service:subscriptions/0, which is
%% what puts it back after a dropped subscription), the aggregate by evoq's own
%% registry, the projection by the PRJ department, and the store by reckon-db.
%% A child here would be a second owner for something that already has one.
-module(mcl_agora_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.
