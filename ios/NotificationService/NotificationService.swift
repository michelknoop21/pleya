import UserNotifications

/// Rich push (DEC-XXX): replaces the generic Pleya alert with the sealed title
/// and attaches the poster. Without a key or with content that does not open,
/// the generic alert stays. A poster that fails or arrives too late leaves the
/// title without an image.
final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var handler: ((UNNotificationContent) -> Void)?
  private var best: UNNotificationContent?
  private var task: URLSessionTask?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    locked {
      handler = contentHandler
      best = request.content
    }
    guard let opened = PushContent.rich(from: request.content.userInfo),
      let content = request.content.mutableCopy() as? UNMutableNotificationContent
    else { return finish(request.content) }
    let (rich, base) = opened
    content.title = rich.title
    content.body = rich.body
    locked { best = content }

    guard let artwork = rich.artwork, let token = rich.token,
      let url = PushContent.posterURL(base: base, artwork: artwork)
    else { return finish(content) }
    var poster = URLRequest(url: url, timeoutInterval: 20)
    poster.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let download = Self.session.downloadTask(with: poster) { [weak self] file, response, _ in
      var downloaded: UNNotificationContent = content
      if let file, let http = response as? HTTPURLResponse, http.statusCode == 200,
        let attachment = Self.attachment(file, mimeType: http.mimeType)
      {
        downloaded = Self.attaching(attachment, to: content)
      }
      self?.finish(downloaded)
    }
    locked { task = download }
    download.resume()
  }

  // Expiry may hand over the title while the download completes; keep it stable.
  static func attaching(_ attachment: UNNotificationAttachment, to content: UNNotificationContent)
    -> UNNotificationContent
  {
    let copy = content.mutableCopy() as! UNMutableNotificationContent
    copy.attachments = [attachment]
    return copy
  }

  override func serviceExtensionTimeWillExpire() {
    let (running, content) = locked { (task, best) }
    running?.cancel()
    finish(content)
  }

  /// NSLocking.withLock needs iOS 16; the app still supports 15.5.
  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// Hands over exactly once, whichever path gets here first.
  private func finish(_ content: UNNotificationContent?) {
    let deliver = locked { () -> ((UNNotificationContent) -> Void)? in
      defer { handler = nil }
      return handler
    }
    if let deliver, let content { deliver(content) }
  }

  /// Ephemeral, and never follows a redirect: the artwork token is only for
  /// the server that minted it.
  private static let session = URLSession(
    configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

  private static func attachment(_ file: URL, mimeType: String?) -> UNNotificationAttachment? {
    let ext: String
    switch mimeType {
    case "image/jpeg": ext = "jpg"
    case "image/png": ext = "png"
    default: return nil
    }
    let target = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    guard (try? FileManager.default.moveItem(at: file, to: target)) != nil else { return nil }
    return try? UNNotificationAttachment(identifier: "poster", url: target)
  }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
