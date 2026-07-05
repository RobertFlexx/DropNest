import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile

pub const default_port = 7070

pub const default_host = "127.0.0.1"

pub const lan_host = "0.0.0.0"

pub const default_data_dir = "./data"

pub const default_receive_dir = "./DropNestDrops"

pub const default_max_upload_bytes = 104_857_600

pub const default_expiration_minutes = 1440

pub type Config {
  Config(
    host: String,
    port: Int,
    lan: Bool,
    pin: Option(String),
    data_dir: String,
    receive_dir: String,
    max_upload_bytes: Int,
    default_expiration_minutes: Int,
    host_was_set: Bool,
  )
}

pub type Parsed {
  Run(Config)
  SendText(Config, String)
  SendFile(Config, String)
  ShowHelp
  ParseError(String)
}

pub fn from_args(args: List(String)) -> Parsed {
  parse(args, load_config(default()))
}

pub fn help_text() -> String {
  "DropNest - private LAN file and clipboard drop\n\nUsage:\n  dropnest serve [options]\n  dropnest send-text <text> [options]\n  dropnest send <path> [options]\n  dropnest help\n\nCommands:\n  serve                  Start DropNest\n  send-text <text>       Add a text drop without starting the server\n  send <path>            Add a local file drop without starting the server\n\nOptions:\n  --config <path>        Read defaults from a config file\n  --lan                  Allow other devices on your Wi-Fi to connect\n  --pin <pin>            Require a PIN in LAN mode\n  --dir <path>           Directory where uploaded files are saved\n  --data-dir <path>      Directory where metadata is stored\n  --host <host>          Host to bind in LAN mode\n  --port <port>          Port to serve on\n  --max-upload-mb <mb>   Maximum accepted upload size\n  --expires <minutes>    Default drop lifetime. Use 0 for never.\n  --help                 Show this help\n\nConfig file:\n  DropNest reads ./dropnest.conf when it exists, or the path passed with --config.\n  Use key=value lines such as lan=true, pin=1234, dir=/tmp/DropNest.\n"
}

pub fn bind_address(config: Config) -> String {
  case config.lan {
    True -> config.host
    False -> default_host
  }
}

pub fn default_expiration_seconds(config: Config) -> Int {
  expiration_seconds(config.default_expiration_minutes)
}

pub fn expiration_seconds(minutes: Int) -> Int {
  case minutes <= 0 {
    True -> 0
    False -> minutes * 60
  }
}

pub fn metadata_path(config: Config) -> String {
  join_path(config.data_dir, "metadata.json")
}

pub fn validate_receive_dir(path: String) -> Result(Nil, String) {
  let clean = string.trim(path)

  case clean {
    "" -> Error("Receive directory cannot be empty.")
    "/" ->
      Error("Refusing to use the filesystem root as the receive directory.")
    "." ->
      Error(
        "Refusing to use the current directory as the receive directory. Choose a dedicated folder.",
      )
    ".." -> Error("Refusing to use '..' as the receive directory.")
    _ ->
      case string.starts_with(clean, "~") {
        True ->
          Error(
            "The receive directory starts with '~'. Pass it unquoted so your shell expands it, or use an absolute path.",
          )
        False -> Ok(Nil)
      }
  }
}

pub fn default() -> Config {
  Config(
    host: default_host,
    port: default_port,
    lan: False,
    pin: None,
    data_dir: default_data_dir,
    receive_dir: default_receive_dir,
    max_upload_bytes: default_max_upload_bytes,
    default_expiration_minutes: default_expiration_minutes,
    host_was_set: False,
  )
}

fn join_path(directory: String, file: String) -> String {
  case string.ends_with(directory, "/") {
    True -> directory <> file
    False -> directory <> "/" <> file
  }
}

