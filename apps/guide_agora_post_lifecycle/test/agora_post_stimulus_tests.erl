%% @doc The article card: a fixed shape, and no atoms minted from a payload.
-module(agora_post_stimulus_tests).

-include_lib("eunit/include/eunit.hrl").

the_news_fields_are_kept_test() ->
    Card = agora_post_stimulus:decode(card()),
    ?assertEqual(<<"item-1">>, maps:get(item_id, Card)),
    ?assertEqual(<<"A headline">>, maps:get(title, Card)),
    ?assertEqual(<<"https://example.invalid/a">>, maps:get(url, Card)),
    ?assertEqual(<<"france24">>, maps:get(source, Card)),
    ?assertEqual(1759999000000, maps:get(published_at, Card)),
    ?assertEqual([<<"world">>, <<"europe">>], maps:get(topics, Card)).

%% The card comes from another service and is not to be trusted with the
%% record's shape: a field mcl-news does not publish is not recorded.
an_unknown_field_is_not_kept_test() ->
    Card = agora_post_stimulus:decode((card())#{<<"payload">> => {text, <<"junk">>}}),
    ?assertEqual(false, maps:is_key(payload, Card)),
    ?assertEqual(false, maps:is_key(<<"payload">>, Card)).

%% A card with no item_id is not provenance: it would put the post in a thread
%% nobody can name.
a_card_without_an_item_id_is_not_kept_test() ->
    ?assertEqual(undefined, agora_post_stimulus:decode(#{<<"title">> => {text, <<"x">>}})).

%% Absent is not empty. A reader has to be able to tell "the feed gave no
%% image" from "the image is blank", so a field that was not there is not
%% present at all rather than present as an empty string.
an_absent_field_is_omitted_not_emptied_test() ->
    Card = agora_post_stimulus:decode(#{<<"item_id">> => {text, <<"item-1">>}}),
    ?assertEqual(false, maps:is_key(image_url, Card)),
    ?assertEqual(false, maps:is_key(topics, Card)).

a_blank_field_is_dropped_too_test() ->
    Card = agora_post_stimulus:decode((card())#{<<"image_url">> => {text, <<>>}}),
    ?assertEqual(false, maps:is_key(image_url, Card)).

a_negative_time_is_not_a_time_test() ->
    Card = agora_post_stimulus:decode((card())#{<<"published_at">> => -1}),
    ?assertEqual(false, maps:is_key(published_at, Card)).

%% On the wire, text is tagged so a consumer outside the BEAM gets a string
%% rather than a byte dump; times stay integers.
the_wire_form_tags_text_and_leaves_times_alone_test() ->
    Wire = agora_post_stimulus:to_wire(agora_post_stimulus:decode(card())),
    ?assertEqual({text, <<"A headline">>}, maps:get(title, Wire)),
    ?assertEqual(1759999000000, maps:get(published_at, Wire)),
    ?assertEqual([{text, <<"world">>}, {text, <<"europe">>}], maps:get(topics, Wire)).

%% Decoding what the wire form carries gives the record's shape back, which is
%% what makes a replayed projection produce the same row as a live one.
a_card_round_trips_test() ->
    Card = agora_post_stimulus:decode(card()),
    ?assertEqual(Card, agora_post_stimulus:decode(agora_post_stimulus:to_wire(Card))).

no_stimulus_at_all_is_no_stimulus_test() ->
    ?assertEqual(undefined, agora_post_stimulus:decode(undefined)),
    ?assertEqual(undefined, agora_post_stimulus:to_wire(undefined)),
    ?assertEqual(undefined, agora_post_stimulus:item_id(undefined)).

%%------------------------------------------------------------------------------

card() ->
    #{<<"item_id">>      => {text, <<"item-1">>},
      <<"title">>        => {text, <<"A headline">>},
      <<"url">>          => {text, <<"https://example.invalid/a">>},
      <<"source">>       => {text, <<"france24">>},
      <<"published_at">> => 1759999000000,
      <<"topics">>       => [{text, <<"world">>}, {text, <<"europe">>}]}.

%%------------------------------------------------------------------------------
%% verified/2 (W2): a card is real when every field it carries is the field the
%% keeper heard mcl-news report.

-define(HEARD, heard()).
heard() -> #{item_id => <<"i">>, title => <<"T">>, url => <<"https://u">>, published_at => 1}.

a_card_that_is_a_subset_of_what_was_heard_is_verified_test() ->
    ?assertEqual(1, agora_post_stimulus:verified(#{item_id => <<"i">>, title => <<"T">>}, ?HEARD)).

a_card_that_is_exactly_what_was_heard_is_verified_test() ->
    ?assertEqual(1, agora_post_stimulus:verified(?HEARD, ?HEARD)).

a_card_with_a_changed_field_is_not_verified_test() ->
    ?assertEqual(0, agora_post_stimulus:verified(maps:put(title, <<"Other">>, heard()), heard())).

a_card_with_a_field_the_news_never_reported_is_not_verified_test() ->
    ?assertEqual(0, agora_post_stimulus:verified(maps:put(image_url, <<"https://evil">>, heard()), heard())).

a_card_for_an_item_never_heard_is_not_verified_test() ->
    ?assertEqual(0, agora_post_stimulus:verified(?HEARD, undefined)).
