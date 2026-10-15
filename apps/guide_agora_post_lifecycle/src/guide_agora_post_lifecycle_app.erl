%% @doc OTP application entry for the CMD department.
-module(guide_agora_post_lifecycle_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> guide_agora_post_lifecycle_sup:start_link().

stop(_State) -> ok.
