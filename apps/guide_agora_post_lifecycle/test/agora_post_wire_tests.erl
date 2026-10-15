%% @doc The record's outbound shape: what leaves this service, and what does
%% not.
-module(agora_post_wire_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PUBLISHER, binary:copy(<<16#ab>>, 32)).

a_row_goes_out_with_text_tagged_test() ->
    Wire = agora_post_wire:to_wire(row()),
    ?assertEqual({text, <<"a mind">>}, maps:get(from, Wire)),
    ?assertEqual({text, <<"something worth keeping">>}, maps:get(body, Wire)),
    ?assertEqual({text, <<"opening">>}, maps:get(kind, Wire)).

times_stay_integers_test() ->
    Wire = agora_post_wire:to_wire(row()),
    ?assertEqual(1760000000000, maps:get(posted_at, Wire)),
    ?assertEqual(1760000000001, maps:get(recorded_at, Wire)).

%% A node id is bytes and is published in hex, so a reader can match it against
%% an id it already holds instead of receiving a byte dump.
a_publisher_goes_out_as_hex_test() ->
    Wire = agora_post_wire:to_wire(row()),
    ?assertEqual({text, binary:copy(<<"ab">>, 32)}, maps:get(publisher, Wire)).

%% Absent is omitted, never sent as null: a reader has to be able to tell
%% "there was no reply" from "it replied to nothing".
an_absent_field_is_omitted_test() ->
    Wire = agora_post_wire:to_wire(maps:remove(in_reply_to, maps:remove(stimulus, row()))),
    ?assertEqual(false, maps:is_key(in_reply_to, Wire)),
    ?assertEqual(false, maps:is_key(stimulus, Wire)).

an_empty_field_is_omitted_too_test() ->
    Wire = agora_post_wire:to_wire((row())#{in_reply_to => <<>>, kind => <<>>}),
    ?assertEqual(false, maps:is_key(in_reply_to, Wire)),
    ?assertEqual(false, maps:is_key(kind, Wire)).

a_rule_publisher_is_omitted_rather_than_mangled_test() ->
    Wire = agora_post_wire:to_wire((row())#{publisher => <<"short">>}),
    ?assertEqual(false, maps:is_key(publisher, Wire)).

the_card_goes_out_with_the_post_test() ->
    Wire = agora_post_wire:to_wire(row()),
    Card = maps:get(stimulus, Wire),
    ?assertEqual({text, <<"item-1">>}, maps:get(item_id, Card)).

%%------------------------------------------------------------------------------

row() ->
    #{post_id     => <<"abcdef0123456789abcdef0123456789">>,
      from        => <<"a mind">>,
      publisher   => ?PUBLISHER,
      body        => <<"something worth keeping">>,
      in_reply_to => <<"0123456789abcdef0123456789abcdef">>,
      item_id     => <<"item-1">>,
      kind        => <<"opening">>,
      posted_at   => 1760000000000,
      recorded_at => 1760000000001,
      stimulus    => #{item_id => <<"item-1">>, title => <<"A headline">>}}.
