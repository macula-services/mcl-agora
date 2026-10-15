%% @doc The service contract, asserted locally.
%%
%% mcl_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(mcl_om_service)' attribute on the service
%% module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the
%% attribute has not been quietly dropped, that the values inside those
%% callbacks are the shapes mcl_om will destructure, that the store id is named
%% the same way in both places it appears, and that the two names this service
%% answers to agree. Nothing local boots mcl_om, so asserting the shape by hand
%% is the closest available thing to a rehearsal.
-module(mcl_agora_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_agora).
-define(SERVICE, mcl_agora_service).
-define(LISTENER, on_agora_post_published_from_mesh_maybe_record_agora_post).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

%% The three this service adds to the contract, and each is load-bearing:
%% without subscriptions/0 the keeper subscribes to nothing and records
%% nothing; without event_store/0 mcl_agora_app has no store to open.
exports_the_optional_callbacks_it_relies_on_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Optional = [{subscriptions, 0}, {event_store, 0}, {data_dir, 0}],
    Missing = [F || {N, A} = F <- Optional,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"mcl-agora">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing
%% with the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

health_is_green_test() ->
    ?assertEqual(ok, ?SERVICE:health()).

%% The one procedure, under the org config names. Adding a second breaks this
%% so someone writes down what the service can now be called for.
answers_exactly_one_procedure_test() ->
    [Capability] = ?SERVICE:capabilities(),
    ?assertEqual(<<"get_posts_page">>, maps:get(name, Capability)),
    ?assertEqual(1, maps:get(version, Capability)),
    ?assertEqual({get_posts_page_responder, []}, maps:get(handler, Capability)).

%% ⚠ THE STORE ID IS NAMED IN TWO PLACES AND NOTHING ELSE MAKES THEM AGREE.
%% evoq resolves its fallback store from the app env; the service opens a store
%% from event_store/0. Disagreeing opens one store and addresses another, which
%% boots green and writes nowhere.
the_store_id_agrees_between_the_service_and_the_config_test() ->
    #{id := Id} = ?SERVICE:event_store(),
    {evoq, Evoq} = lists:keyfind(evoq, 1, substituted_config()),
    ?assertEqual(Id, proplists:get_value(store_id, Evoq)).

%% The store directory comes from data_dir/0, and the compose file has to mount
%% it and point the variable at the mount -- or the record lands inside the
%% container and dies with the first recreate, which for a keeper is the loss
%% of the thing it exists to hold.
the_store_lands_where_the_compose_file_mounts_it_test() ->
    #{dir := Dir} = ?SERVICE:event_store(),
    ?assertEqual(?SERVICE:data_dir(), Dir),
    Compose = read("deploy/docker-compose.yml"),
    ?assertNotEqual(nomatch, binary:match(Compose, <<"MCL_DATA_DIR=/data">>)),
    ?assertNotEqual(nomatch, binary:match(Compose, <<":/data">>)).

%% Both topics are built from the realm name at start, so these two need it
%% configured. Everything else in this module reads only literals.
the_topics_test_() ->
    {setup, fun configure_realm/0, fun unconfigure_realm/1,
     fun(_) ->
             [%% THE LISTENER IS DECLARED, NOT HARD-WIRED. If subscriptions/0
              %% stopped naming it, the keeper would boot green and hear nothing
              %% at all, which looks exactly like a quiet square.
              fun the_square_is_subscribed_with_the_listener/0,
              %% THE AUTHORITY THIS SERVICE DOES NOT ASK FOR. The square belongs
              %% to the speakers; the keeper subscribing to it is not a grant to
              %% write to it, and this asserts the keeper never claims one.
              fun identity_spec_claims_no_authority_over_the_square/0]
     end}.

the_square_is_subscribed_with_the_listener() ->
    Subscriptions = ?SERVICE:subscriptions(),
    ?assertEqual([<<"io.macula/mcl-spartan/agora/wire/agora_post_published_v1">>],
                 [Topic || {Topic, _Mod, _Args} <- Subscriptions]),
    ?assertEqual([?LISTENER], [Mod || {_Topic, Mod, _Args} <- Subscriptions]).

identity_spec_claims_no_authority_over_the_square() ->
    #{scope := Scope, actions := Actions,
      resources := Resources, ttl_days := Ttl} = ?SERVICE:identity_spec(),
    ?assert(is_binary(Scope)),
    ?assert(is_integer(Ttl) andalso Ttl > 0),
    %% In step with capabilities/0, which is the whole reason to state them.
    ?assertEqual([<<"get_posts_page">>], Actions),
    %% NOTHING, named. The keeper writes into its own org's store and reads a
    %% square that belongs to the speakers, so there is no topic it needs the
    %% realm to authorise, and the square is the one it must never be given.
    ?assertEqual([], Resources).

