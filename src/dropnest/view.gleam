import birl
import dropnest/config
import dropnest/drop.{type Drop, File, Text}
import dropnest/net
import dropnest/storage
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import wisp

pub fn home(
  cfg: config.Config,
  drops: List(Drop),
  csrf_token: String,
  nonce: String,
  invite_url: Option(String),
) -> String {
  page(
    "DropNest",
    [
      header(cfg, csrf_token),
      share_card(cfg, invite_url),
      "<div class='composer-grid'>\n",
      upload_card(cfg, csrf_token),
      text_card(cfg, csrf_token),
      "</div>\n",
      drops_section(drops, csrf_token),
      details_card(cfg),
      footer(),
    ],
    nonce,
  )
}

pub fn unlock(csrf_token: String, nonce: String, failed: Bool) -> String {
  let error = case failed {
    True ->
      "<p class='form-error' role='alert'>That access key did not match.</p>"
    False -> ""
  }
  page(
    "Unlock DropNest",
    [
      html([
        "<section class='auth-card'>",
        "  <div class='brand-mark'>D</div>",
        "  <p class='kicker'>Private DropNest</p>",
        "  <h1>Welcome in</h1>",
        "  <p class='muted'>Enter the family access key, or open the temporary friend link you received.</p>",
        error,
        "  <form method='post' action='/unlock'>",
        csrf_input(csrf_token),
        "    <label for='pin'>Access key</label>",
        "    <input id='pin' name='pin' type='password' autocomplete='current-password' minlength='8' maxlength='128' placeholder='Family access key' required autofocus>",
        "    <button class='primary full'>Unlock DropNest</button>",
        "  </form>",
        "  <p class='fineprint'>No account, analytics, or cloud storage. Access lasts for this browser session.</p>",
        "</section>",
      ]),
    ],
    nonce,
  )
}

pub fn message(title: String, text: String, nonce: String) -> String {
  page(
    title,
    [
      html([
        "<section class='auth-card'>",
        "  <h1>" <> esc(title) <> "</h1>",
        "  <p class='muted'>" <> esc(text) <> "</p>",
        "  <p><a class='button secondary' href='/'>Back home</a></p>",
        "</section>",
      ]),
    ],
    nonce,
  )
}

fn header(cfg: config.Config, csrf_token: String) -> String {
  let logout = case cfg.pin {
    Some(_) ->
      "<form method='post' action='/logout' class='logout-form'>"
      <> csrf_input(csrf_token)
      <> "<button class='ghost compact'>Lock</button></form>"
    None -> ""
  }
  html([
    "<header class='site-header'>",
    "  <div class='brand'>",
    "    <div class='brand-mark'>D</div>",
    "    <div><h1>DropNest</h1><p>Share directly. Keep ownership.</p></div>",
    "  </div>",
    logout,
    "</header>",
  ])
}

fn share_card(cfg: config.Config, invite_url: Option(String)) -> String {
  let mode = case cfg.lan {
    True -> "Same Wi-Fi"
    False -> "This device"
  }
  let #(address, label, note) = case invite_url, cfg.public_url, cfg.lan {
    Some(url), _, _ -> #(
      url,
      "Temporary friend link",
      "Works from anywhere for 15 minutes and grants access to two visitor fingerprints. It disappears when DropNest stops.",
    )
    None, Some(url), _ -> #(
      url,
      "Public HTTPS address",
      "Protected by your access key and HTTPS proxy.",
    )
    None, None, True -> #(
      net.primary_lan_url(cfg.host, cfg.port),
      "Family link",
      "Open this on another device connected to the same Wi-Fi.",
    )
    _, _, _ -> #(
      "http://localhost:" <> int.to_string(cfg.port),
      "Local address",
      "Only this computer can open the link until LAN or tunnel mode is enabled.",
    )
  }

  html([
    "<section class='share-card'>",
    "  <div class='share-heading'>",
    "    <div><p class='eyebrow'>"
      <> esc(label)
      <> "</p><h2>Bring someone into the nest</h2></div>",
    "    <span class='pill'>" <> esc(mode) <> "</span>",
    "  </div>",
    "  <p class='share-note'>" <> esc(note) <> "</p>",
    "  <div class='link-row'>",
    "    <input value='"
      <> esc(address)
      <> "' readonly aria-label='Share link'>",
    "    <button class='primary' type='button' data-copy='"
      <> esc(address)
      <> "'>Copy link</button>",
    "    <button class='secondary' type='button' data-qr='"
      <> esc(address)
      <> "'>QR code</button>",
    "  </div>",
    "  <div class='qr-panel' id='qr-panel' hidden>",
    "    <div id='qr-code' aria-label='QR code for DropNest URL'></div>",
    "    <p class='muted'>Scan with the device you want to invite.</p>",
    "  </div>",
    "</section>",
  ])
}

fn upload_card(cfg: config.Config, csrf_token: String) -> String {
  html([
    "<section class='card composer-card'>",
    "  <div class='card-heading'>",
    "    <h2>Drop a file</h2>",
    "    <span class='limit'>Max "
      <> format_size(cfg.max_upload_bytes)
      <> "</span>",
    "  </div>",
    "  <p class='muted'>Stored on the host with a SHA-256 integrity fingerprint.</p>",
    "  <form method='post' action='/drops/file' enctype='multipart/form-data'>",
    csrf_input(csrf_token),
    "    <label class='filebox' data-dropzone>",
    "      <span class='file-icon'>↑</span>",
    "      <strong>Choose or drop a file</strong>",
    "      <small>The original name is preserved; the storage path is not.</small>",
    "      <input type='file' name='file' required>",
    "    </label>",
    expiration_select("file-expires", cfg.default_expiration_minutes),
    "    <button class='primary full'>Upload file</button>",
    "  </form>",
    "</section>",
  ])
}

fn text_card(cfg: config.Config, csrf_token: String) -> String {
  html([
    "<section class='card composer-card'>",
    "  <h2>Drop text</h2>",
    "  <p class='muted'>Links, commands, notes, snippets, and clipboard text.</p>",
    "  <form method='post' action='/drops/text'>",
    csrf_input(csrf_token),
    "    <textarea name='content' rows='7' maxlength='200000' placeholder='Paste text, link, command, or note...' required></textarea>",
    expiration_select("text-expires", cfg.default_expiration_minutes),
    "    <button class='primary full'>Share text</button>",
    "  </form>",
    "</section>",
  ])
}

