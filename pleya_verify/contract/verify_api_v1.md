<!-- anti-slop: off -->
# Pleya Verify transport contract v1

Autoritatieve spec voor het `/v1/*` control-plane dat de app aanbiedt
(`lib/automation/automation_server.dart`) en de runner-client die ertegen
praat (`pleya_verify/runner/lib/src/transport/verify_client.dart`). Beide
kanten hebben een test die dit bestand parseert en tegen de eigen
implementatie legt — zie `test/automation/transport_contract_test.dart` en
`pleya_verify/runner/test/transport_contract_test.dart`. Een endpoint dat hier
niet staat, bestaat niet op het control-plane; een endpoint dat hier wel
staat maar ontbreekt in een van beide kanten, is een falende test.

## Auth

Elk `/v1/*`-verzoek:

- `Host` moet `127.0.0.1[:port]` of `localhost[:port]` zijn, anders 403.
- `X-Pleya-Verify: PleyaVerify/1` is verplicht — een constante protocolmarker,
  nooit een geheim. Ontbreekt hij of klopt hij niet, dan 403.
- `Authorization: Bearer <token>` is alleen verplicht wanneer de app gebouwd
  is met `PLEYA_VERIFY_TOKEN` gezet. Ontbreekt hij dan of klopt hij niet, dan
  401. `X-Pleya-Verify` wordt nergens als tokenwaarde gelezen.

## Endpoints

### `GET /v1/health`

Geen parameters. 200 met JSON:

```json
{
  "protocolVersion": 1,
  "commit": "<git sha, leeg buiten CI>",
  "platform": "<TargetPlatform.name>",
  "port": 47317,
  "booted": true,
  "bootedAt": "<ISO8601>"
}
```

Triggert geen events.
