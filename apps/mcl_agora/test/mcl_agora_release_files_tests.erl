%%% @doc The version sites, asserted against each other.
%%%
%%% The version a peer reads off the mesh (info/0), the OTP application's vsn
%%% and the relx release the image ships are one number written in three
%%% files, and nothing in the build reads them together. 0.4.0 went out with
%%% its release string still at 0.3.1 for exactly that reason: the mesh, the
%%% release directory and `bin/mcl_agora versions' then disagreed while every
%%% other test stayed green, because only this one compares them.
-module(mcl_agora_release_files_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_agora).
-define(SERVICE, mcl_agora_service).

the_versions_agree_test() ->
    #{version := Reported} = ?SERVICE:info(),
    _ = application:load(?APP),
    {ok, App} = application:get_key(?APP, vsn),
    {match, [Release]} = re:run(read("rebar.config"),
                                <<"\\{release, \\{mcl_agora, \"([^\"]+)\"\\}">>,
                                [{capture, all_but_first, binary}]),
    ?assertEqual({Reported, Reported}, {list_to_binary(App), Release}).

%% EVERY APP THE RELEASE NAMES CARRIES THE RELEASE VERSION. The test above reads
%% the service's own app; relx builds the release out of five, and the three desk
%% apps sat at 0.2.0 through v0.4.0 while the release said 0.4.0. The release
%% guard refuses such a tag before it is signed (mcl-agora#3); this fails
%% sooner, on the eunit run that bumps the release and forgets an app.
every_release_app_carries_the_release_version_test() ->
    {Vsn, Apps} = release(),
    Own = [{App, app_vsn(App)} || App <- Apps, app_vsn(App) =/= not_in_repo],
    %% A check over an empty list passes for the wrong reason, so it is asserted
    %% that the release really named this repository's apps.
    ?assert(length(Own) >= 2),
    ?assertEqual([], [{App, V} || {App, V} <- Own, V =/= Vsn]).

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
read(Name) ->
    {ok, Text} = file:read_file(alongside(Name)),
    Text.

alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).

%% The release tuple and every app it names. The list wraps across lines, so the
%% split is on any whitespace or comma rather than on ", " alone.
release() ->
    {match, [Vsn, List]} =
        re:run(read("rebar.config"),
               "\\{release, \\{mcl_agora, \"([^\"]+)\"\}[,\\s]*\\[([^]]*)\\]",
               [{capture, all_but_first, binary}]),
    {binary_to_list(Vsn),
     [list_to_atom(binary_to_list(App))
      || App <- re:split(List, "[,\\s]+", [{return, binary}, trim]),
         App =/= <<>>]}.

%% An app the release names that lives outside this repository (sasl) has no
%% .app.src here; the release guard skips those for the same reason.
app_vsn(App) ->
    Name = atom_to_list(App),
    case file:read_file(alongside(filename:join(["apps", Name, "src", Name ++ ".app.src"]))) of
        {ok, Text} ->
            {match, [V]} = re:run(Text, "\\{vsn, \"([^\"]+)\"",
                                  [{capture, all_but_first, binary}]),
            binary_to_list(V);
        {error, _} ->
            not_in_repo
    end.