fn details_card(cfg: config.Config) -> String {
  let access = case cfg.pin {
    Some(_) -> "Access key on"
    None -> "Local only"
  }
  html([
    "<details class='card server-details'>",
    "  <summary>Storage & security details</summary>",
    "  <dl>",
    "    <div><dt>Files live in</dt><dd><code>"
      <> esc(cfg.receive_dir)
      <> "</code></dd></div>",
    "    <div><dt>Upload limit</dt><dd>"
      <> format_size(cfg.max_upload_bytes)
      <> "</dd></div>",
    "    <div><dt>Storage ceiling</dt><dd>"
      <> format_size(cfg.max_storage_bytes)
      <> "</dd></div>",
    "    <div><dt>Default lifetime</dt><dd>"
      <> format_expiration_label(cfg.default_expiration_minutes)
      <> "</dd></div>",
    "    <div><dt>Protection</dt><dd>"
      <> access
      <> " · CSRF guarded · SHA-256 checked</dd></div>",
    "  </dl>",
    "</details>",
  ])
}

fn csrf_input(token: String) -> String {
  "<input type='hidden' name='csrf_token' value='" <> esc(token) <> "'>"
}

fn expiration_select(id: String, default_minutes: Int) -> String {
  html([
    "    <label for='" <> id <> "'>Keep drop for</label>",
    "    <select id='" <> id <> "' name='expires'>",
    option("15", "15 minutes", default_minutes == 15),
    option("60", "1 hour", default_minutes == 60),
    option("1440", "1 day", default_minutes == 1440),
    option("10080", "1 week", default_minutes == 10_080),
    option("0", "Forever", default_minutes == 0),
    "    </select>",
  ])
}

fn option(value: String, label: String, selected: Bool) -> String {
  let selected_attr = case selected {
    True -> " selected"
    False -> ""
  }

  "      <option value='"
  <> value
  <> "'"
  <> selected_attr
  <> ">"
  <> label
  <> "</option>"
}

fn drops_section(drops: List(Drop), csrf_token: String) -> String {
  case drops {
    [] ->
      html([
        "<section class='card'>",
        "  <h2>Recent Drops</h2>",
        "  <div class='empty'>",
        "    <strong>No drops yet.</strong>",
        "    <span>Send a file or paste some text to get started.</span>",
        "  </div>",
        "</section>",
      ])
    _ ->
      html([
        "<section class='card'>",
        "  <div class='card-heading'>",
        "    <h2>Recent Drops</h2>",
        "    <span class='limit'>Newest first</span>",
        "  </div>",
        "  <div class='drops'>",
        string_join(
          list.map(drops, fn(item) { drop_item(item, csrf_token) }),
          "",
        ),
        "  </div>",
        "</section>",
      ])
  }
}

fn drop_item(item: Drop, csrf_token: String) -> String {
  let icon = case item.kind {
    File -> "FILE"
    Text -> "TEXT"
  }
  let actions = case item.kind {
    File ->
      "<a class='button secondary' href='/drops/"
      <> esc(item.id)
      <> "/download'>Download</a>"
    Text -> {
      let content = case item.text_content {
        Some(text) -> text
        None -> ""
      }
      "<button class='secondary' type='button' data-copy='"
      <> esc(content)
      <> "'>Copy</button>"
    }
  }

  html([
    "<article class='drop'>",
    "  <div class='drop-icon'>" <> icon <> "</div>",
    "  <div class='drop-main'>",
    "    <h3>" <> esc(display_title(item)) <> "</h3>",
    "    <p>" <> meta(item) <> "</p>",
    preview(item),
    checksum(item),
    "  </div>",
    "  <div class='actions'>",
    "    " <> actions,
    "    <form method='post' action='/drops/" <> esc(item.id) <> "/delete'>",
    csrf_input(csrf_token),
    "      <button class='danger' data-confirm-delete>Delete</button>",
    "    </form>",
    "  </div>",
    "</article>",
  ])
}

fn checksum(item: Drop) -> String {
  case item.checksum_sha256 {
    Some(value) ->
      "<button class='checksum' type='button' data-copy='"
      <> esc(value)
      <> "' title='Copy full SHA-256'>SHA-256 · "
      <> esc(string.slice(value, at_index: 0, length: 12))
      <> "…</button>"
    None -> ""
  }
}

fn display_title(item: Drop) -> String {
  case item.kind {
    File -> item.title
    Text -> string.slice(item.title, at_index: 0, length: 96)
  }
}

fn preview(item: Drop) -> String {
  case item.kind, item.text_content {
    Text, Some(text) ->
      "<p class='preview'>"
      <> esc(string.slice(text, at_index: 0, length: 140))
      <> "</p>"
    _, _ -> ""
  }
}

fn meta(item: Drop) -> String {
  let kind = case item.kind {
    File -> "File"
    Text -> "Text"
  }
  let size = case item.kind, item.size_bytes {
    File, Some(bytes) -> " · " <> format_size(bytes)
    _, _ -> ""
  }
  let expiration = case item.expires_at {
    0 -> "never expires"
    expires_at ->
      "expires in " <> format_duration(expires_at - storage.now_seconds())
  }
  kind
  <> size
  <> " · created "
  <> format_time(item.created_at)
  <> " · "
  <> expiration
}

fn page(title: String, body: List(String), nonce: String) -> String {
  html([
    "<!doctype html>",
    "<html lang='en'>",
    "<head>",
    "  <meta charset='utf-8'>",
    "  <meta name='viewport' content='width=device-width, initial-scale=1'>",
    "  <title>" <> esc(title) <> "</title>",
    "  <style nonce='" <> esc(nonce) <> "'>",
    css(),
    "  </style>",
    "</head>",
    "<body>",
    "  <main class='shell'>",
    string_join(body, ""),
    "  </main>",
    "  <script nonce='" <> esc(nonce) <> "'>",
    js(),
    "  </script>",
    "</body>",
    "</html>",
  ])
}

fn footer() -> String {
  "<footer>Your host keeps the files. DropNest keeps no cloud copy, account, or tracking profile.</footer>"
}

fn esc(value: String) -> String {
  wisp.escape_html(value)
}

