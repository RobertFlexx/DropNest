import dropnest/config as app_config
import dropnest/drop
import dropnest/net
import dropnest/security
import dropnest/storage
import dropnest/view
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mist
import wisp
import wisp/wisp_mist

type Runtime {
  Runtime(
    config: app_config.Config,
    secret: String,
    csrf_token: String,
    pin_digest: Option(String),
    session_token: Option(String),
  )
}

pub fn start(config: app_config.Config) -> Nil {
  case app_config.validate_security(config) {
    Ok(_) -> Nil
    Error(message) -> {
      io.println("DropNest refused to start: " <> message)
      io.println("Run `dropnest help` for secure sharing examples.")
      process.sleep_forever()
    }
  }

  case storage.setup(config) {
    Ok(_) -> Nil
    Error(storage.StorageError(message: message)) -> {
      io.println("DropNest could not start: " <> message)
      process.sleep_forever()
    }
  }

  let config = prepare_tunnel(config)

  security.setup()
  let secret = wisp.random_string(64)
  case config.tunnel {
    True -> activate_new_invite(secret)
    False -> security.clear_active_invite()
  }
  let runtime =
    Runtime(
      config:,
      secret:,
      csrf_token: wisp.random_string(48),
      pin_digest: digest_pin(config.pin, secret),
      session_token: digest_session(config.pin, secret),
    )

  let _ = storage.clean_expired(config)
  let _ = process.spawn_unlinked(fn() { cleanup_loop(config) })
  print_banner(config)

  let handler = fn(request) { handle_request(request, runtime) }
  let wisp_handler = wisp_mist.handler(handler, secret)
  let handler = fn(request: request.Request(mist.Connection)) {
    let loopback = case mist.get_connection_info(request.body) {
      Ok(mist.ConnectionInfo(_, mist.IpV4(127, _, _, _))) -> "1"
      Ok(mist.ConnectionInfo(_, mist.IpV6(0, 0, 0, 0, 0, 0, 0, 1))) -> "1"
      _ -> "0"
    }
    request
    |> request.set_header("x-dropnest-loopback-peer", loopback)
    |> wisp_handler
  }
  case
    handler
    |> mist.new
    |> mist.bind(app_config.bind_address(config))
    |> mist.port(config.port)
    |> mist.start
  {
    Ok(_) -> process.sleep_forever()
    Error(_) -> {
      io.println(
        "DropNest could not open port "
        <> int.to_string(config.port)
        <> ". It may already be in use or blocked by the operating system.",
      )
      process.sleep_forever()
    }
  }
}

fn handle_request(request: wisp.Request, runtime: Runtime) -> wisp.Response {
  let config = runtime.config
  let nonce = wisp.random_string(24)

  let request =
    request
    |> wisp.set_max_body_size(config.max_upload_bytes + 1_048_576)
    |> wisp.set_max_files_size(config.max_upload_bytes)

  use <- wisp.rescue_crashes
  use <- wisp.log_request(request)
  use request <- wisp.handle_head(request)

  let response = case request_allowed(request, runtime) {
    False -> rate_limit_response(nonce)
    True ->
      case cross_site_post(request) {
        True ->
          wisp.html_response(
            view.message(
              "Request blocked",
              "DropNest rejected a cross-site request.",
              nonce,
            ),
            403,
          )
        False ->
          case locked(request, runtime) {
            True -> locked_response(request, runtime.csrf_token, nonce)
            False -> route(request, runtime, nonce)
          }
      }
  }

  security_headers(response, nonce, config)
}

fn route(
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  let config = runtime.config
  case request.method, wisp.path_segments(request) {
    Get, [] ->
      wisp.html_response(
        view.home(
          config,
          storage.all(config),
          runtime.csrf_token,
          nonce,
          invite_url(runtime),
          local_admin_request(request),
        ),
        200,
      )

    Get, ["i", token] -> accept_invite(token, request, runtime, nonce)

    Get, ["health"] ->
      wisp.response(200)
      |> wisp.set_header("content-type", "text/plain; charset=utf-8")
      |> wisp.string_body("ok\n")

    Post, ["unlock"] -> unlock(request, runtime, nonce)
    Post, ["logout"] -> logout(request, runtime, nonce)
    Post, ["invite", "regenerate"] -> regenerate_invite(request, runtime, nonce)
    Post, ["drops", "text"] -> create_text(request, runtime, nonce)
    Post, ["drops", "file"] -> create_file(request, runtime, nonce)
    Get, ["drops", id, "download"] -> download(id, config, nonce)
    Post, ["drops", id, "delete"] -> delete(request, id, runtime, nonce)
    _, _ ->
      wisp.html_response(
        view.message("Not found", "That DropNest page does not exist.", nonce),
        404,
      )
  }
}

