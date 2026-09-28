enum DeviceError {
  invalidUrl,
  unauthorized,
  unreachable,
  timeout,
  malformed,
  unavailable,
  server,
  storage,
}

class DeviceException implements Exception {
  const DeviceException(this.kind, this.message);
  final DeviceError kind;
  final String message;
  @override
  String toString() => message;
}

String userMessage(Object error) => error is DeviceException
    ? error.message
    : 'Something went wrong. Please try again.';
