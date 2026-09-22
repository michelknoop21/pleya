import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_media.dart';

/// Which Radarr/Sonarr instance a request targets, and why it is not "whichever
/// one we picked when the sheet opened".
///
/// Overseerr resolves the target itself in `MediaRequestSubscriber`:
///
/// ```ts
/// let radarrSettings = settings.radarr.find(
///   (radarr) => radarr.isDefault && radarr.is4k === entity.is4k
/// );
/// if (entity.serverId !== null && entity.serverId >= 0 && radarrSettings?.id !== entity.serverId) {
///   radarrSettings = settings.radarr.find((radarr) => radarr.id === entity.serverId);
/// }
/// ```
///
/// An explicit `serverId` overrides the correct default **unconditionally**, with
/// no check that its 4K-ness matches. The sheet picked its default once, while
/// `is4k` was still false, and never revisited it: switching 4K on therefore sent
/// `is4k: true` together with the SD instance's id, and Overseerr obediently put
/// the 4K request in the SD library, quality profile and root folder included.
/// It then recorded the result under the media's 4K service fields, so the
/// title's 4K availability pointed at the SD instance afterwards.
///
/// Sending no id at all is the honest fallback: Overseerr then applies its own
/// default rule instead of being handed a wrong answer.
SeerrServiceServer _server(int id, {bool is4k = false, bool isDefault = false}) =>
    SeerrServiceServer(id: id, name: 'srv$id', is4k: is4k, isDefault: isDefault);

void main() {
  group('the 4K-ness of the target has to match the request', () {
    test('a 4K movie request targets the default 4K Radarr, not the SD one', () {
      final servers = [_server(1, isDefault: true), _server(2, is4k: true, isDefault: true)];

      expect(preferredSeerrServer(servers, is4k: true)?.id, 2);
      expect(preferredSeerrServer(servers, is4k: false)?.id, 1);
    });

    test('a 4K series request targets the default 4K Sonarr, not the SD one', () {
      // Same model and same endpoint shape for Sonarr; the rule may not differ.
      final servers = [_server(10, isDefault: true), _server(11, is4k: true, isDefault: true)];

      expect(preferredSeerrServer(servers, is4k: true)?.id, 11);
      expect(preferredSeerrServer(servers, is4k: false)?.id, 10);
    });

    test('a non-default server of the right kind beats a default of the wrong kind', () {
      // Overseerr's own default lookup would find nothing here and abort with
      // "no default 4K server configured", so naming the matching one is the
      // more useful answer than leaving it to that.
      final servers = [_server(1, isDefault: true), _server(2, is4k: true)];

      expect(preferredSeerrServer(servers, is4k: true)?.id, 2);
    });

    test('the first matching server wins when several are configured', () {
      final servers = [_server(1, is4k: true), _server(2, is4k: true)];

      expect(preferredSeerrServer(servers, is4k: true)?.id, 1);
    });

    test('no server of the right kind sends no id rather than the wrong one', () {
      final servers = [_server(1, isDefault: true), _server(2)];

      expect(
        preferredSeerrServer(servers, is4k: true),
        isNull,
        reason: 'an explicit id overrides Overseerr unconditionally, so a wrong id is worse than none',
      );
    });

    test('an empty server list sends no id', () {
      expect(preferredSeerrServer(const [], is4k: false), isNull);
      expect(preferredSeerrServer(const [], is4k: true), isNull);
    });
  });
}
