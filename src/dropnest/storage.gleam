import birl
import dropnest/config as app_config
import dropnest/drop.{type Drop, File, Text}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import wisp

@external(erlang, "dropnest_ffi", "sha256_text")
fn sha256_text(value: String) -> String

@external(erlang, "dropnest_ffi", "sha256_file")
fn sha256_file(path: String) -> Result(String, Nil)

@external(erlang, "dropnest_ffi", "make_private")
fn make_private(path: String, directory: Bool) -> Nil

@external(erlang, "dropnest_ffi", "storage_transaction")
fn storage_transaction(action: fn() -> a) -> a

@external(erlang, "dropnest_ffi", "sanitize_filename")
fn sanitize_filename(value: String) -> String

const max_text_bytes = 200_000

const max_drop_count = 5000

pub type StorageError {
  StorageError(message: String)
}

pub fn setup(config: app_config.Config) -> Result(Nil, StorageError) {
  use _ <- result.try(validate_directory(config.receive_dir))
  use _ <- result.try(create_directory(config.data_dir, "data directory"))
  use _ <- result.try(create_directory(config.receive_dir, "receive directory"))
  make_private(config.data_dir, True)
  make_private(config.receive_dir, True)

  case simplifile.read(from: app_config.metadata_path(config)) {
    Ok(contents) ->
      case drop.decode_result(contents) {
        Ok(_) -> {
          make_private(app_config.metadata_path(config), False)
          Ok(Nil)
        }
        Error(_) -> backup_corrupt_metadata(config, contents)
      }
    Error(_) -> {
      case
        simplifile.write(to: app_config.metadata_path(config), contents: "[]\n")
      {
        Ok(_) -> {
          make_private(app_config.metadata_path(config), False)
          Ok(Nil)
        }
        Error(error) ->
          Error(StorageError(
            message: "Could not create metadata file: "
            <> simplifile.describe_error(error),
          ))
      }
    }
  }
}

pub fn now_seconds() -> Int {
  birl.utc_now() |> birl.to_unix
}

pub fn all(config: app_config.Config) -> List(Drop) {
  case simplifile.read(from: app_config.metadata_path(config)) {
    Ok(contents) -> drop.decode_all(contents)
    Error(_) -> []
  }
}

pub fn save(
  config: app_config.Config,
  drops: List(Drop),
) -> Result(Nil, StorageError) {
  let metadata_path = app_config.metadata_path(config)
  let temporary_path = metadata_path <> ".tmp"
  let contents = drop.encode_all(drops) <> "\n"

  case simplifile.write(to: temporary_path, contents: contents) {
    Ok(_) ->
      case simplifile.rename(at: temporary_path, to: metadata_path) {
        Ok(_) -> {
          make_private(metadata_path, False)
          Ok(Nil)
        }
        Error(error) ->
          Error(StorageError(
            message: "Could not replace metadata: "
            <> simplifile.describe_error(error),
          ))
      }
    Error(error) ->
      Error(StorageError(
        message: "Could not write metadata: "
        <> simplifile.describe_error(error),
      ))
  }
}

pub fn add_text(
  config: app_config.Config,
  content: String,
) -> Result(Nil, StorageError) {
  add_text_with_expiration(config, content, config.default_expiration_minutes)
}

pub fn add_text_with_expiration(
  config: app_config.Config,
  content: String,
  expires_minutes: Int,
) -> Result(Nil, StorageError) {
  storage_transaction(fn() {
    add_text_unlocked(config, content, expires_minutes)
  })
}

fn add_text_unlocked(
  config: app_config.Config,
  content: String,
  expires_minutes: Int,
) -> Result(Nil, StorageError) {
  let clean = string.trim(content)
  let size = string.byte_size(clean)
  case clean == "", size > max_text_bytes {
    True, _ ->
      Error(StorageError(message: "Paste some text before sending a text drop."))
    _, True -> Error(StorageError(message: "Text drops are limited to 200 KB."))
    False, False -> {
      let drops = all(config)
      use _ <- result.try(ensure_drop_capacity(drops))
      let now = now_seconds()
      let item =
        drop.Drop(
          id: safe_id(),
          kind: Text,
          title: text_title(clean),
          original_filename: None,
          stored_filename: None,
          mime_type: Some("text/plain"),
          size_bytes: Some(size),
          checksum_sha256: Some(sha256_text(clean)),
          text_content: Some(clean),
          created_at: now,
          expires_at: expires_at(now, expires_minutes),
        )
      save(config, [item, ..drops])
    }
  }
}

