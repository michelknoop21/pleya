import 'dart:io';

/// One shared media root ("library") with the same layout conventions as the
/// app's local folder scanner (`lib/services/local_folder_client.dart`):
/// movies = `<root>/Movie (2024)/movie.mkv` or loose files; tvshows =
/// `<root>/Show/Season 1/S01E01.mkv`; mixed = recursive movie scan.
class MediaRoot {
  final String id;
  final String path;
  final String name;

  /// 'movies' | 'tvshows' | 'mixed'
  final String type;

  const MediaRoot({required this.id, required this.path, required this.name, required this.type});
}

const _videoExtensions = {
  '.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v', '.ts', '.m2ts', //
  '.wmv', '.flv', '.mpg', '.mpeg', '.vob', '.3gp', '.ogv',
};

final _moviePattern = RegExp(r'^(.+?)[\s._]*\((\d{4})\)|^(.+?)[\s._]+(\d{4})\b');
final _episodePattern = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');

/// Scans [root] into MediaItem-compatible JSON maps (the app's
/// `MediaItem.fromJson` wire format, backend 'local').
class LibraryScanner {
  final MediaRoot root;

  LibraryScanner(this.root);

  List<Map<String, Object?>> scan() {
    final dir = Directory(root.path);
    if (!dir.existsSync()) {
      stderr.writeln('media root does not exist: ${root.path}');
      return [];
    }
    final items = <Map<String, Object?>>[];
    for (final entity in dir.listSync(followLinks: true)) {
      if (entity is Directory) {
        switch (root.type) {
          case 'movies':
            _scanMovieFolder(entity, items);
          case 'tvshows':
            _scanShowFolder(entity, items);
          default:
            _scanGenericFolder(entity, items);
        }
      } else if (entity is File && _isVideo(entity.path)) {
        items.add(_movieItem(entity));
      }
    }
    return items;
  }

  void _scanMovieFolder(Directory folder, List<Map<String, Object?>> items) {
    for (final entity in folder.listSync(followLinks: true)) {
      if (entity is File && _isVideo(entity.path)) items.add(_movieItem(entity));
    }
  }

  void _scanGenericFolder(Directory folder, List<Map<String, Object?>> items) {
    for (final entity in folder.listSync(followLinks: true)) {
      if (entity is File && _isVideo(entity.path)) {
        items.add(_movieItem(entity));
      } else if (entity is Directory) {
        _scanGenericFolder(entity, items);
      }
    }
  }

  void _scanShowFolder(Directory showDir, List<Map<String, Object?>> items) {
    final showName = _basename(showDir.path);
    var seasonCount = 0;
    var episodeTotal = 0;
    final showJson = _base(showDir.path, 'show', _cleanName(showName));
    items.add(showJson);

    var seasonNum = 0;
    for (final seasonEntity in showDir.listSync(followLinks: true)) {
      if (seasonEntity is! Directory) continue;
      seasonNum++;
      seasonCount++;
      final seasonName = _basename(seasonEntity.path);
      final seasonIndex = _parseSeasonNumber(seasonName) ?? seasonNum;
      final seasonJson = _base(seasonEntity.path, 'season', seasonName)
        ..['parentId'] = showDir.path
        ..['parentTitle'] = showName
        ..['index'] = seasonIndex;
      items.add(seasonJson);

      var epNum = 0;
      for (final epEntity in seasonEntity.listSync(followLinks: true)) {
        if (epEntity is! File || !_isVideo(epEntity.path)) continue;
        epNum++;
        episodeTotal++;
        final epName = _basename(epEntity.path);
        final parsed = _episodePattern.firstMatch(epName);
        items.add(
          _base(epEntity.path, 'episode', _cleanName(epName))
            ..['parentId'] = seasonEntity.path
            ..['parentTitle'] = seasonName
            ..['parentIndex'] = seasonIndex
            ..['grandparentId'] = showDir.path
            ..['grandparentTitle'] = showName
            ..['index'] = parsed != null ? int.tryParse(parsed.group(2)!) ?? epNum : epNum
            ..['mediaVersions'] = [_version(epEntity)],
        );
      }
      seasonJson['leafCount'] = epNum;
    }
    showJson['childCount'] = seasonCount;
    showJson['leafCount'] = episodeTotal;
  }

  Map<String, Object?> _movieItem(File file) {
    final fileName = _basename(file.path);
    final match = _moviePattern.firstMatch(fileName);
    String title;
    int? year;
    if (match != null && match.group(1) != null) {
      title = _cleanName(match.group(1)!);
      year = int.tryParse(match.group(2)!);
    } else if (match != null && match.group(3) != null) {
      title = _cleanName(match.group(3)!);
      year = int.tryParse(match.group(4)!);
    } else {
      title = _cleanName(fileName);
    }
    return _base(file.path, 'movie', title)
      ..['year'] = year
      ..['mediaVersions'] = [_version(file)];
  }

  Map<String, Object?> _base(String id, String kind, String title) => {
    'backend': 'local',
    'id': id,
    'kind': kind,
    'title': title,
    'libraryId': root.id,
    'libraryTitle': root.name,
    'serverId': root.id,
    'serverName': root.name,
    'addedAt': _addedAt(id),
  };

  Map<String, Object?> _version(File file) {
    final container = _extension(file.path);
    int? size;
    try {
      size = file.lengthSync();
    } catch (_) {}
    return {
      'id': file.path,
      'container': container,
      'parts': [
        {'id': file.path, 'streamPath': file.path, 'sizeBytes': size, 'container': container},
      ],
    };
  }

  int _addedAt(String path) {
    try {
      return FileSystemEntity.isDirectorySync(path)
          ? Directory(path).statSync().modified.millisecondsSinceEpoch ~/ 1000
          : File(path).statSync().modified.millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return 0;
    }
  }

  bool _isVideo(String path) => _videoExtensions.contains('.${_extension(path)}');

  String _extension(String path) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  String _basename(String path) => path.split(Platform.pathSeparator).last;

  String _cleanName(String name) {
    var cleaned = name;
    final dot = cleaned.lastIndexOf('.');
    if (dot >= 0) cleaned = cleaned.substring(0, dot);
    cleaned = cleaned.replaceAll('.', ' ').replaceAll('_', ' ').replaceAll('-', ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int? _parseSeasonNumber(String name) {
    final match = RegExp(r'[Ss]eason\s*(\d{1,2})').firstMatch(name);
    if (match != null) return int.tryParse(match.group(1)!);
    final numMatch = RegExp(r'^(\d{1,2})$').firstMatch(name.trim());
    if (numMatch != null) return int.tryParse(numMatch.group(1)!);
    return null;
  }
}
