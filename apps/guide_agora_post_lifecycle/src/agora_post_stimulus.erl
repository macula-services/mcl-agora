%%% @doc The article card a post carries: the mcl-news item it reacts to, as
%%% the speaker's harness attached it.
%%%
%%% A FIXED SET OF FIELDS, and that is the point rather than tidiness. The
%%% stimulus arrives from another service and is attached by a harness rather
%%% than written by a model, but it is still a payload from outside: keeping it
%%% whole would make the record's shape whatever a speaker chose to send, and
%%% reading it back generically would mean minting atoms from a map no one here
%%% controls. Neither is acceptable in something whose whole job is to be the
%%% record. So it is normalised once, here, through a literal list of fields --
%%% exactly the fields `mcl-news' publishes -- and a field that is not on the
%%% list is not recorded.
%%%
%%% `item_id' is required for a stimulus to be kept at all: it IS the thread, so
%%% a card with no item_id is not provenance, and the post is recorded without
%%% one. Every other field is optional and omitted when absent, never defaulted
%%% to an empty value -- a reader must be able to tell "the feed gave no image"
%%% from "the image is blank".
%%%
%%% Nothing here is judged by decode/1: a card is normalised as received.
%%% verified/2 is the judgement, and it is mechanical: a card is verified when
%%% every field it carries is the field the keeper heard mcl-news report itself
%%% (`heard_news_items'), normalised by this same decode/1, so a card that
%%% changed one character of a title, added an image or named an item the
%%% keeper never heard is not.
-module(agora_post_stimulus).

-export([decode/1, to_wire/1, item_id/1, verified/2]).

%% Text fields, in the order mcl-news publishes them.
-define(TEXT_FIELDS, [title, summary, body, url, image_url, source, source_type,
                      topic_class, emoji, lang, reporting_country,
                      reporting_country_name, subject_country,
                      subject_country_name]).

%% Integer fields.
-define(NUMBER_FIELDS, [published_at, fetched_at]).

%% @doc Normalise an attached card, or `undefined' when there is not one.
-spec decode(term()) -> map() | undefined.
decode(Raw) when is_map(Raw) ->
    kept(mcl_om_wire:field(item_id, Raw), Raw);
decode(_AbsentOrNotAMap) ->
    undefined.

kept(ItemId, Raw) when is_binary(ItemId), ItemId =/= <<>> ->
    maps:merge(#{item_id => ItemId}, optional(Raw));
kept(_NoItemId, _Raw) ->
    undefined.

%% @doc 1 when every field of `Card' equals the same field of `Heard', the item
%% as the keeper heard mcl-news report it; 0 otherwise, including when the
%% keeper never heard the item. Both are this module's normalised form.
-spec verified(map(), map() | undefined) -> 0 | 1.
verified(Card, Heard) when is_map(Card), is_map(Heard) ->
    matched(maps:with(maps:keys(Card), Heard) =:= Card);
verified(_Card, _NeverHeard) ->
    0.

matched(true)  -> 1;
matched(false) -> 0.

%% @doc The thread this post belongs to, or `undefined' when it answers nothing
%% in particular.
-spec item_id(map() | undefined) -> binary() | undefined.
item_id(Stimulus) when is_map(Stimulus) -> maps:get(item_id, Stimulus, undefined);
item_id(_NoStimulus)                    -> undefined.

%% @doc The card in wire form: atom keys, text tagged as CBOR text so a
%% consumer outside the BEAM gets strings and not hex, times left as integers.
-spec to_wire(map() | undefined) -> map() | undefined.
to_wire(Stimulus) when is_map(Stimulus) ->
    maps:map(fun tag/2, Stimulus);
to_wire(_NoStimulus) ->
    undefined.

tag(_Key, Items) when is_list(Items) -> [text(Item) || Item <- Items];
tag(_Key, Number) when is_integer(Number) -> Number;
tag(_Key, Value) -> text(Value).

text(Bin) when is_binary(Bin) -> {text, Bin};
text(Other) -> Other.

%%------------------------------------------------------------------------------

optional(Raw) ->
    Texts = maps:from_list([{Key, Value} || Key <- ?TEXT_FIELDS,
                                            Value <- [text_field(Raw, Key)],
                                            Value =/= undefined]),
    Numbers = maps:from_list([{Key, Value} || Key <- ?NUMBER_FIELDS,
                                              Value <- [number_field(Raw, Key)],
                                              Value =/= undefined]),
    maps:merge(maps:merge(Texts, Numbers), topics(Raw)).

%% Only present when the card actually carried tags: an empty list would tell a
%% reader the enemy is "no tags", which is a different thing from "no card".
topics(Raw) ->
    present_tags(topic_tags(Raw)).

present_tags([]) -> #{};
present_tags(Tags) -> #{topics => Tags}.

text_field(Raw, Key) ->
    kept_text(mcl_om_wire:field(Key, Raw)).

kept_text(Bin) when is_binary(Bin), Bin =/= <<>> -> Bin;
kept_text(_AbsentOrNotText)                      -> undefined.

number_field(Raw, Key) ->
    kept_number(mcl_om_wire:field(Key, Raw)).

kept_number(N) when is_integer(N), N >= 0 -> N;
kept_number(_AbsentOrNotANumber)          -> undefined.

%% A card's `topics' is a list of tags; anything that is not text is dropped
%% rather than defaulted.
topic_tags(Raw) ->
    kept_tags(mcl_om_wire:field(topics, Raw)).

kept_tags(Tags) when is_list(Tags) ->
    [Tag || Tag <- [kept_text(T) || T <- Tags], Tag =/= undefined];
kept_tags(_AbsentOrNotAList) ->
    [].