pub fn add_file(
  config: app_config.Config,
  temp_path: String,
  original_filename: String,
) -> Result(Nil, StorageError) {
  add_file_with_expiration(
    config,
    temp_path,
    original_filename,
    config.default_expiration_minutes,
  )
}

pub fn add_existing_file(
  config: app_config.Config,
  path: String,
) -> Result(Nil, StorageError) {
  let filename = path |> basename |> safe_title
  add_file(config, path, filename)
}

pub fn add_file_with_expiration(
  config: app_config.Config,
  temp_path: String,
  original_filename: String,
  expires_minutes: Int,
) -> Result(Nil, StorageError) {
  storage_transaction(fn() {
    add_file_unlocked(config, temp_path, original_filename, expires_minutes)
  })
}

fn add_file_unlocked(
  config: app_config.Config,
  temp_path: String,
  original_filename: String,
  expires_minutes: Int,
) -> Result(Nil, StorageError) {
  let id = safe_id()
  let destination = drop_path(config, id)
  case simplifile.copy_file(at: temp_path, to: destination) {
    Ok(_) -> {
      make_private(destination, False)
      let size = case simplifile.file_info(destination) {
        Ok(info) -> info.size
        Error(_) -> 0
      }

      let drops = all(config)
      let over_storage_limit =
        stored_file_bytes(drops) + size > config.max_storage_bytes
      case size <= 0, size > config.max_upload_bytes, over_storage_limit {
        True, _, _ -> {
          let _ = simplifile.delete_file(at: destination)
          Error(StorageError(message: "Choose a non-empty file and try again."))
        }
        _, True, _ -> {
          let _ = simplifile.delete_file(at: destination)
          Error(StorageError(message: "That file exceeds the upload limit."))
        }
        _, _, True -> {
          let _ = simplifile.delete_file(at: destination)
          Error(StorageError(
            message: "The DropNest storage limit has been reached. Delete or expire a file before uploading another.",
          ))
        }
        False, False, False ->
          case ensure_drop_capacity(drops) {
            Error(error) -> {
              let _ = simplifile.delete_file(at: destination)
              Error(error)
            }
            Ok(_) ->
              case sha256_file(destination) {
                Ok(checksum) -> {
                  let now = now_seconds()
                  let safe_name = safe_title(original_filename)
                  let item =
                    drop.Drop(
                      id:,
                      kind: File,
                      title: safe_name,
                      original_filename: Some(safe_name),
                      stored_filename: Some(id),
                      mime_type: Some("application/octet-stream"),
                      size_bytes: Some(size),
                      checksum_sha256: Some(checksum),
                      text_content: None,
                      created_at: now,
                      expires_at: expires_at(now, expires_minutes),
                    )
                  case save(config, [item, ..drops]) {
                    Ok(_) -> Ok(Nil)
                    Error(error) -> {
                      let _ = simplifile.delete_file(at: destination)
                      Error(error)
                    }
                  }
                }
                Error(_) -> {
                  let _ = simplifile.delete_file(at: destination)
                  Error(StorageError(
                    message: "Could not calculate the uploaded file's SHA-256 checksum.",
                  ))
                }
              }
          }
      }
    }
    Error(error) ->
      Error(StorageError(
        message: "Could not save uploaded file: "
        <> simplifile.describe_error(error),
      ))
  }
}

pub fn find(config: app_config.Config, id: String) -> Result(Drop, Nil) {
  all(config)
  |> list.find(fn(item) { item.id == id })
}

pub fn file_is_intact(config: app_config.Config, item: Drop) -> Bool {
  case item.kind, item.checksum_sha256, valid_id(item.id) {
    File, Some(expected), True ->
      sha256_file(drop_path(config, item.id)) == Ok(expected)
    File, None, True -> True
    _, _, _ -> False
  }
}

pub fn delete(
  config: app_config.Config,
  id: String,
) -> Result(Nil, StorageError) {
  storage_transaction(fn() { delete_unlocked(config, id) })
}

fn delete_unlocked(
  config: app_config.Config,
  id: String,
) -> Result(Nil, StorageError) {
  let drops = all(config)
  let remaining = list.filter(drops, fn(item) { item.id != id })
  case valid_id(id) {
    True -> {
      let _ = simplifile.delete_file(at: drop_path(config, id))
      Nil
    }
    False -> Nil
  }
  save(config, remaining)
}

pub fn clean_expired(config: app_config.Config) -> Result(Nil, StorageError) {
  storage_transaction(fn() { clean_expired_unlocked(config) })
}

