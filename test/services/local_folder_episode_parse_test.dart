import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/local_folder_client.dart';

void main() {
  group('LocalFolderClient.parseLooseEpisode', () {
    test('parses the se1.ep6 convention from the reported flat folder', () {
      final r = LocalFolderClient.parseLooseEpisode('Rooster.se1.ep6.mkv');
      expect(r, isNotNull);
      expect(r!.showTitle, 'Rooster');
      expect(r.season, 1);
      expect(r.episode, 6);
    });

    test('keeps multi-word show titles and 2-digit episode numbers', () {
      final r = LocalFolderClient.parseLooseEpisode('The Miniature Wife.se1.ep10.mkv');
      expect(r!.showTitle, 'The Miniature Wife');
      expect(r.season, 1);
      expect(r.episode, 10);
    });

    test('parses standard SxxEyy, sNeN and NxNN conventions', () {
      expect(LocalFolderClient.parseLooseEpisode('Show.S02E05.mkv'), (showTitle: 'Show', season: 2, episode: 5));
      expect(LocalFolderClient.parseLooseEpisode('Show s3e12.mp4'), (showTitle: 'Show', season: 3, episode: 12));
      expect(LocalFolderClient.parseLooseEpisode('Show 2x08.mkv'), (showTitle: 'Show', season: 2, episode: 8));
      expect(
        LocalFolderClient.parseLooseEpisode('Show.season 1 episode 4.mkv'),
        (showTitle: 'Show', season: 1, episode: 4),
      );
    });

    test('does not mistake an s in the show name for a season marker', () {
      // "Roos" contains an 's' but no digits follow — must not parse falsely.
      expect(LocalFolderClient.parseLooseEpisode('Roos the movie.mkv'), isNull);
      expect(LocalFolderClient.parseLooseEpisode('A Movie (2024).mkv'), isNull);
    });
  });
}
