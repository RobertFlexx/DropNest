-module(dropnest_ffi).
-export([
  local_ipv4_addresses/0,
  sha256_text/1,
  sha256_file/1,
  hmac_sha256/2,
  secure_equals/2,
  make_private/2,
  start_quick_tunnel/1,
  claim_invite/3,
  rate_limit/3,
  init_security_state/0,
  prune_rate_limits/1,
  storage_transaction/1,
  sanitize_filename/1
]).

sha256_text(Value) ->
  hex(crypto:hash(sha256, Value)).

sha256_file(Path) ->
  case file:open(Path, [read, binary, raw]) of
    {ok, File} ->
      try
        {ok, hex(hash_file(File, crypto:hash_init(sha256)))}
      catch
        _:_ -> {error, nil}
      after
        file:close(File)
      end;
    {error, _} ->
      {error, nil}
  end.

hash_file(File, Context) ->
  case file:read(File, 1024 * 1024) of
    {ok, Chunk} -> hash_file(File, crypto:hash_update(Context, Chunk));
    eof -> crypto:hash_final(Context);
    {error, Reason} -> error(Reason)
  end.

hmac_sha256(Key, Value) ->
  hex(crypto:mac(hmac, sha256, Key, Value)).

secure_equals(Left, Right) when byte_size(Left) =:= byte_size(Right) ->
  secure_equals(Left, Right, 0) =:= 0;
secure_equals(_, _) ->
  false.

secure_equals(<<>>, <<>>, Difference) -> Difference;
secure_equals(<<Left, LeftRest/binary>>, <<Right, RightRest/binary>>, Difference) ->
  secure_equals(LeftRest, RightRest, Difference bor (Left bxor Right)).

make_private(Path, IsDirectory) ->
  Mode = case IsDirectory of true -> 8#700; false -> 8#600 end,
  _ = file:change_mode(Path, Mode),
  nil.