fn create_text(
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  case valid_csrf(form.values, runtime.csrf_token) {
    False -> csrf_error(nonce)
    True -> {
      let content = form_value(form.values, "content") |> result.unwrap("")
      let expires = expiration_value(form.values, runtime.config)
      case storage.add_text_with_expiration(runtime.config, content, expires) {
        Ok(_) -> wisp.redirect(to: "/")
        Error(storage.StorageError(message: message)) ->
          wisp.html_response(
            view.message("Text drop failed", message, nonce),
            400,
          )
      }
    }
  }
}

fn create_file(
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  case valid_csrf(form.values, runtime.csrf_token) {
    False -> csrf_error(nonce)
    True -> {
      let expires = expiration_value(form.values, runtime.config)
      case form_file(form.files, "file") {
        Ok(wisp.UploadedFile(file_name: file_name, path: path)) ->
          case
            storage.add_file_with_expiration(
              runtime.config,
              path,
              file_name,
              expires,
            )
          {
            Ok(_) -> wisp.redirect(to: "/")
            Error(storage.StorageError(message: message)) ->
              wisp.html_response(
                view.message("Upload failed", message, nonce),
                400,
              )
          }
        Error(_) ->
          wisp.html_response(
            view.message(
              "Upload failed",
              "Choose a non-empty file and try again.",
              nonce,
            ),
            400,
          )
      }
    }
  }
}

fn delete(
  request: wisp.Request,
  id: String,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  case valid_csrf(form.values, runtime.csrf_token), storage.valid_id(id) {
    False, _ -> csrf_error(nonce)
    _, False ->
      wisp.html_response(
        view.message("Not found", "Invalid drop ID.", nonce),
        404,
      )
    True, True -> {
      let _ = storage.delete(runtime.config, id)
      wisp.redirect(to: "/")
    }
  }
}

fn download(
  id: String,
  config: app_config.Config,
  nonce: String,
) -> wisp.Response {
  case storage.valid_id(id), storage.find(config, id) {
    True, Ok(item) ->
      case
        item.kind,
        item.original_filename,
        storage.file_is_intact(config, item)
      {
        drop.File, Some(name), True ->
          wisp.response(200)
          |> wisp.file_download(
            named: storage.safe_title(name),
            from: storage.drop_path(config, id),
          )
        drop.File, Some(_), False ->
          wisp.html_response(
            view.message(
              "Integrity check failed",
              "The stored file no longer matches its SHA-256 checksum, so DropNest refused to send it.",
              nonce,
            ),
            409,
          )
        _, _, _ ->
          wisp.html_response(
            view.message(
              "Missing file",
              "That file is no longer available.",
              nonce,
            ),
            404,
          )
      }
    _, _ ->
      wisp.html_response(
        view.message("Missing drop", "That drop was not found.", nonce),
        404,
      )
  }
}

fn unlock(
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  case valid_csrf(form.values, runtime.csrf_token) {
    False -> csrf_error(nonce)
    True -> {
      let submitted = form_value(form.values, "pin") |> result.unwrap("")
      let submitted_digest =
        security.hmac_sha256(runtime.secret, "dropnest-pin:" <> submitted)
      case runtime.pin_digest, browser_session(runtime, request) {
        Some(expected), Some(session) ->
          case security.secure_equals(submitted_digest, expected) {
            True ->
              wisp.redirect(to: "/")
              |> wisp.set_header(
                "set-cookie",
                "dropnest_session="
                  <> session
                  <> "; Path=/; Max-Age=43200; HttpOnly; SameSite=Strict"
                  <> secure_cookie_suffix(request),
              )
            False -> invalid_unlock(runtime.csrf_token, nonce)
          }
        _, _ -> invalid_unlock(runtime.csrf_token, nonce)
      }
    }
  }
}

