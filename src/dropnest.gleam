import argv
import dropnest/config
import dropnest/server
import dropnest/storage
import gleam/io

pub fn main() {
  case argv.load().arguments |> config.from_args {
    config.Run(settings) -> server.start(settings)
    config.SendText(settings, text) -> send_text(settings, text)
    config.SendFile(settings, path) -> send_file(settings, path)
    config.ShowHelp -> io.println(config.help_text())
    config.ParseError(message) -> {
      io.println(message <> "\n\nRun:\n  gleam run -- help")
    }
  }
}

fn send_text(settings: config.Config, text: String) -> Nil {
  case storage.setup(settings) {
    Ok(_) ->
      case storage.add_text(settings, text) {
        Ok(_) -> io.println("Text drop added.")
        Error(storage.StorageError(message: message)) -> io.println(message)
      }
    Error(storage.StorageError(message: message)) -> io.println(message)
  }
}

fn send_file(settings: config.Config, path: String) -> Nil {
  case storage.setup(settings) {
    Ok(_) ->
      case storage.add_existing_file(settings, path) {
        Ok(_) -> io.println("File drop added.")
        Error(storage.StorageError(message: message)) -> io.println(message)
      }
    Error(storage.StorageError(message: message)) -> io.println(message)
  }
}