fn html(lines: List(String)) -> String {
  string_join(lines, "\n") <> "\n"
}

fn string_join(items: List(String), separator: String) -> String {
  case items {
    [] -> ""
    [one] -> one
    [one, ..rest] -> one <> separator <> string_join(rest, separator)
  }
}

fn format_size(bytes: Int) -> String {
  case bytes < 1024 {
    True -> int.to_string(bytes) <> " B"
    False ->
      case bytes < 1024 * 1024 {
        True -> int.to_string(bytes / 1024) <> " KB"
        False ->
          case bytes < 1024 * 1024 * 1024 {
            True -> int.to_string(bytes / 1024 / 1024) <> " MB"
            False -> int.to_string(bytes / 1024 / 1024 / 1024) <> " GB"
          }
      }
  }
}

fn format_duration(seconds: Int) -> String {
  case seconds == 0 {
    True -> "never"
    False -> format_positive_duration(seconds)
  }
}

fn format_positive_duration(seconds: Int) -> String {
  case seconds <= 0 {
    True -> "now"
    False ->
      case seconds < 60 {
        True -> int.to_string(seconds) <> " seconds"
        False ->
          case seconds < 3600 {
            True -> int.to_string(seconds / 60) <> " minutes"
            False -> int.to_string(seconds / 3600) <> " hours"
          }
      }
  }
}

fn format_expiration_label(minutes: Int) -> String {
  case minutes <= 0 {
    True -> "Forever"
    False -> "After " <> int.to_string(minutes) <> " minutes"
  }
}

fn format_time(seconds: Int) -> String {
  seconds
  |> birl.from_unix
  |> birl.to_iso8601
}

