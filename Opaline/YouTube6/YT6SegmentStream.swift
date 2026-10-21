import Foundation

/// One googlevideo segment download shared by everyone who asks for it
/// (REQUEST695, step 1 of research/YOUTUBE6-SPEED-2026-10-21.md).
///
/// The proxy used to hand AVPlayer a segment only once all of its 1–4 MB
/// had arrived; now `LocalMediaServer` sends the length up front (known from
/// the index) and every chunk as it comes in, so the first frame no longer
/// waits for the last byte. Readers that join late get what has arrived so
/// far, then follow along. Bytes come through the session delegate
/// (`YT6NetMetrics`), which looks the stream up by its task.
final class YT6SegmentStream {
    typealias OnData = (Data) -> Void
    /// The whole segment, or nil when the download failed or was cancelled.
    typealias OnEnd = (Data?) -> Void

    private static var streams: [ObjectIdentifier: YT6SegmentStream] = [:]
    private static let registry = NSLock()

    let length: Int
    let mime: String
    private(set) var statusCode = 0
    private(set) var task: URLSessionDataTask?
    /// Callbacks run under the lock so every reader sees the bytes in order;
    /// they only queue work (a socket send), never call back in.
    private let lock = NSLock()
    private var received = Data()
    private var result: Data??
    private var readers: [(data: OnData, end: OnEnd)] = []

    init(length: Int, mime: String) {
        self.length = length
        self.mime = mime
    }

    static func stream(for task: URLSessionTask) -> YT6SegmentStream? {
        registry.lock()
        defer {
            registry.unlock()
        }
        return streams[ObjectIdentifier(task)]
    }

    /// Starts the download; data arrives through the session's delegate.
    func start(_ request: URLRequest, on session: URLSession) {
        let task = session.dataTask(with: request)
        self.task = task
        Self.registry.lock()
        Self.streams[ObjectIdentifier(task)] = self
        Self.registry.unlock()
        task.resume()
    }

    /// Replays what has arrived, then follows the download to its end.
    func read(onData: @escaping OnData, onEnd: @escaping OnEnd) {
        lock.lock()
        defer {
            lock.unlock()
        }
        switch result {
        case .none:
            if !received.isEmpty {
                onData(received)
            }
            readers.append((onData, onEnd))
        case let .some(body):
            if let body {
                onData(body)
            }
            onEnd(body)
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: Session delegate

    func receive(response: URLResponse) {
        lock.lock()
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        lock.unlock()
    }

    func receive(_ chunk: Data) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard result == nil, statusCode == 206 || statusCode == 200 else {
            return
        }
        received.append(chunk)
        readers.forEach { $0.data(chunk) }
    }

    func complete(error: Error?) {
        if let task {
            Self.registry.lock()
            Self.streams.removeValue(forKey: ObjectIdentifier(task))
            Self.registry.unlock()
        }
        lock.lock()
        defer {
            lock.unlock()
        }
        guard result == nil else {
            return
        }
        let whole = error == nil && received.count == length
        let body: Data? = whole ? received : nil
        result = .some(body)
        readers.forEach { $0.end(body) }
        readers = []
    }
}
