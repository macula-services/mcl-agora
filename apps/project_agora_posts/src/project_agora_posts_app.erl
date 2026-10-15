%% @doc OTP application entry for the PRJ department.
-module(project_agora_posts_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> project_agora_posts_sup:start_link().

stop(_State) -> ok.
