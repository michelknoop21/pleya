import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';

/// Connected synthetic sources for card tests that replace image decoding.
class CatalogArtworkClient extends Fake implements MediaServerClient {
  CatalogArtworkClient(this.serverId);
  @override
  final ServerId serverId;
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) =>
      'https://${serverId.value}.invalid/${Uri.encodeComponent(path ?? '')}';
}

class CatalogArtworkServers extends MultiServerProvider {
  CatalogArtworkServers(MultiServerManager manager) : super(manager, DataAggregationService(manager));

  @override
  MediaServerClient? getClientForServer(ServerId serverId) => CatalogArtworkClient(serverId);
}
