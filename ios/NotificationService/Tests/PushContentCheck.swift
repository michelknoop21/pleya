import Foundation
import UserNotifications

/// Opens the vector the Go side sealed (pleya_server/internal/push/testdata/
/// rich_vector.json) and checks the fallbacks. Run by scripts/test_push_content.sh.
@main
struct PushContentCheck {
  static func main() throws {
    let path = CommandLine.arguments[1]
    let vector =
      try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: String]
    let key = Data(base64Encoded: vector["key"]!)!
    let sealed = Data(base64Encoded: vector["sealed"]!)!
    let aad = vector["aad"]!
    var failures = 0
    func check(_ ok: Bool, _ what: String) {
      if !ok { failures += 1 }
      print("\(ok ? "PASS" : "FAIL")  \(what)")
    }

    let rich = PushContent.open(sealed, key: key, aad: aad)
    check(
      rich?.title == "Nieuw: Dune" && rich?.body == "Nieuwe film in je bibliotheek.", "opens the server's sealed title")
    check(
      rich?.artwork == "0198f2c0-0001-7000-8000-000000000001" && rich?.token == "ply1.e30.c2ln",
      "carries poster id and token")

    check(PushContent.open(sealed, key: key, aad: aad + "x") == nil, "another notification falls back")
    check(PushContent.open(sealed, key: key, aad: "") == nil, "missing binding falls back")

    var wrongKey = key
    wrongKey[0] ^= 1
    check(PushContent.open(sealed, key: wrongKey, aad: aad) == nil, "another key falls back")
    var tampered = sealed
    tampered[tampered.count - 1] ^= 1
    check(PushContent.open(tampered, key: key, aad: aad) == nil, "tampered content falls back")
    check(PushContent.open(sealed.prefix(10), key: key, aad: aad) == nil, "truncated content falls back")
    check(PushContent.open(sealed, key: key.prefix(16), aad: aad) == nil, "a short key falls back")
    check(PushContent.rich(from: ["aps": [:]]) == nil, "an alert without rich part stays generic")

    let url = PushContent.posterURL(base: "https://nas.example.org/", artwork: "0198F2C0-0001-7000-8000-000000000001")
    check(
      url?.absoluteString == "https://nas.example.org/pleya/v1/artwork/0198f2c0-0001-7000-8000-000000000001?width=960",
      "poster URL on the registering server")
    check(
      PushContent.posterURL(base: "http://nas.example.org", artwork: "0198f2c0-0001-7000-8000-000000000001") == nil,
      "no poster over plain HTTP")
    check(
      PushContent.posterURL(base: "https://nas.example.org", artwork: "../users/me") == nil, "artwork must be an id")

    check(PushContent.allowsKeychain("nl.michelknoop.pleya"), "app may use shared keys")
    check(PushContent.allowsKeychain("nl.michelknoop.pleya.NotificationService"), "extension may use shared keys")
    check(!PushContent.allowsKeychain("nl.michelknoop.pleya.verify"), "Verify cannot access production keys")
    check(!PushContent.allowsKeychain(nil), "unidentified bundle cannot access keys")
    let image = URL(fileURLWithPath: CommandLine.arguments[2])
    try Data(
      base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1sAAAAASUVORK5CYII=")!
      .write(to: image)
    let attachment = try UNNotificationAttachment(identifier: "poster", url: image)
    let title = UNMutableNotificationContent()
    title.title = "Nieuw: Dune"
    let downloaded = NotificationService.attaching(attachment, to: title)
    check(downloaded.attachments.count == 1, "download attaches poster")
    check(
      title.attachments.isEmpty && title.title == downloaded.title, "expiry title stays stable when download completes")

    if failures > 0 { exit(1) }
  }
}
