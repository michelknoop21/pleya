part of '../../pleya_server_client.dart';

/// `POST /companion/ticket` (DEC-XXX): a ticket about the signed-in user, for
/// Pleya Fly. A server without the route answers 404, which throws here.
extension PleyaServerCompanionTicket on PleyaServerClient {
  Future<PleyaCompanionTicket> companionTicket(String deviceKey) async {
    final data = await _adminSend('POST', '/companion/ticket', body: PleyaCompanionTicket.request(deviceKey));
    if (data == null) {
      throw MediaServerHttpException(type: MediaServerHttpErrorType.unknown, message: 'empty companion ticket');
    }
    return PleyaCompanionTicket.fromJson(data);
  }
}
