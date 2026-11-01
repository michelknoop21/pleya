/// Whether existing identity claims can cross the Pleya applied boundary.
library;

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../media/unified/carried_external_ids.dart';
import '../services/pleya_server_client.dart';

bool canTrustStoredIdentity(MediaItem item, MediaServerClient? client) =>
    storedIdentityIsSafe(item) || (client is PleyaServerClient && client.canUseStoredExternalIds(item));