fn parse(args: List(String), config: Config) -> Parsed {
  case args {
    [] -> Run(config)
    ["help"] -> ShowHelp
    ["--help"] -> ShowHelp
    ["serve", "--help", ..] -> ShowHelp
    ["serve", ..rest] -> parse(rest, config)
    ["send-text"] -> ParseError("Missing text after send-text")
    ["send-text", text, ..rest] -> parse_send_text(rest, config, text)
    ["send"] -> ParseError("Missing path after send")
    ["send", path, ..rest] -> parse_send_file(rest, config, path)
    ["--config"] -> ParseError("Missing value after --config")
    ["--config", path, ..rest] -> parse(rest, load_config_from(config, path))
    ["--lan", ..rest] -> {
      let host = case config.host_was_set {
        True -> config.host
        False -> lan_host
      }
      parse(rest, Config(..config, lan: True, host: host))
    }
    ["--host"] -> ParseError("Missing value after --host")
    ["--host", host, ..rest] ->
      parse(rest, Config(..config, host: host, host_was_set: True))
    ["--pin"] -> ParseError("Missing value after --pin")
    ["--pin", pin, ..rest] -> parse(rest, Config(..config, pin: Some(pin)))
    ["--dir"] -> ParseError("Missing value after --dir")
    ["--dir", path, ..rest] -> parse(rest, Config(..config, receive_dir: path))
    ["--data-dir"] -> ParseError("Missing value after --data-dir")
    ["--data-dir", path, ..rest] ->
      parse(rest, Config(..config, data_dir: path))
    ["--max-upload-mb"] -> ParseError("Missing value after --max-upload-mb")
    ["--max-upload-mb", size, ..rest] -> {
      let bytes = case int.parse(size) {
        Ok(value) if value > 0 -> value * 1024 * 1024
        _ -> 0
      }
      case bytes > 0 {
        True -> parse(rest, Config(..config, max_upload_bytes: bytes))
        False -> ParseError("Invalid value for --max-upload-mb: " <> size)
      }
    }
    ["--expires"] -> ParseError("Missing value after --expires")
    ["--expires", minutes, ..rest] -> {
      case parse_minutes(minutes) {
        Ok(value) ->
          parse(rest, Config(..config, default_expiration_minutes: value))
        Error(_) -> ParseError("Invalid value for --expires: " <> minutes)
      }
    }
    ["--port"] -> ParseError("Missing value after --port")
    ["--port", port, ..rest] -> {
      case int.parse(port) {
        Ok(value) if value > 0 -> parse(rest, Config(..config, port: value))
        _ -> ParseError("Invalid value for --port: " <> port)
      }
    }
    [unknown, ..] -> ParseError("Unknown option: " <> unknown)
  }
}

fn parse_send_text(args: List(String), config: Config, text: String) -> Parsed {
  case parse(args, config) {
    Run(config) -> SendText(config, text)
    other -> other
  }
}

fn parse_send_file(args: List(String), config: Config, path: String) -> Parsed {
  case parse(args, config) {
    Run(config) -> SendFile(config, path)
    other -> other
  }
}

fn load_config(config: Config) -> Config {
  load_config_from(config, "./dropnest.conf")
}

fn load_config_from(config: Config, path: String) -> Config {
  case simplifile.read(from: path) {
    Ok(contents) -> apply_config_lines(config, string.split(contents, on: "\n"))
    Error(_) -> config
  }
}

fn apply_config_lines(config: Config, lines: List(String)) -> Config {
  list.fold(lines, config, fn(current, line) {
    apply_config_line(current, line)
  })
}

fn apply_config_line(config: Config, line: String) -> Config {
  let clean = line |> string.trim
  case clean == "" || string.starts_with(clean, "#") {
    True -> config
    False -> {
      case string.split_once(clean, on: "=") {
        Ok(#(key, value)) ->
          apply_config_value(config, string.trim(key), string.trim(value))
        Error(_) -> config
      }
    }
  }
}

fn apply_config_value(config: Config, key: String, value: String) -> Config {
  case key {
    "lan" ->
      case bool_value(value) {
        True -> Config(..config, lan: True, host: lan_config_host(config))
        False -> Config(..config, lan: False)
      }
    "pin" ->
      case value {
        "" -> Config(..config, pin: None)
        _ -> Config(..config, pin: Some(value))
      }
    "dir" -> Config(..config, receive_dir: value)
    "receive_dir" -> Config(..config, receive_dir: value)
    "data_dir" -> Config(..config, data_dir: value)
    "host" -> Config(..config, host: value, host_was_set: True)
    "port" ->
      case int.parse(value) {
        Ok(port) if port > 0 -> Config(..config, port: port)
        _ -> config
      }
    "max_upload_mb" ->
      case int.parse(value) {
        Ok(mb) if mb > 0 -> Config(..config, max_upload_bytes: mb * 1024 * 1024)
        _ -> config
      }
    "expires" ->
      case parse_minutes(value) {
        Ok(minutes) -> Config(..config, default_expiration_minutes: minutes)
        Error(_) -> config
      }
    _ -> config
  }
}

fn lan_config_host(config: Config) -> String {
  case config.host_was_set {
    True -> config.host
    False -> lan_host
  }
}

fn bool_value(value: String) -> Bool {
  case string.lowercase(value) {
    "1" -> True
    "true" -> True
    "yes" -> True
    "on" -> True
    _ -> False
  }
}

fn parse_minutes(value: String) -> Result(Int, Nil) {
  case int.parse(value) {
    Ok(minutes) if minutes >= 0 -> Ok(minutes)
    _ -> Error(Nil)
  }
}
