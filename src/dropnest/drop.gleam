import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}

pub type Kind {
  File
  Text
}

pub type Drop {
  Drop(
    id: String,
    kind: Kind,
    title: String,
    original_filename: Option(String),
    stored_filename: Option(String),
    mime_type: Option(String),
    size_bytes: Option(Int),
    checksum_sha256: Option(String),
    text_content: Option(String),
    created_at: Int,
    expires_at: Int,
  )
}

pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    File -> "file"
    Text -> "text"
  }
}

pub fn kind_from_string(kind: String) -> Kind {
  case kind {
    "file" -> File
    _ -> Text
  }
}

pub fn encode_all(drops: List(Drop)) -> String {
  json.array(drops, of: encode)
  |> json.to_string
}

pub fn decode_all(input: String) -> List(Drop) {
  case decode_result(input) {
    Ok(drops) -> drops
    Error(_) -> []
  }
}

pub fn decode_result(input: String) -> Result(List(Drop), Nil) {
  case json.parse(input, using: decode.list(of: decoder())) {
    Ok(drops) -> Ok(drops)
    Error(_) -> Error(Nil)
  }
}

pub fn encode(item: Drop) -> json.Json {
  json.object([
    #("id", json.string(item.id)),
    #("kind", json.string(kind_to_string(item.kind))),
    #("title", json.string(item.title)),
    #("original_filename", optional_string(item.original_filename)),
    #("stored_filename", optional_string(item.stored_filename)),
    #("mime_type", optional_string(item.mime_type)),
    #("size_bytes", optional_int(item.size_bytes)),
    #("checksum_sha256", optional_string(item.checksum_sha256)),
    #("text_content", optional_string(item.text_content)),
    #("created_at", json.int(item.created_at)),
    #("expires_at", json.int(item.expires_at)),
  ])
}

fn decoder() -> decode.Decoder(Drop) {
  use id <- decode.field("id", decode.string)
  use kind <- decode.field("kind", decode.string)
  use title <- decode.field("title", decode.string)
  use original_filename <- decode.optional_field(
    "original_filename",
    None,
    decode.optional(decode.string),
  )
  use stored_filename <- decode.optional_field(
    "stored_filename",
    None,
    decode.optional(decode.string),
  )
  use mime_type <- decode.optional_field(
    "mime_type",
    None,
    decode.optional(decode.string),
  )
  use size_bytes <- decode.optional_field(
    "size_bytes",
    None,
    decode.optional(decode.int),
  )
  use checksum_sha256 <- decode.optional_field(
    "checksum_sha256",
    None,
    decode.optional(decode.string),
  )
  use text_content <- decode.optional_field(
    "text_content",
    None,
    decode.optional(decode.string),
  )
  use created_at <- decode.field("created_at", decode.int)
  use expires_at <- decode.field("expires_at", decode.int)
  decode.success(Drop(
    id:,
    kind: kind_from_string(kind),
    title:,
    original_filename:,
    stored_filename:,
    mime_type:,
    size_bytes:,
    checksum_sha256:,
    text_content:,
    created_at:,
    expires_at:,
  ))
}

fn optional_string(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn optional_int(value: Option(Int)) -> json.Json {
  case value {
    Some(value) -> json.int(value)
    None -> json.null()
  }
}
