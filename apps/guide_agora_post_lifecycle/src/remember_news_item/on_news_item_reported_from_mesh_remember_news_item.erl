%%% @doc Hears the news wire, so the keeper knows what mcl-news actually said.
%%%
%%% Only an admitted mcl-news node is heard. macula verifies who signed the
%%% fact, not who may publish on the topic, so without the membership check a
%%% stranger could report the item a forged card describes, and the forgery
%%% would verify against itself. A fact from a node the realm says is not
%%% mcl-news, or from one the keeper could not check, is not remembered; the
%%% cost of that is only a card not shown.
%%%
%%% Counted, not logged per fact: a stranger publishing in a loop must not
%%% become the keeper's log volume.
-module(on_news_item_reported_from_mesh_remember_news_item).

-behaviour(macula_subscriber).

-export([init/1, handle_event/4]).

init(_Args) ->
    {ok, #{remembered => 0, not_the_news_sensor => 0, unchecked => 0, refused => 0}}.

-spec handle_event(binary(), term(), map(), map()) -> {noreply, map()}.
handle_event(_Topic, Payload, #{publisher := Publisher, publisher_verified := true}, State)
  when is_map(Payload), is_binary(Publisher), byte_size(Publisher) =:= 32 ->
    {noreply, heard(mcl_om:org_member(agora_post_topic:news_sensor(), Publisher), Payload, State)};
handle_event(_Topic, _Payload, _UnattributedOrNotAMap, State) ->
    {noreply, tally(refused, State)}.

heard({ok, _ExpiresAt}, Payload, State) ->
    remembered(agora_post_stimulus:decode(Payload), State);
heard({error, {not_a_member, _}}, _Payload, State) ->
    tally(not_the_news_sensor, State);
heard({error, {unavailable, _}}, _Payload, State) ->
    tally(unchecked, State).

remembered(undefined, State) ->
    tally(refused, State);
remembered(Item, State) ->
    ok = heard_news_items:remember(agora_post_stimulus:item_id(Item), Item),
    tally(remembered, State).

tally(Key, State) ->
    maps:update_with(Key, fun(N) -> N + 1 end, 1, State).