fn invalid_unlock(csrf_token: String, nonce: String) -> wisp.Response {
  process.sleep(350)
  wisp.html_response(view.unlock(csrf_token, nonce, True), 403)
}

fn logout(
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  case valid_csrf(form.values, runtime.csrf_token) {
    False -> csrf_error(nonce)
    True ->
      wisp.redirect(to: "/")
      |> wisp.set_header(
        "set-cookie",
        "dropnest_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"
          <> secure_cookie_suffix(request),
      )
  }
}

fn locked(request: wisp.Request, runtime: Runtime) -> Bool {
  case runtime.session_token, wisp.path_segments(request) {
    None, _ -> False
    Some(_), ["health"] -> False
    Some(_), ["unlock"] -> False
    Some(_), ["i", _] -> False
    Some(_), _ ->
      case browser_session(runtime, request) {
        Some(expected) ->
          case cookie_value(request, "dropnest_session") {
            Ok(actual) -> !security.secure_equals(actual, expected)
            Error(_) -> True
          }
        None -> True
      }
  }
}

fn accept_invite(
  token: String,
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  let supplied =
    security.hmac_sha256(runtime.secret, "dropnest-invite:" <> token)
  accept_active_invite(supplied, request, runtime, nonce)
}

fn accept_active_invite(
  supplied: String,
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  case browser_session(runtime, request) {
    Some(session) -> {
      let fingerprint = client_fingerprint(request, runtime.secret)
      case
        security.claim_active_invite(
          supplied,
          fingerprint,
          storage.now_seconds(),
          2,
        )
      {
        security.InviteAccepted ->
          wisp.redirect(to: "/")
          |> wisp.set_header(
            "set-cookie",
            "dropnest_session="
              <> session
              <> "; Path=/; Max-Age=43200; HttpOnly; SameSite=Strict"
              <> secure_cookie_suffix(request),
          )
        security.InviteExpired ->
          wisp.html_response(
            view.message(
              "Friend link expired",
              "This 15-minute invite has expired. Ask the host to regenerate the friend link from localhost.",
              nonce,
            ),
            410,
          )
        security.InviteFull ->
          wisp.html_response(
            view.message(
              "Friend link already used",
              "This temporary link has already granted access to two browsers. Ask the host to regenerate it from localhost.",
              nonce,
            ),
            410,
          )
        security.InviteInvalid -> invalid_invite(nonce)
        security.InviteUnavailable -> invalid_invite(nonce)
      }
    }
    None -> invalid_invite(nonce)
  }
}

fn regenerate_invite(
  request: wisp.Request,
  runtime: Runtime,
  nonce: String,
) -> wisp.Response {
  use form <- wisp.require_form(request)
  case
    valid_csrf(form.values, runtime.csrf_token),
    runtime.config.tunnel,
    local_admin_request(request)
  {
    False, _, _ -> csrf_error(nonce)
    _, False, _ -> invalid_invite(nonce)
    _, _, False ->
      wisp.html_response(
        view.message(
          "Host action only",
          "Open DropNest through localhost on the computer running it to regenerate the friend link.",
          nonce,
        ),
        403,
      )
    True, True, True -> {
      activate_new_invite(runtime.secret)
      wisp.redirect(to: "/#friend-link")
    }
  }
}

fn request_allowed(request: wisp.Request, runtime: Runtime) -> Bool {
  let fingerprint = client_fingerprint(request, runtime.secret)
  case request.method, wisp.path_segments(request) {
    Post, ["unlock"] -> security.rate_limit("unlock:" <> fingerprint, 5, 5 * 60)
    Get, ["i", _] -> security.rate_limit("invite:" <> fingerprint, 20, 15 * 60)
    Post, ["invite", "regenerate"] ->
      security.rate_limit("regenerate:" <> fingerprint, 12, 60 * 60)
    Post, ["drops", "file"] ->
      security.rate_limit("file:" <> fingerprint, 20, 10 * 60)
    Post, ["drops", "text"] ->
      security.rate_limit("text:" <> fingerprint, 60, 10 * 60)
    Get, ["drops", _, "download"] ->
      security.rate_limit("download:" <> fingerprint, 60, 10 * 60)
    Post, _ -> security.rate_limit("write:" <> fingerprint, 120, 60)
    _, _ -> True
  }
}

