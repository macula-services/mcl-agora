%% Status flags for the `agora_post' aggregate. Powers of two, one state per
%% bit, and `evoq_bit_flags' is the only thing that reads or writes them: the
%% aggregate never compares the integer itself, so adding a state later cannot
%% quietly change what an existing one means.
%%
%% W1a sets RECORDED and nothing else. A post is written down once: the first
%% fact under a post_id is the record and every later one is refused by the
%% aggregate with the sanctioned no-op, so a redelivery never produces a second
%% event, a second recorded fact or a second read-model write.
%%
%% W2 adds its own bit for a post the keeper heard twice with two different
%% bodies. It is deliberately not reserved here: a flag nothing sets is a flag
%% nothing tests.
-define(AGORA_POST_RECORDED, 1).