fn css() -> String {
  string_join(
    [
      ":root {",
      "  color-scheme: light;",
      "  --bg: #f4f1ea;",
      "  --card: #fffdf8;",
      "  --ink: #1f1b16;",
      "  --muted: #70685d;",
      "  --line: #d8ccba;",
      "  --soft: #f6efe3;",
      "  --soft2: #ebe2d4;",
      "  --accent: #20584d;",
      "  --accent2: #174239;",
      "  --danger: #9c342d;",
      "  --focus: #bf8c2c;",
      "}",
      "",
      "* {",
      "  box-sizing: border-box;",
      "}",
      "",
      "body {",
      "  margin: 0;",
      "  background: var(--bg);",
      "  color: var(--ink);",
      "  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;",
      "  font-size: 16px;",
      "  line-height: 1.5;",
      "}",
      "",
      ".shell {",
      "  width: min(920px, 100%);",
      "  margin: 0 auto;",
      "  padding: 28px 16px 44px;",
      "}",
      "",
      ".site-header,",
      ".card,",
      ".auth-card {",
      "  background: var(--card);",
      "  border: 1px solid var(--line);",
      "  border-radius: 14px;",
      "  box-shadow: 0 2px 0 rgba(40, 32, 20, .08);",
      "}",
      "",
      ".site-header {",
      "  padding: 26px 28px;",
      "  margin-bottom: 16px;",
      "  background: #fffaf0;",
      "}",
      "",
      ".site-header h1,",
      ".auth-card h1 {",
      "  font-size: clamp(2.1rem, 7vw, 3.8rem);",
      "  line-height: .95;",
      "  margin: 0 0 8px;",
      "  letter-spacing: -.055em;",
      "}",
      "",
      ".site-header p,",
      ".auth-card p,",
      "p {",
      "  margin: 0 0 12px;",
      "}",
      "",
      ".kicker {",
      "  margin: 0 0 8px;",
      "  color: var(--accent);",
      "  font-size: .78rem;",
      "  font-weight: 900;",
      "  text-transform: uppercase;",
      "  letter-spacing: .11em;",
      "}",
      "",
      ".muted,",
      ".fineprint {",
      "  color: var(--muted);",
      "}",
      "",
      ".fineprint {",
      "  font-size: .92rem;",
      "  margin-top: 14px;",
      "}",
      "",
      ".card {",
      "  padding: 20px;",
      "  margin: 14px 0;",
      "}",
      "",
      ".auth-card {",
      "  max-width: 440px;",
      "  margin: 12vh auto 0;",
      "  padding: 28px;",
      "}",
      "",
      "h2 {",
      "  font-size: 1.18rem;",
      "  margin: 0 0 10px;",
      "}",
      "",
      "h3 {",
      "  font-size: 1rem;",
      "  margin: 0 0 4px;",
      "  overflow-wrap: anywhere;",
      "}",
      "",
      ".card-heading {",
      "  display: flex;",
      "  align-items: center;",
      "  justify-content: space-between;",
      "  gap: 12px;",
      "  margin-bottom: 8px;",
      "}",
      "",
      ".pill,",
      ".limit {",
      "  display: inline-flex;",
      "  align-items: center;",
      "  border: 1px solid var(--line);",
      "  background: var(--soft);",
      "  border-radius: 999px;",
      "  padding: 4px 9px;",
      "  color: #453d34;",
      "  font-size: .84rem;",
      "  font-weight: 800;",
      "}",
      "",
      ".status-card dl {",
      "  display: grid;",
      "  grid-template-columns: repeat(2, minmax(0, 1fr));",
      "  gap: 10px;",
      "  margin: 12px 0 0;",
      "}",
      "",
      ".status-card dl div {",
      "  background: var(--soft);",
      "  border: 1px solid #e5d9c8;",
      "  border-radius: 10px;",
      "  padding: 11px;",
      "}",
      "",
      ".status-card dt {",
      "  font-size: .75rem;",
      "  text-transform: uppercase;",
      "  letter-spacing: .08em;",
      "  color: var(--muted);",
      "  font-weight: 900;",
      "}",
      "",
      ".status-card dd {",
      "  margin: 3px 0 0;",
      "  font-weight: 750;",
      "  overflow-wrap: anywhere;",
      "}",
      "",
      "code {",
      "  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;",
      "  background: #eee5d8;",
      "  border: 1px solid #d9cbbb;",
      "  border-radius: 6px;",
      "  padding: 1px 5px;",
      "  overflow-wrap: anywhere;",
      "}",
      "",
      ".notice {",
      "  background: #edf6f2;",
      "  border: 1px solid #c9ddd5;",
      "  border-radius: 10px;",
      "  padding: 10px 12px;",
      "  margin: 14px 0 0;",
      "}",
      "",
      ".warning {",
      "  background: #fff4cf;",
      "  border-color: #e3c26d;",
      "  color: #574000;",
      "}",
      "",
      ".filebox {",
      "  display: grid;",
      "  gap: 8px;",
      "  place-items: center;",
      "  text-align: center;",
      "  border: 2px dashed #b7aa98;",
      "  border-radius: 12px;",
      "  background: #fff9ed;",
      "  padding: 26px 18px;",
      "  margin: 14px 0;",
      "}",
      "",
      ".filebox:hover {",
      "  border-color: var(--accent);",
      "  background: #fff6e4;",
      "}",
      "",
      ".filebox.dragging {",
      "  border-color: var(--accent);",
      "  background: #edf6f2;",
      "  box-shadow: inset 0 0 0 2px rgba(32, 88, 77, .16);",
      "}",
      "",
      ".filebox input {",
      "  width: 100%;",
      "  max-width: 28rem;",
      "}",
      "",
      ".file-icon,",
      ".drop-icon {",
      "  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;",
      "  font-weight: 900;",
      "  letter-spacing: .04em;",
      "}",
      "",
      ".file-icon {",
      "  color: var(--accent);",
      "  font-size: .92rem;",
      "}",
      "",
      "label {",
      "  display: block;",
      "  font-weight: 800;",
      "  margin-bottom: 6px;",
      "}",
      "",
      "textarea,",
      "input,",
      "select {",
      "  width: 100%;",
      "  border: 1px solid #c9bba9;",
      "  border-radius: 10px;",
      "  background: #fffefb;",
      "  color: var(--ink);",
      "  font: inherit;",
      "  padding: 12px;",
      "}",
      "",
      "textarea {",
      "  resize: vertical;",
      "  min-height: 145px;",
      "}",
      "",
      "textarea:focus,",
      "input:focus,",
      "select:focus {",
      "  outline: 3px solid rgba(191, 140, 44, .24);",
      "  border-color: var(--focus);",
      "}",
      "",
      "button,",
      ".button {",
      "  appearance: none;",
      "  border: 1px solid transparent;",
      "  border-radius: 10px;",
      "  padding: 10px 15px;",
      "  font: inherit;",
      "  font-weight: 850;",
      "  text-decoration: none;",
      "  display: inline-flex;",
      "  align-items: center;",
      "  justify-content: center;",
      "  gap: 8px;",
      "  cursor: pointer;",
      "  min-height: 42px;",
      "}",
      "",
      ".primary {",
      "  background: var(--accent);",
      "  border-color: var(--accent2);",
      "  color: white;",
      "  box-shadow: 0 2px 0 var(--accent2);",
      "}",
      "",
      ".primary:hover {",
      "  background: var(--accent2);",
      "}",
      "",
      ".secondary {",
      "  background: var(--soft2);",
      "  border-color: #c9bba9;",
      "  color: #243d36;",
      "}",
      "",
      ".secondary:hover {",
      "  background: #ded3c3;",
      "}",
      "",
      ".compact {",
      "  min-height: 32px;",
      "  padding: 5px 9px;",
      "}",
      "",
      ".danger {",
      "  background: #fff0ee;",
      "  color: var(--danger);",
      "  border-color: #e0b8b2;",
      "}",
      "",
      ".danger:hover {",
      "  background: #ffe3df;",
      "}",
      "",
      ".full {",
      "  width: 100%;",
      "  margin-top: 8px;",
      "}",
      "",
      ".empty {",
      "  display: grid;",
      "  gap: 4px;",
      "  border: 1px dashed #c7b8a5;",
      "  border-radius: 12px;",
      "  background: #fff9ed;",
      "  padding: 26px;",
      "  text-align: center;",
      "  color: var(--muted);",
      "}",
      "",
      ".qr-panel {",
      "  display: grid;",
      "  justify-items: center;",
      "  gap: 10px;",
      "  margin-top: 14px;",
      "  padding: 16px;",
      "  border: 1px solid var(--line);",
      "  border-radius: 12px;",
      "  background: #fff9ed;",
      "}",
      "",
      ".qr-panel[hidden] {",
      "  display: none;",
      "}",
      "",
      ".qr-panel svg {",
      "  width: 192px;",
      "  height: 192px;",
      "  image-rendering: pixelated;",
      "  background: white;",
      "}",
      "",
      ".drop {",
      "  display: grid;",
      "  grid-template-columns: 56px minmax(0, 1fr) auto;",
      "  gap: 13px;",
      "  align-items: center;",
      "  border-top: 1px solid var(--line);",
      "  padding: 15px 0;",
      "}",
      "",
      ".drop:first-child {",
      "  border-top: 0;",
      "}",
      "",
      ".drop-icon {",
      "  border: 1px solid var(--line);",
      "  background: var(--soft);",
      "  border-radius: 10px;",
      "  padding: 10px 6px;",
      "  text-align: center;",
      "  color: var(--muted);",
      "  font-size: .73rem;",
      "}",
      "",
      ".drop p {",
      "  margin: 0;",
      "  color: var(--muted);",
      "  font-size: .94rem;",
      "}",
      "",
      ".drop .preview {",
      "  margin-top: 7px;",
      "  color: #3f382f;",
      "  overflow-wrap: anywhere;",
      "}",
      "",
      ".actions {",
      "  display: flex;",
      "  gap: 8px;",
      "  align-items: center;",
      "  flex-wrap: wrap;",
      "  justify-content: flex-end;",
      "}",
      "",
      ".actions form {",
      "  display: inline;",
      "}",
      "",
      "footer {",
      "  text-align: center;",
      "  color: var(--muted);",
      "  font-size: .92rem;",
      "  margin-top: 22px;",
      "}",
      "",
      "/* Refined family-sharing layout */",
      ":root {",
      "  --bg: #f6f7f3;",
      "  --card: #ffffff;",
      "  --ink: #15231f;",
      "  --muted: #65716c;",
      "  --line: #dce3df;",
      "  --soft: #f0f4f1;",
      "  --soft2: #e9efeb;",
      "  --accent: #176c57;",
      "  --accent2: #0f5141;",
      "}",
      "",
      "body {",
      "  background: radial-gradient(circle at 50% -10%, #e5f1eb 0, var(--bg) 32rem);",
      "}",
      "",
      ".shell {",
      "  width: min(1040px, 100%);",
      "  padding-top: 22px;",
      "}",
      "",
      ".site-header {",
      "  display: flex;",
      "  align-items: center;",
      "  justify-content: space-between;",
      "  gap: 18px;",
      "  padding: 10px 2px 22px;",
      "  border: 0;",
      "  border-radius: 0;",
      "  box-shadow: none;",
      "  background: transparent;",
      "}",
      "",
      ".brand { display: flex; align-items: center; gap: 12px; }",
      ".brand-mark {",
      "  display: grid;",
      "  place-items: center;",
      "  width: 42px;",
      "  height: 42px;",
      "  flex: 0 0 auto;",
      "  border-radius: 13px;",
      "  background: var(--accent);",
      "  color: #fff;",
      "  font-size: 1.05rem;",
      "  font-weight: 900;",
      "  box-shadow: 0 8px 22px rgba(23, 108, 87, .2);",
      "}",
      "",
      ".site-header h1 {",
      "  margin: 0;",
      "  font-size: 1.18rem;",
      "  line-height: 1.2;",
      "  letter-spacing: -.025em;",
      "}",
      ".site-header p { margin: 1px 0 0; color: var(--muted); font-size: .9rem; }",
      ".logout-form { margin: 0; }",
      "",
      ".share-card {",
      "  position: relative;",
      "  overflow: hidden;",
      "  padding: clamp(22px, 5vw, 38px);",
      "  margin-bottom: 16px;",
      "  border: 1px solid #164b40;",
      "  border-radius: 20px;",
      "  color: #f7fffc;",
      "  background: #123d33;",
      "  box-shadow: 0 18px 50px rgba(20, 48, 40, .14);",
      "}",
      ".share-card::after {",
      "  content: '';",
      "  position: absolute;",
      "  width: 260px;",
      "  height: 260px;",
      "  right: -100px;",
      "  top: -150px;",
      "  border-radius: 50%;",
      "  background: rgba(132, 222, 183, .12);",
      "  pointer-events: none;",
      "}",
      ".share-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 18px; }",
      ".share-card h2 { font-size: clamp(1.35rem, 3vw, 2rem); margin: 2px 0 0; letter-spacing: -.035em; }",
      ".eyebrow { margin: 0; color: #9edfc9; font-weight: 800; font-size: .78rem; letter-spacing: .08em; text-transform: uppercase; }",
      ".share-card .pill { color: #eafff7; background: rgba(255,255,255,.09); border-color: rgba(255,255,255,.18); }",
      ".share-note { max-width: 44rem; margin: 10px 0 18px; color: #c6ddd5; }",
      "",
      ".link-row { display: grid; grid-template-columns: minmax(0, 1fr) auto auto; gap: 9px; }",
      ".link-row input { background: rgba(255,255,255,.96); border: 0; color: #183a31; font-size: .93rem; }",
      ".link-row .primary { background: #dbf7ec; border-color: #dbf7ec; color: #123d33; box-shadow: none; }",
      ".link-row .primary:hover { background: #fff; }",
      ".link-row .secondary { background: transparent; border-color: rgba(255,255,255,.35); color: #fff; }",
      ".link-row .secondary:hover { background: rgba(255,255,255,.1); }",
      ".share-card .qr-panel { background: #fff; color: var(--ink); border: 0; }",
      "",
      ".composer-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; align-items: stretch; }",
      ".composer-grid .card { margin: 0; }",
      ".composer-card { display: flex; flex-direction: column; padding: 24px; }",
      ".composer-card form { display: flex; flex: 1; flex-direction: column; }",
      ".composer-card form > .primary { margin-top: auto; }",
      ".composer-card select { margin-bottom: 16px; }",
      ".composer-card textarea { margin: 10px 0 14px; }",
      "",
      ".card, .auth-card {",
      "  border-color: var(--line);",
      "  border-radius: 16px;",
      "  box-shadow: 0 8px 28px rgba(30, 52, 44, .055);",
      "}",
      ".filebox { background: #f7faf8; border-color: #bbccc5; border-radius: 14px; }",
      ".file-icon { display: grid; place-items: center; width: 36px; height: 36px; border-radius: 11px; background: #e1f1ea; font-size: 1.25rem; }",
      "",
      ".ghost { background: transparent; border-color: var(--line); color: var(--muted); }",
      ".ghost:hover { background: var(--soft); color: var(--ink); }",
      ".form-error { padding: 10px 12px; border-radius: 10px; color: #8d2e28; background: #fff0ee; border: 1px solid #f0cbc6; }",
      ".auth-card .brand-mark { margin-bottom: 20px; }",
      "",
      ".checksum {",
      "  min-height: 0;",
      "  margin-top: 8px;",
      "  padding: 3px 7px;",
      "  border: 1px solid var(--line);",
      "  border-radius: 6px;",
      "  background: var(--soft);",
      "  color: var(--muted);",
      "  font: 700 .72rem ui-monospace, SFMono-Regular, Menlo, monospace;",
      "}",
      ".checksum:hover { color: var(--accent); border-color: #b8d3c9; }",
      "",
      ".server-details { color: var(--muted); }",
      ".server-details summary { cursor: pointer; color: var(--ink); font-weight: 800; }",
      ".server-details dl { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 18px 0 0; }",
      ".server-details dt { font-size: .76rem; font-weight: 800; text-transform: uppercase; letter-spacing: .06em; }",
      ".server-details dd { margin: 4px 0 0; overflow-wrap: anywhere; }",
      "",
      "@media (max-width: 700px) {",
      "  .shell {",
      "    padding: 12px;",
      "  }",
      "",
      "  .site-header,",
      "  .card,",
      "  .auth-card {",
      "    border-radius: 12px;",
      "  }",
      "",
      "  .site-header,",
      "  .card {",
      "    padding: 17px;",
      "  }",
      "",
      "  .auth-card {",
      "    margin: 8vh auto 0;",
      "    padding: 22px;",
      "  }",
      "",
      "  .status-card dl {",
      "    grid-template-columns: 1fr;",
      "  }",
      "",
      "  .card-heading {",
      "    align-items: flex-start;",
      "    flex-direction: column;",
      "  }",
      "",
      "  .drop {",
      "    grid-template-columns: 1fr;",
      "    align-items: start;",
      "  }",
      "",
      "  .drop-icon {",
      "    width: 56px;",
      "  }",
      "",
      "  .actions {",
      "    width: 100%;",
      "    justify-content: stretch;",
      "  }",
      "",
      "  .actions button,",
      "  .actions .button {",
      "    flex: 1;",
      "  }",
      "",
      "  .filebox {",
      "    padding: 20px 14px;",
      "  }",
      "",
      "  .composer-grid { grid-template-columns: 1fr; }",
      "  .link-row { grid-template-columns: 1fr 1fr; }",
      "  .link-row input { grid-column: 1 / -1; }",
      "  .server-details dl { grid-template-columns: 1fr; }",
      "  .share-heading { flex-direction: column; }",
      "}",
    ],
    "\n",
  )
}

