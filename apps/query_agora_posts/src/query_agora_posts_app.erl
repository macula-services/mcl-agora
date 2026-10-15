%% @doc OTP application entry for the QRY department.
-module(query_agora_posts_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> query_agora_posts_sup:start_link().

stop(_State) -> ok.
