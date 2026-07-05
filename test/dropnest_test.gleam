import dropnest/config
import dropnest/drop
import dropnest/storage
import dropnest/view
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn default_parse_starts_server_test() {
  config.from_args([])
  |> should.equal(
    config.Run(config.Config(
      host: "127.0.0.1",
      port: 7070,
      lan: False,
      pin: option.None,
      data_dir: "./data",
      receive_dir: "./DropNestDrops",
      max_upload_bytes: 104_857_600,
      default_expiration_minutes: 1440,
      host_was_set: False,
    )),
  )
}

pub fn cli_overrides_defaults_test() {
  config.from_args([
    "serve",
    "--lan",
    "--pin",
    "1234",
    "--dir",
    "/tmp/DropNest",
    "--port",
    "8080",
    "--max-upload-mb",
    "250",
    "--expires",
    "0",
  ])
  |> should.equal(
    config.Run(config.Config(
      host: "0.0.0.0",
      port: 8080,
      lan: True,
      pin: option.Some("1234"),
      data_dir: "./data",
      receive_dir: "/tmp/DropNest",
      max_upload_bytes: 262_144_000,
      default_expiration_minutes: 0,
      host_was_set: False,
    )),
  )
}

pub fn config_file_is_loaded_test() {
  let path = "./build/dropnest-test.conf"
  let assert Ok(_) =
    simplifile.write(
      to: path,
      contents: "lan=true\npin=2468\ndir=/tmp/from-config\nport=9090\nexpires=60\n",
    )

  config.from_args(["--config", path])
  |> should.equal(
    config.Run(config.Config(
      host: "0.0.0.0",
      port: 9090,
      lan: True,
      pin: option.Some("2468"),
      data_dir: "./data",
      receive_dir: "/tmp/from-config",
      max_upload_bytes: 104_857_600,
      default_expiration_minutes: 60,
      host_was_set: False,
    )),
  )
}

pub fn send_commands_parse_test() {
  config.from_args(["send-text", "hello", "--dir", "/tmp/DropNest"])
  |> should.equal(config.SendText(
    config.Config(
      host: "127.0.0.1",
      port: 7070,
      lan: False,
      pin: option.None,
      data_dir: "./data",
      receive_dir: "/tmp/DropNest",
      max_upload_bytes: 104_857_600,
      default_expiration_minutes: 1440,
      host_was_set: False,
    ),
    "hello",
  ))
}

pub fn never_expiring_drop_round_trips_test() {
  let item =
    drop.Drop(
      id: "0123456789abcdef0123456789abcdef",
      kind: drop.Text,
      title: "note",
      original_filename: option.None,
      stored_filename: option.None,
      mime_type: option.Some("text/plain"),
      size_bytes: option.Some(4),
      text_content: option.Some("note"),
      created_at: 100,
      expires_at: 0,
    )

  [item]
  |> drop.encode_all
  |> drop.decode_all
  |> should.equal([item])
}

pub fn receive_directory_rejects_broad_paths_test() {
  storage.valid_id("0123456789abcdef0123456789abcdef")
  |> should.be_true

  config.validate_receive_dir("/")
  |> should.equal(Error(
    "Refusing to use the filesystem root as the receive directory.",
  ))
}

pub fn homepage_contains_offline_qr_engine_test() {
  let html = view.home(config.default(), [])

  string.contains(html, "const DropNestQR =")
  |> should.be_true

  string.contains(html, "api.qrserver.com")
  |> should.be_false
}
