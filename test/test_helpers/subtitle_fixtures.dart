import 'package:pleya/media/media_source_info.dart';

/// Server-side subtitle stream, with every field the resolver reads.
MediaSubtitleTrack serverSubtitle({
  int id = 1,
  int? index,
  String? language,
  String? languageCode,
  String? title,
  String? displayTitle,
  String? codec,
  String? key,
  bool external = false,
  bool usesExternalDelivery = false,
  bool forced = false,
  bool selected = false,
}) => MediaSubtitleTrack(
  id: id,
  index: index,
  language: language,
  languageCode: languageCode,
  title: title,
  displayTitle: displayTitle,
  codec: codec,
  key: key,
  external: external,
  usesExternalDelivery: usesExternalDelivery,
  forced: forced,
  selected: selected,
);
