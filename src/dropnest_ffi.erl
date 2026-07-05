-module(dropnest_ffi).
-export([local_ipv4_addresses/0]).

local_ipv4_addresses() ->
  case inet:getifaddrs() of
    {ok, Interfaces} ->
      Addresses = lists:flatmap(fun addresses_for_interface/1, Interfaces),
      unique(Addresses);
    _ ->
      []
  end.

addresses_for_interface({_Name, Options}) ->
  Flags = proplists:get_value(flags, Options, []),
  case lists:member(loopback, Flags) of
    true -> [];
    false ->
      [format_ipv4(Address) || {addr, Address} <- Options, usable_ipv4(Address)]
  end.

usable_ipv4({127, _, _, _}) -> false;
usable_ipv4({169, 254, _, _}) -> false;
usable_ipv4({A, B, C, D})
  when is_integer(A), is_integer(B), is_integer(C), is_integer(D) -> true;
usable_ipv4(_) -> false.

format_ipv4({A, B, C, D}) ->
  list_to_binary(
    integer_to_list(A) ++ "." ++
    integer_to_list(B) ++ "." ++
    integer_to_list(C) ++ "." ++
    integer_to_list(D)
  ).

unique(Items) ->
  lists:reverse(unique(Items, [])).

unique([], Seen) -> Seen;
unique([Item | Rest], Seen) ->
  case lists:member(Item, Seen) of
    true -> unique(Rest, Seen);
    false -> unique(Rest, [Item | Seen])
  end.
