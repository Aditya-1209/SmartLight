enum HaError {
  invalidUrl,
  unauthorized,
  unreachable,
  timeout,
  malformed,
  unavailable,
  server,
  storage,
}

class HaException implements Exception {
  const HaException(this.kind, this.message);
  final HaError kind;
  final String message;
  @override
  String toString() => message;
}

String userMessage(Object error) => error is HaException
    ? error.message
    : 'Something went wrong. Please try again.';