fn rate_limit_response(nonce: String) -> wisp.Response {
  wisp.html_response(
    view.message(
      "Slow down",
      "Too many requests came from this visitor. Wait a few minutes and try again.",
      nonce,
    ),
    429,
  )
  |> wisp.set_header("retry-after", "300")
}

fn client_fingerprint(request: wisp.Request, secret: String) -> String {
  let address =
    first_header(request, ["cf-connecting-ip", "x-real-ip", "x-forwarded-for"])
  let traits =
    address
    <> "\n"
    <> header_or_empty(request, "user-agent")
    <> "\n"
    <> header_or_empty(request, "accept-language")
    <> "\n"
    <> header_or_empty(request, "accept-encoding")
  security.hmac_sha256(secret, "dropnest-visitor:" <> traits)
}

fn first_header(request: wisp.Request, names: List(String)) -> String {
  case names {
    [] -> "local-or-unknown"
    [name, ..rest] ->
      case request.get_header(request, name) {
        Ok(value) -> string.slice(value, at_index: 0, length: 256)
        Error(_) -> first_header(request, rest)
      }
  }
}

fn header_or_empty(request: wisp.Request, name: String) -> String {
  request.get_header(request, name)
  |> result.unwrap("")
  |> string.slice(at_index: 0, length: 512)
}

fn invalid_invite(nonce: String) -> wisp.Response {
  wisp.html_response(
    view.message(
      "Invalid friend link",
      "This temporary DropNest link is not valid.",
      nonce,
    ),
    404,
  )
}

fn locked_response(
  request: wisp.Request,
  csrf_token: String,
  nonce: String,
) -> wisp.Response {
  case request.method {
    Get -> wisp.html_response(view.unlock(csrf_token, nonce, False), 200)
    _ -> wisp.redirect(to: "/")
  }
}

fn csrf_error(nonce: String) -> wisp.Response {
  wisp.html_response(
    view.message(
      "Request expired",
      "Refresh the page and try that action again.",
      nonce,
    ),
    403,
  )
}

