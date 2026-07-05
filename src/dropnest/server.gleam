import dropnest/config as app_config
import dropnest/drop
import dropnest/net
import dropnest/storage
import dropnest/view
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import mist
import wisp
import wisp/wisp_mist

pub fn start(config: app_config.Config) -> Nil {
  case storage.setup(config) {
    Ok(_) -> Nil
    Error(storage.StorageError(message: message)) -> {
      io.println("DropNest could not start: " <> message)
      process.sleep_forever()
    }
  }

  let _ = storage.clean_expired(config)
  let _ = process.spawn_unlinked(fn() { cleanup_loop(config) })
  print_banner(config)

  let secret_key_base = wisp.random_string(64)
  let handler = fn(request) { handle_request(request, config) }

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.bind(app_config.bind_address(config))
    |> mist.port(config.port)
    |> mist.start

  process.sleep_forever()
}

fn handle_request(
  request: wisp.Request,
  config: app_config.Config,
) -> wisp.Response {
  let _ = storage.clean_expired(config)

  let request =
    request
    |> wisp.set_max_body_size(config.max_upload_bytes)
    |> wisp.set_max_files_size(config.max_upload_bytes)

  use <- wisp.rescue_crashes
  use <- wisp.log_request(request)
  use request <- wisp.handle_head(request)

  case locked(request, config) {
    True -> locked_response(request)
    False -> route(request, config)
  }
}

fn route(request: wisp.Request, config: app_config.Config) -> wisp.Response {
  case request.method, wisp.path_segments(request) {
    Get, [] -> wisp.html_response(view.home(config, storage.all(config)), 200)

    Get, ["health"] ->
      wisp.response(200)
      |> wisp.set_header("content-type", "text/plain; charset=utf-8")
      |> wisp.string_body("ok\n")

    Get, ["drops"] ->
      storage.all(config)
      |> drop.encode_all
      |> wisp.json_response(200)

    Post, ["unlock"] -> unlock(request, config)
    Post, ["drops", "text"] -> create_text(request, config)
    Post, ["drops", "file"] -> create_file(request, config)
    Get, ["drops", id, "download"] -> download(id, config)
    Post, ["drops", id, "delete"] -> {
      let _ = storage.delete(config, id)
      wisp.redirect(to: "/")
    }
    _, _ ->
      wisp.html_response(
        view.message("Not found", "That DropNest page does not exist."),
        404,
      )
  }
}

fn create_text(
  request: wisp.Request,
  config: app_config.Config,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  let content = form_value(form.values, "content") |> result.unwrap("")
  let expires = expiration_value(form.values, config)
  case storage.add_text_with_expiration(config, content, expires) {
    Ok(_) -> wisp.redirect(to: "/")
    Error(storage.StorageError(message: message)) ->
      wisp.html_response(view.message("Text drop failed", message), 400)
  }
}

fn create_file(
  request: wisp.Request,
  config: app_config.Config,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  let expires = expiration_value(form.values, config)
  case form_file(form.files, "file") {
    Ok(wisp.UploadedFile(file_name: file_name, path: path)) -> {
      case storage.add_file_with_expiration(config, path, file_name, expires) {
        Ok(_) -> wisp.redirect(to: "/")
        Error(storage.StorageError(message: message)) ->
          wisp.html_response(view.message("Upload failed", message), 400)
      }
    }
    Error(_) ->
      wisp.html_response(
        view.message("Upload failed", "Choose a non-empty file and try again."),
        400,
      )
  }
}

fn download(id: String, config: app_config.Config) -> wisp.Response {
  case storage.valid_id(id), storage.find(config, id) {
    True, Ok(item) -> {
      case item.kind, item.original_filename {
        drop.File, Some(name) ->
          wisp.response(200)
          |> wisp.file_download(
            named: storage.safe_title(name),
            from: storage.drop_path(config, id),
          )
        _, _ ->
          wisp.html_response(
            view.message("Missing file", "That file is no longer available."),
            404,
          )
      }
    }
    _, _ ->
      wisp.html_response(
        view.message("Missing drop", "That drop was not found."),
        404,
      )
  }
}