fn qr_engine_js() -> String {
  string_join(
    [
      "const DropNestQR = (() => {",
      "  const RS = [",
      "    [[1, 26, 16]],",
      "    [[1, 44, 28]],",
      "    [[1, 70, 44]],",
      "    [[2, 50, 32]],",
      "    [[2, 67, 43]],",
      "    [[4, 43, 27]],",
      "    [[4, 49, 31]],",
      "    [[2, 60, 38], [2, 61, 39]],",
      "    [[3, 58, 36], [2, 59, 37]],",
      "    [[4, 69, 43], [1, 70, 44]],",
      "  ];",
      "  const ALIGN = [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];",
      "  const EXP = new Array(512);",
      "  const LOG = new Array(256);",
      "  let x = 1;",
      "  for (let i = 0; i < 255; i++) {",
      "    EXP[i] = x;",
      "    LOG[x] = i;",
      "    x <<= 1;",
      "    if (x & 0x100) x ^= 0x11d;",
      "  }",
      "  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];",
      "",
      "  function bytes(text) {",
      "    if (typeof TextEncoder !== 'undefined') return Array.from(new TextEncoder().encode(text));",
      "    const out = [];",
      "    for (const ch of encodeURIComponent(text).replace(/%([0-9A-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))) out.push(ch.charCodeAt(0));",
      "    return out;",
      "  }",
      "",
      "  function gfMul(a, b) {",
      "    if (a === 0 || b === 0) return 0;",
      "    return EXP[LOG[a] + LOG[b]];",
      "  }",
      "",
      "  function polyMul(a, b) {",
      "    const out = new Array(a.length + b.length - 1).fill(0);",
      "    for (let i = 0; i < a.length; i++) {",
      "      for (let j = 0; j < b.length; j++) out[i + j] ^= gfMul(a[i], b[j]);",
      "    }",
      "    return out;",
      "  }",
      "",
      "  function generator(degree) {",
      "    let poly = [1];",
      "    for (let i = 0; i < degree; i++) poly = polyMul(poly, [1, EXP[i]]);",
      "    return poly;",
      "  }",
      "",
      "  function rsEncode(data, degree) {",
      "    const gen = generator(degree);",
      "    const out = new Array(degree).fill(0);",
      "    for (const value of data) {",
      "      const factor = value ^ out.shift();",
      "      out.push(0);",
      "      for (let i = 0; i < degree; i++) out[i] ^= gfMul(gen[i + 1], factor);",
      "    }",
      "    return out;",
      "  }",
      "",
      "  function dataCapacity(version) {",
      "    return RS[version - 1].reduce((sum, block) => sum + block[0] * block[2], 0);",
      "  }",
      "",
      "  function chooseVersion(data) {",
      "    for (let version = 1; version <= RS.length; version++) {",
      "      const lengthBits = version < 10 ? 8 : 16;",
      "      if (4 + lengthBits + data.length * 8 <= dataCapacity(version) * 8) return version;",
      "    }",
      "    throw new Error('URL is too long for the built-in QR encoder.');",
      "  }",
      "",
      "  function buildData(data, version) {",
      "    const bits = [];",
      "    const put = (value, width) => {",
      "      for (let i = width - 1; i >= 0; i--) bits.push((value >>> i) & 1);",
      "    };",
      "    put(4, 4);",
      "    put(data.length, version < 10 ? 8 : 16);",
      "    for (const value of data) put(value, 8);",
      "",
      "    const capacityBits = dataCapacity(version) * 8;",
      "    for (let i = 0; i < Math.min(4, capacityBits - bits.length); i++) bits.push(0);",
      "    while (bits.length % 8 !== 0) bits.push(0);",
      "",
      "    const words = [];",
      "    for (let i = 0; i < bits.length; i += 8) words.push(bits.slice(i, i + 8).reduce((n, bit) => (n << 1) | bit, 0));",
      "    for (let pad = 0xec; words.length < dataCapacity(version); pad = pad === 0xec ? 0x11 : 0xec) words.push(pad);",
      "    return words;",
      "  }",
      "",
      "  function addErrorCorrection(words, version) {",
      "    const blocks = [];",
      "    let offset = 0;",
      "    for (const [count, total, dataCount] of RS[version - 1]) {",
      "      for (let i = 0; i < count; i++) {",
      "        const data = words.slice(offset, offset + dataCount);",
      "        offset += dataCount;",
      "        blocks.push({ data, ec: rsEncode(data, total - dataCount) });",
      "      }",
      "    }",
      "",
      "    const out = [];",
      "    const maxData = Math.max(...blocks.map(block => block.data.length));",
      "    const maxEc = Math.max(...blocks.map(block => block.ec.length));",
      "    for (let i = 0; i < maxData; i++) for (const block of blocks) if (i < block.data.length) out.push(block.data[i]);",
      "    for (let i = 0; i < maxEc; i++) for (const block of blocks) if (i < block.ec.length) out.push(block.ec[i]);",
      "    return out;",
      "  }",
      "",
      "  function makeBase(version) {",
      "    const size = version * 4 + 17;",
      "    const modules = Array.from({ length: size }, () => new Array(size).fill(null));",
      "    const set = (row, col, dark) => { if (row >= 0 && row < size && col >= 0 && col < size) modules[row][col] = dark; };",
      "    const finder = (row, col) => {",
      "      for (let y = -1; y <= 7; y++) {",
      "        for (let x = -1; x <= 7; x++) {",
      "          const r = row + y;",
      "          const c = col + x;",
      "          const dark = y >= 0 && y <= 6 && x >= 0 && x <= 6 && (y === 0 || y === 6 || x === 0 || x === 6 || (y >= 2 && y <= 4 && x >= 2 && x <= 4));",
      "          set(r, c, dark);",
      "        }",
      "      }",
      "    };",
      "",
      "    finder(0, 0); finder(0, size - 7); finder(size - 7, 0);",
      "    for (let i = 8; i < size - 8; i++) {",
      "      set(6, i, i % 2 === 0);",
      "      set(i, 6, i % 2 === 0);",
      "    }",
      "",
      "    if (version > 1) {",
      "      for (const row of ALIGN[version - 1]) {",
      "        for (const col of ALIGN[version - 1]) {",
      "          if (modules[row][col] !== null) continue;",
      "          for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) set(row + y, col + x, Math.max(Math.abs(x), Math.abs(y)) !== 1);",
      "        }",
      "      }",
      "    }",
      "",
      "    for (let i = 0; i < 9; i++) {",
      "      if (i !== 6) { set(8, i, false); set(i, 8, false); }",
      "    }",
      "    for (let i = size - 8; i < size; i++) { set(8, i, false); set(i, 8, false); }",
      "    if (version >= 7) {",
      "      for (let i = 0; i < 18; i++) {",
      "        set(Math.floor(i / 3), i % 3 + size - 11, false);",
      "        set(i % 3 + size - 11, Math.floor(i / 3), false);",
      "      }",
      "    }",
      "    set(size - 8, 8, true);",
      "    return modules;",
      "  }",
      "",
      "  function maskBit(mask, row, col) {",
      "    switch (mask) {",
      "      case 0: return (row + col) % 2 === 0;",
      "      case 1: return row % 2 === 0;",
      "      case 2: return col % 3 === 0;",
      "      case 3: return (row + col) % 3 === 0;",
      "      case 4: return (Math.floor(row / 2) + Math.floor(col / 3)) % 2 === 0;",
      "      case 5: return (row * col) % 2 + (row * col) % 3 === 0;",
      "      case 6: return ((row * col) % 2 + (row * col) % 3) % 2 === 0;",
      "      default: return ((row + col) % 2 + (row * col) % 3) % 2 === 0;",
      "    }",
      "  }",
      "",
      "  function mapData(base, codewords, mask) {",
      "    const modules = base.map(row => row.slice());",
      "    const size = modules.length;",
      "    let bitIndex = 0;",
      "    let direction = -1;",
      "    let row = size - 1;",
      "    for (let col = size - 1; col > 0; col -= 2) {",
      "      if (col === 6) col--;",
      "      while (true) {",
      "        for (let offset = 0; offset < 2; offset++) {",
      "          const c = col - offset;",
      "          if (modules[row][c] === null) {",
      "            const word = codewords[Math.floor(bitIndex / 8)] || 0;",
      "            let dark = ((word >>> (7 - bitIndex % 8)) & 1) === 1;",
      "            if (maskBit(mask, row, c)) dark = !dark;",
      "            modules[row][c] = dark;",
      "            bitIndex++;",
      "          }",
      "        }",
      "        row += direction;",
      "        if (row < 0 || row >= size) {",
      "          row -= direction;",
      "          direction = -direction;",
      "          break;",
      "        }",
      "      }",
      "    }",
      "    return modules;",
      "  }",
      "",
      "  function bchDigit(value) {",
      "    let digit = 0;",
      "    while (value !== 0) { digit++; value >>>= 1; }",
      "    return digit;",
      "  }",
      "",
      "  function formatBits(mask) {",
      "    const generator = 0x537;",
      "    let data = mask;",
      "    let bits = data << 10;",
      "    while (bchDigit(bits) - bchDigit(generator) >= 0) bits ^= generator << (bchDigit(bits) - bchDigit(generator));",
      "    return ((data << 10) | bits) ^ 0x5412;",
      "  }",
      "",
      "  function addFormat(modules, mask) {",
      "    const size = modules.length;",
      "    const bits = formatBits(mask);",
      "    for (let i = 0; i < 15; i++) {",
      "      const dark = ((bits >>> i) & 1) === 1;",
      "      if (i < 6) modules[i][8] = dark; else if (i < 8) modules[i + 1][8] = dark; else modules[size - 15 + i][8] = dark;",
      "      if (i < 8) modules[8][size - i - 1] = dark; else if (i < 9) modules[8][15 - i] = dark; else modules[8][15 - i - 1] = dark;",
      "    }",
      "    modules[size - 8][8] = true;",
      "    return modules;",
      "  }",
      "",
      "  function versionBits(version) {",
      "    const generator = 0x1f25;",
      "    let bits = version << 12;",
      "    while (bchDigit(bits) - bchDigit(generator) >= 0) bits ^= generator << (bchDigit(bits) - bchDigit(generator));",
      "    return (version << 12) | bits;",
      "  }",
      "",
      "  function addVersion(modules, version) {",
      "    if (version < 7) return modules;",
      "    const size = modules.length;",
      "    const bits = versionBits(version);",
      "    for (let i = 0; i < 18; i++) {",
      "      const dark = ((bits >>> i) & 1) === 1;",
      "      modules[Math.floor(i / 3)][i % 3 + size - 11] = dark;",
      "      modules[i % 3 + size - 11][Math.floor(i / 3)] = dark;",
      "    }",
      "    return modules;",
      "  }",
      "",
      "  function lostPoint(modules) {",
      "    const size = modules.length;",
      "    let lost = 0;",
      "    for (let row = 0; row < size; row++) {",
      "      let runColor = modules[row][0];",
      "      let run = 1;",
      "      for (let col = 1; col < size; col++) {",
      "        if (modules[row][col] === runColor) run++; else { if (run >= 5) lost += 3 + run - 5; runColor = modules[row][col]; run = 1; }",
      "      }",
      "      if (run >= 5) lost += 3 + run - 5;",
      "    }",
      "    for (let col = 0; col < size; col++) {",
      "      let runColor = modules[0][col];",
      "      let run = 1;",
      "      for (let row = 1; row < size; row++) {",
      "        if (modules[row][col] === runColor) run++; else { if (run >= 5) lost += 3 + run - 5; runColor = modules[row][col]; run = 1; }",
      "      }",
      "      if (run >= 5) lost += 3 + run - 5;",
      "    }",
      "    for (let row = 0; row < size - 1; row++) for (let col = 0; col < size - 1; col++) {",
      "      const count = [modules[row][col], modules[row + 1][col], modules[row][col + 1], modules[row + 1][col + 1]].filter(Boolean).length;",
      "      if (count === 0 || count === 4) lost += 3;",
      "    }",
      "    const pattern = [true, false, true, true, true, false, true, false, false, false, false];",
      "    for (let row = 0; row < size; row++) for (let col = 0; col <= size - 11; col++) if (pattern.every((value, i) => modules[row][col + i] === value)) lost += 40;",
      "    for (let col = 0; col < size; col++) for (let row = 0; row <= size - 11; row++) if (pattern.every((value, i) => modules[row + i][col] === value)) lost += 40;",
      "    let dark = 0;",
      "    for (const row of modules) for (const value of row) if (value) dark++;",
      "    lost += Math.floor(Math.abs(dark * 20 - size * size * 10) / (size * size)) * 10;",
      "    return lost;",
      "  }",
      "",
      "  function svg(modules) {",
      "    const size = modules.length;",
      "    const quiet = 4;",
      "    const view = size + quiet * 2;",
      "    const path = [];",
      "    for (let row = 0; row < size; row++) for (let col = 0; col < size; col++) if (modules[row][col]) path.push(`M${col + quiet} ${row + quiet}h1v1h-1z`);",
      "    return `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${view} ${view}' role='img' aria-label='QR code'><rect width='100%' height='100%' fill='#fff'/><path fill='#111' d='${path.join('')}'/></svg>`;",
      "  }",
      "",
      "  function make(text) {",
      "    const data = bytes(text);",
      "    const version = chooseVersion(data);",
      "    const codewords = addErrorCorrection(buildData(data, version), version);",
      "    const base = makeBase(version);",
      "    let best = null;",
      "    let bestScore = Infinity;",
      "    for (let mask = 0; mask < 8; mask++) {",
      "      const modules = addVersion(addFormat(mapData(base, codewords, mask), mask), version);",
      "      const score = lostPoint(modules);",
      "      if (score < bestScore) { best = modules; bestScore = score; }",
      "    }",
      "    return svg(best);",
      "  }",
      "",
      "  return { make };",
      "})();",
    ],
    "\n",
  )
}