fn clean_expired_unlocked(
  config: app_config.Config,
) -> Result(Nil, StorageError) {
  let now = now_seconds()
  let drops = all(config)
  let active_drops = list.filter(drops, fn(item) { active(item, now) })
  drops
  |> list.filter(fn(item) { !active(item, now) })
  |> list.each(fn(item) {
    case item.kind, item.stored_filename, valid_id(item.id) {
      File, Some(_), True -> {
        let _ = simplifile.delete_file(at: drop_path(config, item.id))
        Nil
      }
      _, _, _ -> Nil
    }
  })
  case list.length(active_drops) == list.length(drops) {
    True -> Ok(Nil)
    False -> save(config, active_drops)
  }
}

fn ensure_drop_capacity(drops: List(Drop)) -> Result(Nil, StorageError) {
  case list.length(drops) < max_drop_count {
    True -> Ok(Nil)
    False ->
      Error(StorageError(
        message: "DropNest has reached its 5,000-drop safety limit. Delete or expire an older drop first.",
      ))
  }
}

pub fn stored_file_bytes(drops: List(Drop)) -> Int {
  list.fold(drops, 0, fn(total, item) {
    case item.kind, item.size_bytes {
      File, Some(size) -> total + size
      _, _ -> total
    }
  })
}

fn active(item: Drop, now: Int) -> Bool {
  item.expires_at == 0 || item.expires_at > now
}

fn expires_at(now: Int, minutes: Int) -> Int {
  let seconds = app_config.expiration_seconds(minutes)
  case seconds <= 0 {
    True -> 0
    False -> now + seconds
  }
}

pub fn drop_path(config: app_config.Config, id: String) -> String {
  join_path(config.receive_dir, id)
}

pub fn valid_id(id: String) -> Bool {
  string.length(id) == 32
  && list.all(string.to_graphemes(id), fn(char) {
    list.contains(hex_graphemes(), any: char)
  })
}

fn hex_graphemes() -> List(String) {
  [
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
  ]
}

pub fn safe_title(filename: String) -> String {
  let cleaned =
    filename
    |> sanitize_filename
    |> string.trim
    |> string.slice(at_index: 0, length: 180)

  case cleaned {
    "" -> "Untitled"
    _ -> cleaned
  }
}

fn safe_id() -> String {
  wisp.random_string(48)
  |> string.lowercase
  |> string.replace(each: "-", with: "")
  |> string.replace(each: "_", with: "")
  |> string.slice(at_index: 0, length: 32)
}

fn text_title(content: String) -> String {
  content
  |> string.split(on: "\n")
  |> list.first
  |> result.unwrap("Text drop")
  |> string.trim
  |> string.slice(at_index: 0, length: 80)
}

fn basename(path: String) -> String {
  path
  |> string.replace(each: "\\", with: "/")
  |> string.split(on: "/")
  |> list.reverse
  |> list.first
  |> result.unwrap("Untitled")
}

fn validate_directory(path: String) -> Result(Nil, StorageError) {
  case app_config.validate_receive_dir(path) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(StorageError(message: message))
  }
}

fn create_directory(path: String, label: String) -> Result(Nil, StorageError) {
  case simplifile.create_directory_all(path) {
    Ok(_) -> Ok(Nil)
    Error(error) ->
      Error(StorageError(
        message: "Could not create "
        <> label
        <> ": "
        <> simplifile.describe_error(error),
      ))
  }
}

fn backup_corrupt_metadata(
  config: app_config.Config,
  contents: String,
) -> Result(Nil, StorageError) {
  let backup =
    join_path(
      config.data_dir,
      "metadata.corrupt." <> int_string(now_seconds()) <> ".json",
    )
  case simplifile.write(to: backup, contents: contents) {
    Ok(_) ->
      case
        simplifile.write(to: app_config.metadata_path(config), contents: "[]\n")
      {
        Ok(_) -> {
          make_private(app_config.metadata_path(config), False)
          Ok(Nil)
        }
        Error(error) ->
          Error(StorageError(
            message: "Metadata is corrupt and could not be reset: "
            <> simplifile.describe_error(error),
          ))
      }
    Error(error) ->
      Error(StorageError(
        message: "Metadata is corrupt and could not be backed up: "
        <> simplifile.describe_error(error),
      ))
  }
}

fn int_string(value: Int) -> String {
  int.to_string(value)
}

fn join_path(directory: String, file: String) -> String {
  case string.ends_with(directory, "/") {
    True -> directory <> file
    False -> directory <> "/" <> file
  }
}