fn valid_csrf(values: List(#(String, String)), expected: String) -> Bool {
  case form_value(values, "csrf_token") {
    Ok(actual) -> security.secure_equals(actual, expected)
    Error(_) -> False
  }
}

fn cross_site_post(req: wisp.Request) -> Bool {
  case req.method, request.get_header(req, "sec-fetch-site") {
    Post, Ok("cross-site") -> True
    _, _ -> False
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
        Ok(minutes)
          if minutes == 0
          || minutes == 15
          || minutes == 60
          || minutes == 1440
          || minutes == 10_080
          || minutes == config.default_expiration_minutes
        -> minutes
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

fn digest_pin(pin: Option(String), secret: String) -> Option(String) {
  case pin {
    Some(pin) -> Some(security.hmac_sha256(secret, "dropnest-pin:" <> pin))
    None -> None
  }
}

fn digest_session(pin: Option(String), secret: String) -> Option(String) {
  case pin {
    Some(pin) -> Some(security.hmac_sha256(secret, "dropnest-session:" <> pin))
    None -> None
  }
}

fn browser_session(runtime: Runtime, request: wisp.Request) -> Option(String) {
  case runtime.session_token {
    Some(base) ->
      Some(security.hmac_sha256(
        base,
        "dropnest-browser-session:"
          <> client_fingerprint(request, runtime.secret),
      ))
    None -> None
  }
}

fn activate_new_invite(secret: String) -> Nil {
  let token = wisp.random_string(48)
  let digest = security.hmac_sha256(secret, "dropnest-invite:" <> token)
  security.set_active_invite(token, digest, storage.now_seconds() + 15 * 60)
}

fn invite_url(runtime: Runtime) -> Option(String) {
  case runtime.config.public_url, security.active_invite() {
    Some(base), Ok(#(token, _, _)) -> Some(base <> "/i/" <> token)
    _, _ -> None
  }
}

fn local_admin_request(request: wisp.Request) -> Bool {
  let host_is_local = case request.get_header(request, "host") {
    Ok(host) -> {
      let host = string.lowercase(host)
      host == "localhost"
      || string.starts_with(host, "localhost:")
      || host == "127.0.0.1"
      || string.starts_with(host, "127.0.0.1:")
      || host == "[::1]"
      || string.starts_with(host, "[::1]:")
    }
    Error(_) -> False
  }
  let peer_is_loopback =
    request.get_header(request, "x-dropnest-loopback-peer") == Ok("1")
  let bypasses_public_proxy =
    request.get_header(request, "cf-connecting-ip") |> result.is_error

  host_is_local && peer_is_loopback && bypasses_public_proxy
}

fn prepare_tunnel(config: app_config.Config) -> app_config.Config {
  case config.tunnel {
    False -> config
    True ->
      case net.start_quick_tunnel(config.port) {
        Ok(url) -> app_config.Config(..config, public_url: Some(url))
        Error(message) -> {
          io.println(
            "DropNest could not create a temporary friend link: " <> message,
          )
          io.println(
            "Install cloudflared and make sure it is available on PATH.",
          )
          process.sleep_forever()
          config
        }
      }
  }
}

fn secure_cookie_suffix(request: wisp.Request) -> String {
  case request.get_header(request, "x-forwarded-proto") {
    Ok("https") -> "; Secure"
    _ -> ""
  }
}

fn security_headers(
  response: wisp.Response,
  nonce: String,
  config: app_config.Config,
) -> wisp.Response {
  let csp =
    "default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; img-src 'self' data:; style-src 'nonce-"
    <> nonce
    <> "'; script-src 'nonce-"
    <> nonce
    <> "'"

  let response =
    response
    |> wisp.set_header("content-security-policy", csp)
    |> wisp.set_header("x-content-type-options", "nosniff")
    |> wisp.set_header("x-frame-options", "DENY")
    |> wisp.set_header("referrer-policy", "no-referrer")
    |> wisp.set_header(
      "permissions-policy",
      "camera=(), microphone=(), geolocation=(), payment=()",
    )
    |> wisp.set_header("cache-control", "no-store")
    |> wisp.set_header("cross-origin-resource-policy", "same-origin")

  case config.public_url {
    Some(_) ->
      response
      |> wisp.set_header(
        "strict-transport-security",
        "max-age=31536000; includeSubDomains",
      )
    None -> response
  }
}

fn cleanup_loop(config: app_config.Config) -> Nil {
  process.sleep(60 * 1000)
  let _ = storage.clean_expired(config)
  security.prune_rate_limits(60 * 60)
  cleanup_loop(config)
}

fn print_banner(config: app_config.Config) -> Nil {
  case config.lan {
    True -> io.println("\nDropNest is ready for family sharing.\n")
    False -> io.println("\nDropNest is running locally.\n")
  }

  io.println("This computer:")
  io.println("  http://localhost:" <> int.to_string(config.port))

  case config.lan {
    True -> {
      io.println("\nShare this address:")
      case config.public_url {
        Some(url) -> io.println("  " <> url)
        None ->
          net.lan_urls(config.host, config.port)
          |> list.each(fn(url) { io.println("  " <> url) })
      }
      io.println("\nAccess key: enabled")
      io.println("Files: " <> config.receive_dir)
      case config.public_url {
        Some(_) ->
          io.println("Public HTTPS mode: secure cookies and HSTS enabled")
        None ->
          io.println("LAN mode: keep this port inside your trusted network")
      }
    }
    False -> {
      case config.public_url {
        Some(url) -> {
          io.println("\nTemporary HTTPS tunnel:")
          io.println("  " <> url)
          io.println(
            "Open localhost in your browser to copy the two-visitor invite.",
          )
        }
        None ->
          io.println(
            "\nTip: use --lan with an 8+ character access key to share on Wi-Fi.",
          )
      }
      io.println("Files: " <> config.receive_dir)
    }
  }

  io.println("")
}
