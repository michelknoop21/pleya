import 'dart:io';

/// Deletes a test's temporary folder while a store write of a provider may
/// still be running. That write can sit on a fake-time timer, so awaiting it
/// inside `tester.runAsync` hangs; deleting the folder under it fails now and
/// then instead. Call it inside `runAsync`: it retries a few times in real time
/// and rethrows the last error.
Future<void> deleteTempDir(Directory root) async {
  for (var attempt = 0; ; attempt++) {
    try {
      if (await root.exists()) await root.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
