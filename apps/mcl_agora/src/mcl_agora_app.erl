%% @doc OTP application entry.
%%
%% Opens this service's own reckon-db store and its evoq subscription
%% (mcl_agora_store, from mcl_agora_service:event_store/0), THEN lets
%% mcl_om:boot/1 wire the mesh, the realm identity, capabilities and health and
%% start the service. mcl_om opens no store (0.35, mcl-om#10).
%%
%% The three departments start before this app does (they are listed in the
%% .app.src applications tuple), so by the time the store subscription starts
%% its catch-up replay here, the projection is already registered and every
%% recorded post is back in the read model.
-module(mcl_agora_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    ok = mcl_agora_store:open(mcl_agora_service:event_store()),
    mcl_om:boot(mcl_agora_service).

stop(_State) -> ok.
