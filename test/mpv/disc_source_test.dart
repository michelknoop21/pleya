import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/disc_source.dart';

/// Pretends the given paths are directories, so the rules can be exercised
/// without laying down a fake Blu-ray on disk.
bool Function(String) dirs(Set<String> present) => present.contains;

DiscSource? detect(String path, {Set<String> present = const {}}) =>
    detectDiscSource(path, directoryExists: dirs(present));

void main() {
  group('disc images', () {
    test('an .iso is handed to libbluray as a device, not opened as a file', () {
      final source = detect('/Volumes/NAS/Movies/Heat (1995).iso');

      expect(source, isNotNull);
      expect(source!.kind, DiscKind.bluray);
      expect(source.devicePath, '/Volumes/NAS/Movies/Heat (1995).iso');
      expect(source.mpvUri, 'bd://longest');
    });

    test('the extension check ignores case', () {
      expect(detect('/m/Film.ISO')?.kind, DiscKind.bluray);
      expect(detect('/m/Film.IsO')?.kind, DiscKind.bluray);
    });

    test('a file:// URL is reduced to a plain path, which is what libbluray opens', () {
      expect(detect('file:///Volumes/NAS/Heat.iso')?.devicePath, '/Volumes/NAS/Heat.iso');
    });

    test('spaces and brackets survive', () {
      final source = detect('/Volumes/My Disk/Films/The Thing [1982].iso');
      expect(source?.devicePath, '/Volumes/My Disk/Films/The Thing [1982].iso');
    });
  });

  group('unpacked disc folders', () {
    test('a folder holding BDMV is the device', () {
      final source = detect('/mnt/bd/Heat', present: {'/mnt/bd/Heat/BDMV'});

      expect(source?.kind, DiscKind.bluray);
      expect(source?.devicePath, '/mnt/bd/Heat');
    });

    test('picking BDMV itself resolves to its parent', () {
      // mpv wants the disc root, not the structure folder.
      final source = detect('/mnt/bd/Heat/BDMV');

      expect(source?.kind, DiscKind.bluray);
      expect(source?.devicePath, '/mnt/bd/Heat');
    });

    test('a trailing separator does not change the answer', () {
      expect(detect('/mnt/bd/Heat/BDMV/')?.devicePath, '/mnt/bd/Heat');
      expect(detect('/mnt/bd/Heat/', present: {'/mnt/bd/Heat/BDMV'})?.devicePath, '/mnt/bd/Heat');
    });
  });

  group('DVD', () {
    test('VIDEO_TS is recognised so it can be refused with a real message', () {
      // Detected rather than ignored: falling through would hand mpv a folder
      // and surface "corrupt stream" instead of "DVDs are not supported here".
      expect(detect('/mnt/dvd/Alien/VIDEO_TS')?.kind, DiscKind.dvd);
      expect(detect('/mnt/dvd/Alien', present: {'/mnt/dvd/Alien/VIDEO_TS'})?.kind, DiscKind.dvd);
    });

    test('resolves to the disc root and the dvdnav URL', () {
      final source = detect('/mnt/dvd/Alien/VIDEO_TS');

      expect(source?.devicePath, '/mnt/dvd/Alien');
      expect(source?.mpvUri, 'dvdnav://');
    });
  });

  group('ordinary media is left completely alone', () {
    test('regular files are not discs', () {
      // The whole risk of hooking into open() is catching something it
      // shouldn't; every one of these must stay null.
      for (final path in [
        '/movies/Heat.mkv',
        '/movies/Heat.mp4',
        '/movies/Heat.m2ts',
        '/movies/isotope.mkv',
        '/movies/my.iso.backup.mkv',
        'https://server/library/parts/1/file.mkv',
        '/movies/plain-folder',
      ]) {
        expect(detect(path), isNull, reason: path);
      }
    });

    test('an empty path is not a disc', () {
      expect(detect(''), isNull);
      expect(detect('/'), isNull);
    });
  });
}
