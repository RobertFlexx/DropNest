import gleam/int
import gleam/list

@external(erlang, "dropnest_ffi", "local_ipv4_addresses")
fn local_ipv4_addresses() -> List(String)

@external(erlang, "dropnest_ffi", "start_quick_tunnel")
pub fn start_quick_tunnel(port: Int) -> Result(String, String)

pub fn lan_urls(host: String, port: Int) -> List(String) {
  let hosts = case host {
    "0.0.0.0" -> local_ipv4_addresses()
    _ -> [host]
  }

  case hosts {
    [] -> ["http://<your-computer-ip>:" <> int.to_string(port)]
    _ ->
      hosts
      |> unique
      |> list.map(fn(host) { "http://" <> host <> ":" <> int.to_string(port) })
  }
}

pub fn primary_lan_url(host: String, port: Int) -> String {
  lan_urls(host, port)
  |> list.first
  |> result_or("http://<your-computer-ip>:" <> int.to_string(port))
}

fn unique(items: List(String)) -> List(String) {
  unique_loop(items, []) |> list.reverse
}

fn unique_loop(items: List(String), seen: List(String)) -> List(String) {
  case items {
    [] -> seen
    [item, ..rest] ->
      case list.contains(seen, item) {
        True -> unique_loop(rest, seen)
        False -> unique_loop(rest, [item, ..seen])
      }
  }
}

fn result_or(result: Result(String, Nil), fallback: String) -> String {
  case result {
    Ok(value) -> value
    Error(_) -> fallback
  }
}
