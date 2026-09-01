import dropnest/config
import dropnest/drop
import dropnest/security
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
      max_storage_bytes: 10_737_418_240,
      default_expiration_minutes: 1440,
      public_url: option.None,
      tunnel: False,
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
      max_storage_bytes: 10_737_418_240,
      default_expiration_minutes: 0,
      public_url: option.None,
      tunnel: False,
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
      max_storage_bytes: 10_737_418_240,
      default_expiration_minutes: 60,
      public_url: option.None,
      tunnel: False,
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
      max_storage_bytes: 10_737_418_240,
      default_expiration_minutes: 1440,
      public_url: option.None,
      tunnel: False,
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
      checksum_sha256: option.Some(
        "5f2d8fbfef0d2c222b4d7a2c135731763a87b0f6e8c0efdc9468e4461d6f3265",
      ),
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
  let html =
    view.home(
      config.default(),
      [],
      "csrf-test",
      "nonce-test",
      option.None,
      False,
    )

  string.contains(html, "const DropNestQR =")
  |> should.be_true

  string.contains(html, "api.qrserver.com")
  |> should.be_false
}

pub fn insecure_network_modes_are_rejected_test() {
  let insecure = config.Config(..config.default(), lan: True, host: "0.0.0.0")

  insecure
  |> config.validate_security
  |> should.equal(Error(
    "LAN mode requires --pin with an access key of at least 8 characters.",
  ))

  config.from_args(["serve", "--tunnel", "--pin", "family-owl-72"])
  |> should.equal(config.Run(
    config.Config(
      ..config.default(),
      tunnel: True,
      pin: option.Some("family-owl-72"),
    ),
  ))

  config.Config(
    ..config.default(),
    public_url: option.Some("https://drop.example"),
  )
  |> config.validate_security
  |> should.equal(Error(
    "Public HTTPS mode requires --pin with an 8+ character access key.",
  ))
}

pub fn invite_is_limited_to_two_fingerprints_test() {
  security.setup()

  security.claim_invite("test-invite-two-fingerprints", "visitor-a", 2)
  |> should.be_true
  security.claim_invite("test-invite-two-fingerprints", "visitor-b", 2)
  |> should.be_true
  security.claim_invite("test-invite-two-fingerprints", "visitor-a", 2)
  |> should.be_true
  security.claim_invite("test-invite-two-fingerprints", "visitor-c", 2)
  |> should.be_false
}

pub fn friend_link_rotation_invalidates_old_invite_and_resets_slots_test() {
  security.setup()
  security.set_active_invite("token-a", "digest-a", 1000)

  security.claim_active_invite("digest-a", "visitor-a", 100, 2)
  |> should.equal(security.InviteAccepted)
  security.claim_active_invite("digest-a", "visitor-b", 100, 2)
  |> should.equal(security.InviteAccepted)
  security.claim_active_invite("digest-a", "visitor-c", 100, 2)
  |> should.equal(security.InviteFull)

  security.set_active_invite("token-b", "digest-b", 2000)

  security.active_invite()
  |> should.equal(Ok(#("token-b", "digest-b", 2000)))
  security.claim_active_invite("digest-a", "visitor-a", 100, 2)
  |> should.equal(security.InviteInvalid)
  security.claim_active_invite("digest-b", "visitor-c", 100, 2)
  |> should.equal(security.InviteAccepted)
}

pub fn friend_link_regeneration_control_is_host_only_test() {
  let settings =
    config.Config(
      ..config.default(),
      public_url: option.Some("https://drop.example"),
      tunnel: True,
      pin: option.Some("family-owl-72"),
    )
  let invite = option.Some("https://drop.example/i/fresh-token")

  let local_html =
    view.home(settings, [], "csrf-test", "nonce-test", invite, True)
  string.contains(local_html, "action='/invite/regenerate'")
  |> should.be_true
  string.contains(local_html, "Existing sessions stay connected")
  |> should.be_true

  let visitor_html =
    view.home(settings, [], "csrf-test", "nonce-test", invite, False)
  string.contains(visitor_html, "action='/invite/regenerate'")
  |> should.be_false
}

pub fn fixed_window_rate_limit_test() {
  security.setup()

  security.rate_limit("test-rate-limit", 2, 60)
  |> should.be_true
  security.rate_limit("test-rate-limit", 2, 60)
  |> should.be_true
  security.rate_limit("test-rate-limit", 2, 60)
  |> should.be_false
}

pub fn filenames_are_safe_for_download_headers_test() {
  storage.safe_title("../../bad\r\n\"name.txt")
  |> should.equal(".._.._bad  'name.txt")
}

pub fn total_storage_limit_fails_closed_test() {
  let settings =
    config.Config(
      ..config.default(),
      data_dir: "./build/dropnest-quota-test-data",
      receive_dir: "./build/dropnest-quota-test-files",
      max_upload_bytes: 10,
      max_storage_bytes: 4,
    )
  let fixture = "./build/dropnest-quota-fixture.txt"
  let assert Ok(_) = simplifile.write(to: fixture, contents: "12345")
  let assert Ok(_) = storage.setup(settings)

  storage.add_existing_file(settings, fixture)
  |> should.equal(
    Error(storage.StorageError(
      message: "The DropNest storage limit has been reached. Delete or expire a file before uploading another.",
    )),
  )

  storage.all(settings)
  |> should.equal([])
}
