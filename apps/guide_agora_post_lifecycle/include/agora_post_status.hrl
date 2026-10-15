%% Status flags for the `agora_post' aggregate. Powers of two, one state per
%% bit, and `evoq_bit_flags' is the only thing that reads or writes them: the
%% aggregate never compares the integer itself, so adding a state later cannot
%% quietly change what an existing one means.
%%
%% RECORDED is set by the first fact under a post_id: that fact is the record.
%% A later fact with the same body is a redelivery, refused with the sanctioned
%% no-op. A later fact with a DIFFERENT body sets CONFLICTED: two things claim
%% to be one post, the first stays on the record, and the conflict is itself
%% written down and said out loud (agora_post_conflict_detected_v1).
-define(AGORA_POST_RECORDED, 1).
-define(AGORA_POST_CONFLICTED, 2).
