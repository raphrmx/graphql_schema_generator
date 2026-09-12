/// What a console message is, which decides its colour.
enum MessageType {
  /// Ordinary output.
  normal,

  /// A detail of what the run did.
  info,

  /// Something the run handled, and the reader should know about.
  warning,

  /// Something the run could not do.
  error,

  /// The run finished.
  success,
}