fn unlock(request: wisp.Request, config: app_config.Config) -> wisp.Response {
  use form <- wisp.require_form(request)
  let submitted = form_value(form.values, "pin") |> result.unwrap("")
  case config.pin {
    Some(pin) if submitted == pin ->
      wisp.redirect(to: "/")
      |> wisp.set_header(
        "set-cookie",
        "dropnest_pin=" <> pin <> "; Path=/; Max-Age=43200; SameSite=Strict",
      )
    _ -> wisp.html_response(view.unlock(), 403)
  }
}

fn locked(request: wisp.Request, config: app_config.Config) -> Bool {
  case config.pin, wisp.path_segments(request) {
    None, _ -> False
    Some(_), ["health"] -> False
    Some(_), ["unlock"] -> False
    Some(pin), _ -> {
      cookie_value(request, "dropnest_pin") != Ok(pin)
    }
  }
}

fn locked_response(request: wisp.Request) -> wisp.Response {
  case request.method {
    Get -> wisp.html_response(view.unlock(), 200)
    _ -> wisp.redirect(to: "/")
  }
}

fn form_value(
  values: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  values
  |> list.find(fn(pair) { pair.0 == name })
  |> result.map(fn(pair) { pair.1 })
}

fn form_file(
  files: List(#(String, wisp.UploadedFile)),
  name: String,
) -> Result(wisp.UploadedFile, Nil) {
  files
  |> list.find(fn(pair) { pair.0 == name })
  |> result.map(fn(pair) { pair.1 })
}

fn expiration_value(
  values: List(#(String, String)),
  config: app_config.Config,
) -> Int {
  case form_value(values, "expires") {
    Ok(value) ->
      case int.parse(value) {
        Ok(minutes) if minutes >= 0 -> minutes
        _ -> config.default_expiration_minutes
      }
    Error(_) -> config.default_expiration_minutes
  }
}

fn cookie_value(req: wisp.Request, name: String) -> Result(String, Nil) {
  use cookie <- result.try(request.get_header(req, "cookie"))
  cookie
  |> string.split(on: ";")
  |> list.map(string.trim)
  |> list.find(fn(pair) { string.starts_with(pair, name <> "=") })
  |> result.map(fn(pair) {
    string.drop_start(pair, up_to: string.length(name) + 1)
  })
}

fn cleanup_loop(config: app_config.Config) -> Nil {
  process.sleep(60 * 1000)
  let _ = storage.clean_expired(config)
  cleanup_loop(config)
}

fn print_banner(config: app_config.Config) -> Nil {
  case config.lan {
    True -> io.println("\nDropNest is running in LAN mode.\n")
    False -> io.println("\nDropNest is running.\n")
  }

  io.println("Local:")
  io.println("  http://localhost:" <> int.to_string(config.port))

  case config.lan {
    True -> {
      io.println("\nOn your Wi-Fi:")
      net.lan_urls(config.host, config.port)
      |> list.each(fn(url) { io.println("  " <> url) })
      io.println("\nReceive directory:")
      io.println("  " <> config.receive_dir)
      io.println("\nPIN protection:")
      case config.pin {
        Some(_) -> io.println("  enabled")
        None -> io.println("  disabled")
      }
      io.println("\nWarning:")
      io.println(
        "  LAN mode allows other devices on your network to reach DropNest.",
      )
      io.println(
        "  If more than one address is shown, use the one on the same Wi-Fi as your other device.",
      )
    }
    False -> {
      io.println("\nReceive directory:")
      io.println("  " <> config.receive_dir)
      io.println("\nTip:")
      io.println(
        "  Use --lan to open DropNest from another device on your Wi-Fi.",
      )
    }
  }

  io.println("")
}