fn js() -> String {
  string_join(
    [
      qr_engine_js(),
      "async function copyText(value) {",
      "  if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(value);",
      "  const field = document.createElement('textarea');",
      "  field.value = value;",
      "  field.setAttribute('readonly', '');",
      "  field.style.position = 'fixed';",
      "  field.style.opacity = '0';",
      "  document.body.appendChild(field);",
      "  field.select();",
      "  const copied = document.execCommand('copy');",
      "  field.remove();",
      "  if (!copied) throw new Error('copy failed');",
      "}",
      "",
      "document.addEventListener('click', async event => {",
      "  const deleteButton = event.target.closest('[data-confirm-delete]');",
      "  if (deleteButton && !confirm('Delete this drop for everyone?')) {",
      "    event.preventDefault();",
      "    return;",
      "  }",
      "",
      "  const qrButton = event.target.closest('[data-qr]');",
      "  if (qrButton) {",
      "    const panel = document.getElementById('qr-panel');",
      "    const target = document.getElementById('qr-code');",
      "    const url = qrButton.dataset.qr;",
      "",
      "    try {",
      "      target.innerHTML = DropNestQR.make(url);",
      "    } catch (error) {",
      "      target.textContent = error.message;",
      "    }",
      "    panel.hidden = !panel.hidden;",
      "    qrButton.textContent = panel.hidden ? 'Show QR' : 'Hide QR';",
      "    return;",
      "  }",
      "",
      "  const button = event.target.closest('[data-copy]');",
      "  if (!button) return;",
      "",
      "  try {",
      "    await copyText(button.dataset.copy);",
      "    const oldText = button.textContent;",
      "",
      "    button.textContent = 'Copied';",
      "    button.classList.add('copied');",
      "",
      "    setTimeout(() => {",
      "      button.textContent = oldText;",
      "      button.classList.remove('copied');",
      "    }, 1300);",
      "  } catch {",
      "    alert('Copy failed. Your browser may block clipboard access on this page.');",
      "  }",
      "});",
      "",
      "for (const dropzone of document.querySelectorAll('[data-dropzone]')) {",
      "  const input = dropzone.querySelector('input[type=file]');",
      "",
      "  for (const name of ['dragenter', 'dragover']) {",
      "    dropzone.addEventListener(name, event => {",
      "      event.preventDefault();",
      "      dropzone.classList.add('dragging');",
      "    });",
      "  }",
      "",
      "  for (const name of ['dragleave', 'drop']) {",
      "    dropzone.addEventListener(name, event => {",
      "      event.preventDefault();",
      "      dropzone.classList.remove('dragging');",
      "    });",
      "  }",
      "",
      "  dropzone.addEventListener('drop', event => {",
      "    if (!event.dataTransfer || event.dataTransfer.files.length === 0) return;",
      "    input.files = event.dataTransfer.files;",
      "    const file = event.dataTransfer.files[0];",
      "    const strong = dropzone.querySelector('strong');",
      "    if (strong && file) strong.textContent = file.name;",
      "  });",
      "",
      "  input.addEventListener('change', () => {",
      "    const file = input.files && input.files[0];",
      "    const strong = dropzone.querySelector('strong');",
      "    if (strong && file) strong.textContent = file.name;",
      "  });",
      "}",
      "",
      "for (const form of document.querySelectorAll('form')) {",
      "  form.addEventListener('submit', event => {",
      "    if (event.defaultPrevented) return;",
      "    const button = form.querySelector('button[type=submit], button:not([type])');",
      "    if (!button) return;",
      "    button.disabled = true;",
      "    button.dataset.originalText = button.textContent;",
      "    button.textContent = form.enctype === 'multipart/form-data' ? 'Uploading…' : 'Working…';",
      "  });",
      "}",
    ],
    "\n",
  )
}
