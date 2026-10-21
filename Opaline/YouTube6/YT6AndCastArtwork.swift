import Foundation

/// Covers before they are scrolled to (REQUEST727: «я сейчас не вижу
/// обложек»): the next page of a list is fetched ahead in one
/// `POST /andcast/v1/artwork/batch` (up to 100 items, base64 JPEGs — what
/// the andCast client's `ACArtwork synchronize` uses) straight into the
/// thumbnail disk cache under each cover's own address, so the rows open
/// from disk. The rows of the screen itself load as before.
enum YT6AndCastArtwork {
    private static let batch = 100
    private static var asked = Set<String>()

    static func warm(_ videos: [Video]) {
        guard YT6Source.mode != .downloadedOnly, YT6AndCastReach.base != nil else {
            return
        }
        let disk = ThumbnailLoader.shared.diskCache
        var wanted: [(item: YT6AndCastItem, url: URL)] = []
        for video in videos {
            guard let item = YT6AndCastCatalog.shared.item(videoId: video.id),
                  let address = YT6AndCast.artworkURL(item.id, revision: item.artwork),
                  let url = URL(string: address), !asked.contains(address),
                  disk.fileURL(for: url) == nil else {
                continue
            }
            asked.insert(address)
            wanted.append((item, url))
        }
        stride(from: 0, to: wanted.count, by: batch).forEach { start in
            fetch(Array(wanted[start..<min(start + batch, wanted.count)]))
        }
    }

    private static func fetch(_ wanted: [(item: YT6AndCastItem, url: URL)]) {
        let items = wanted.map { ["Id": $0.item.id, "ArtworkRevision": $0.item.artwork ?? ""] }
        var urls: [String: URL] = [:]
        wanted.forEach { urls[$0.item.id] = $0.url }
        YT6AndCast.call("v1/artwork/batch", body: ["items": items]) { body in
            let images = body?["images"] as? [[String: Any]] ?? []
            DispatchQueue.global(qos: .utility).async {
                var stored = 0
                for image in images {
                    guard let id = image["Id"] as? String, let url = urls[id],
                          let text = image["data"] as? String,
                          let data = Data(base64Encoded: text) else {
                        continue
                    }
                    ThumbnailLoader.shared.diskCache.store(data: data, for: url)
                    stored += 1
                }
                YT6AndCast.log("artwork: \(stored) of \(wanted.count) covers fetched ahead")
            }
        }
    }
}