configure_realm() ->
    _ = application:load(guide_agora_post_lifecycle),
    Existing = application:get_env(guide_agora_post_lifecycle, realm_name),
    application:set_env(guide_agora_post_lifecycle, realm_name, "io.macula"),
    Existing.

unconfigure_realm(undefined) ->
    application:unset_env(guide_agora_post_lifecycle, realm_name);
unconfigure_realm({ok, Value}) ->
    application:set_env(guide_agora_post_lifecycle, realm_name, Value).

%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, DELIBERATELY. A green suite
%% on a release you do not ship means less than it looks like it means. The
%% team images' tags name a date, not a release, so the builder and lint each
%% assert the release in a check step; this compares those, the .tool-versions
%% pin, and this VM, to the patch.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Check = "\\{<<\"([0-9]+\\.[0-9]+\\.[0-9]+)\">>, true\\} -> halt\\(0\\);",
    Image = pinned("Containerfile", Check),
    CiCheck = pinned(".github/workflows/lint.yml", Check),
    Tools = pinned(".tool-versions", "^erlang ([0-9]+\\.[0-9]+\\.[0-9]+)$"),
    ?assertEqual([Image], lists:usort([Image, CiCheck, Tools, running_otp()])).

%% Build, CI and runtime are the team pair, named by dated tag AND digest, so a
%% re-pushed tag cannot change what builds or what runs.
images_are_the_digest_pinned_team_pair_test() ->
    Digest = ":[0-9]{8}-[0-9]{4}@sha256:[0-9a-f]{64}",
    ?assertMatch(<<_/binary>>,
                 pinned("Containerfile",
                        "^FROM (ghcr\\.io/macula-io/macula-ci-otp)" ++ Digest ++ " AS builder$")),
    ?assertMatch(<<_/binary>>,
                 pinned("Containerfile",
                        "^FROM (ghcr\\.io/macula-io/macula-pq-runtime)" ++ Digest ++ "$")),
    ?assertMatch(<<_/binary>>,
                 pinned(".github/workflows/lint.yml",
                        "^\\s+image: (ghcr\\.io/macula-io/macula-ci-otp)" ++ Digest ++ "$")).

%% The image says which commit it was built from, so a digest a fleet pins can
%% be traced to its commit.
the_image_carries_its_revision_test() ->
    ?assertEqual(<<"REVISION">>, pinned("Containerfile", "^ARG (REVISION)=unknown$")),
    ?assertEqual(<<"${REVISION}">>,
                 pinned("Containerfile",
                        "^LABEL org\\.opencontainers\\.image\\.revision=\"([^\"]+)\"$")),
    ?assertEqual(<<"${{ github.sha }}">>,
                 pinned(".github/workflows/build-push.yml", "^\\s+REVISION=(.+)$")).

%% /health is a Unix socket, not a port: a service on mcl_om 0.39 takes no port
%% from the fleet's registry, and claiming one it does not need would collide
%% with a sibling on a host-networked box.
health_is_a_socket_and_not_a_port_test() ->
    ?assertEqual(<<"/run/mcl/health.sock">>,
                 pinned("config/sys.config.src", "health_socket,\\s+\"([^\"]+)\"")),
    ?assertEqual(<<"/run/mcl/health.sock">>,
                 pinned("Containerfile", "^\\s+CMD curl -fsS --unix-socket ([^ ]+) ")),
    ?assertMatch(nomatch, re:run(read("Containerfile"), "MCL_HEALTH_PORT")).

%% The full release, 28.4.3 and not 28: `otp_release' names only the major.
running_otp() ->
    {ok, Version} = file:read_file(filename:join([code:root_dir(), "releases",
                                                  erlang:system_info(otp_release),
                                                  "OTP_VERSION"])),
    string:trim(Version).

%%------------------------------------------------------------------------------

%% Substituted the way relx does, so a file that only parses with its ${...}
%% in place cannot pass by accident.
substituted_config() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Named = re:replace(Text, <<"\"\\$\\{([A-Z_]+)\\}\"">>, <<"\"\\1\"">>, [global]),
    Substituted = re:replace(Named, <<"\\$\\{[A-Z_]+\\}">>, <<"0">>, [global, {return, list}]),
    {ok, Tokens, _End} = erl_scan:string(Substituted),
    {ok, Config} = erl_parse:parse_term(Tokens),
    Config.

read(Relative) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    Text.

pinned(Relative, Pattern) ->
    {match, [Version]} = re:run(read(Relative), Pattern,
                                [multiline, {capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
