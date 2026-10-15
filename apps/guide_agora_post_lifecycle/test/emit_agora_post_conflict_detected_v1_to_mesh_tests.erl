%% @doc The contradiction fact: hashes and publishers, never the refused body.
-module(emit_agora_post_conflict_detected_v1_to_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

the_fact_names_both_bodies_by_hash_only_test() ->
    Fact = emit_agora_post_conflict_detected_v1_to_mesh:to_wire(
             #{post_id => <<"p">>, kept_body_sha256 => <<"aa">>, kept_publisher => <<1:256>>,
               refused_body_sha256 => <<"bb">>, refused_publisher => <<2:256>>,
               refused_from => <<"a mind">>, detected_at => 5}),
    ?assertEqual(#{post_id => {text, <<"p">>},
                   kept_body_sha256 => {text, <<"aa">>},
                   kept_publisher => {text, binary:encode_hex(<<1:256>>, lowercase)},
                   refused_body_sha256 => {text, <<"bb">>},
                   refused_publisher => {text, binary:encode_hex(<<2:256>>, lowercase)},
                   refused_from => {text, <<"a mind">>},
                   detected_at => 5}, Fact).

%% A replayed envelope (binary keys) gives the same fact.
the_fact_reads_a_stored_envelope_too_test() ->
    Fact = emit_agora_post_conflict_detected_v1_to_mesh:to_wire(
             #{<<"post_id">> => <<"p">>, <<"kept_body_sha256">> => <<"aa">>,
               <<"refused_body_sha256">> => <<"bb">>, <<"refused_publisher">> => <<2:256>>,
               <<"refused_from">> => <<"m">>, <<"detected_at">> => 5}),
    ?assertMatch(#{post_id := {text, <<"p">>}, refused_body_sha256 := {text, <<"bb">>}}, Fact),
    ?assertNot(maps:is_key(kept_publisher, Fact)).