hex(Binary) ->
  << <<(hex_digit(Byte bsr 4)), (hex_digit(Byte band 16#0f))>> || <<Byte>> <= Binary >>.

hex_digit(Value) when Value < 10 -> $0 + Value;
hex_digit(Value) -> $a + Value - 10.

start_quick_tunnel(HttpPort) ->
  case os:find_executable("cloudflared") of
    false ->
      {error, <<"cloudflared was not found. Install it, then run DropNest again.">>};
    Executable ->
      Parent = self(),
      Worker = spawn(fun() -> quick_tunnel_worker(Parent, Executable, HttpPort) end),
      receive
        {Worker, Result} -> Result
      after 30000 ->
        exit(Worker, kill),
        {error, <<"Timed out while waiting for the temporary tunnel URL.">>}
      end
  end.

quick_tunnel_worker(Parent, Executable, HttpPort) ->
  Origin = "http://127.0.0.1:" ++ integer_to_list(HttpPort),
  try open_port(
    {spawn_executable, Executable},
    [binary, exit_status, stderr_to_stdout,
      {args, ["tunnel", "--url", Origin, "--no-autoupdate"]}]
  ) of
    TunnelPort ->
      ParentMonitor = erlang:monitor(process, Parent),
      collect_tunnel_output(Parent, ParentMonitor, TunnelPort, <<>>, false)
  catch
    _:_ -> Parent ! {self(), {error, <<"Could not start cloudflared.">>}}
  end.

collect_tunnel_output(Parent, ParentMonitor, TunnelPort, Output, Announced) ->
  receive
    {TunnelPort, {data, Chunk}} ->
      Combined = <<Output/binary, Chunk/binary>>,
      case {Announced, tunnel_url(Combined)} of
        {false, {ok, Url}} ->
          Parent ! {self(), {ok, Url}},
          collect_tunnel_output(Parent, ParentMonitor, TunnelPort, <<>>, true);
        _ ->
          Kept = keep_output_tail(Combined),
          collect_tunnel_output(Parent, ParentMonitor, TunnelPort, Kept, Announced)
      end;
    {TunnelPort, {exit_status, Status}} ->
      case Announced of
        true ->
          io:format(
            standard_error,
            "DropNest warning: the temporary public tunnel stopped (status ~B). Local and LAN access are still available.~n",
            [Status]
          );
        false ->
          Message = iolist_to_binary(
            io_lib:format("cloudflared exited before creating a link (status ~B).", [Status])
          ),
          Parent ! {self(), {error, Message}}
      end;
    {'DOWN', ParentMonitor, process, Parent, _} ->
      port_close(TunnelPort)
  end.

tunnel_url(Output) ->
  case re:run(
    Output,
    <<"https://[a-z0-9-]+\\.trycloudflare\\.com">>,
    [{capture, first, binary}]
  ) of
    {match, [Url]} -> {ok, Url};
    nomatch -> error
  end.

keep_output_tail(Output) when byte_size(Output) =< 16384 -> Output;
keep_output_tail(Output) ->
  binary:part(Output, byte_size(Output) - 16384, 16384).

claim_invite(Invite, Device, Limit) ->
  retry_transaction(
    {{dropnest_invite_claim, Invite}, self()},
    fun() -> claim_invite_locked(Invite, Device, Limit) end
  ).

claim_invite_locked(Invite, Device, Limit) ->
  Table = ensure_invite_table(),
  Key = {Invite, Device},
  case ets:member(Table, Key) of
    true -> true;
    false ->
      Match = ets:match_object(Table, {{Invite, '_'}, true}),
      case length(Match) < Limit of
        true -> ets:insert(Table, {Key, true}), true;
        false -> false
      end
  end.

ensure_invite_table() ->
  case ets:whereis(dropnest_invite_claims) of
    undefined ->
      try ets:new(dropnest_invite_claims, [named_table, public, set])
      catch error:badarg -> dropnest_invite_claims
      end;
    Table -> Table
  end.

init_security_state() ->
  _ = ensure_named_table(dropnest_invite_claims),
  _ = ensure_named_table(dropnest_rate_limits),
  nil.

rate_limit(Key, Limit, WindowSeconds) ->
  retry_transaction(
    {{dropnest_rate_limit, Key}, self()},
    fun() -> rate_limit_locked(Key, Limit, WindowSeconds) end
  ).

rate_limit_locked(Key, Limit, WindowSeconds) ->
  Table = ensure_named_table(dropnest_rate_limits),
  Now = erlang:monotonic_time(second),
  case ets:lookup(Table, Key) of
    [{Key, Started, Count}]
      when Now - Started < WindowSeconds, Count >= Limit -> false;
    [{Key, Started, Count}]
      when Now - Started < WindowSeconds ->
        ets:insert(Table, {Key, Started, Count + 1}),
        true;
    _ ->
      case ets:info(Table, size) < 10000 of
        true ->
          ets:insert(Table, {Key, Now, 1}),
          true;
        false -> false
      end
  end.

prune_rate_limits(MaxAgeSeconds) ->
  Table = ensure_named_table(dropnest_rate_limits),
  Now = erlang:monotonic_time(second),
  _ = ets:foldl(
    fun({Key, Started, _Count}, nil) ->
      case Now - Started >= MaxAgeSeconds of
        true -> ets:delete(Table, Key);
        false -> ok
      end,
      nil
    end,
    nil,
    Table
  ),
  nil.

ensure_named_table(Name) ->
  case ets:whereis(Name) of
    undefined ->
      try ets:new(Name, [named_table, public, set])
      catch error:badarg -> Name
      end;
    Table -> Table
  end.

storage_transaction(Fun) ->
  retry_transaction({{dropnest_storage, node()}, self()}, Fun).

retry_transaction(Lock, Fun) ->
  case global:trans(Lock, Fun) of
    aborted ->
      timer:sleep(5),
      retry_transaction(Lock, Fun);
    Value -> Value
  end.

sanitize_filename(Value) ->
  << <<(safe_filename_byte(Byte))>> || <<Byte>> <= Value >>.

safe_filename_byte(Byte) when Byte < 32 -> $\s;
safe_filename_byte(127) -> $\s;
safe_filename_byte($/) -> $_;
safe_filename_byte($\\) -> $_;
safe_filename_byte($\") -> $';
safe_filename_byte(Byte) -> Byte.

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
