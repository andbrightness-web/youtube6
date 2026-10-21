import CommonCrypto
import Foundation

/// One prepared copy onto the iPod (REQUEST731): the file in several
/// parallel `Range` streams (the server's `/v1/downloads/{key}/file` is a
/// Starlette `FileResponse`), each into its own part file in the video's
/// folder, so an interrupted transfer — dropped Wi-Fi, a killed app —
/// resumes where every part stopped. The parts are then joined, the size
/// and the sha256 checked against the server's.
///
/// APPROXIMATION: 3 streams, as the downloader's 3 connections per host.
final class YT6AndCastFileFetch: NSObject, URLSessionDataDelegate {
    private struct Part {
        let index: Int
        let start: Int64
        let end: Int64
        let file: URL
        var handle: FileHandle?
        var written: Int64
    }

    static let streams = 3
    /// Running fetches, kept alive until they finish.
    private static var running: [YT6AndCastFileFetch] = []

    private let request: URLRequest
    private let total: Int64
    private let folder: URL
    private let onProgress: (Double) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private let token: CancellationToken?
    private var parts: [Int: Part] = [:]
    private var left = 0
    private var failure: Error?
    private var reportedAt = Date.distantPast
    private var session: URLSession?
    private let queue = OperationQueue()

    private init(
        _ request: URLRequest,
        total: Int64,
        folder: URL,
        token: CancellationToken?,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.request = request
        self.total = total
        self.folder = folder
        self.token = token
        onProgress = progress
        self.completion = completion
        queue.maxConcurrentOperationCount = 1
    }

    // `total` is the size the server reported for the ready copy.
    // swiftlint:disable:next function_parameter_count
    static func start(
        _ request: URLRequest,
        total: Int64,
        folder: URL,
        token: CancellationToken?,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let fetch = YT6AndCastFileFetch(
            request,
            total: total,
            folder: folder,
            token: token,
            progress: progress,
            completion: completion
        )
        running.append(fetch)
        fetch.queue.addOperation { fetch.begin() }
    }

    /// Removes the part files once the joined file was accepted.
    static func dropParts(in folder: URL) {
        for index in 0..<streams {
            let part = folder.appendingPathComponent("andcast.part\(index)")
            try? FileManager.default.removeItem(at: part)
        }
    }

    /// sha256 of a file, read in 4 MB pieces.
    static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { handle.closeFile() }
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        while case let chunk = handle.readData(ofLength: 4 * 1_048_576), !chunk.isEmpty {
            chunk.withUnsafeBytes { raw in
                _ = CC_SHA256_Update(&context, raw.baseAddress, CC_LONG(chunk.count))
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// On the delegate queue, so the parts are only ever touched there.
    private func begin() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        config.httpMaximumConnectionsPerHost = Self.streams
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        let size = max(total, 1)
        let span = (size + Int64(Self.streams) - 1) / Int64(Self.streams)
        for index in 0..<Self.streams {
            open(index, start: Int64(index) * span, end: min(size, Int64(index + 1) * span) - 1)
        }
        if left == 0 {
            join()
        }
    }

    /// One part: what is on disk counts, the rest is asked for.
    private func open(_ index: Int, start: Int64, end: Int64) {
        guard start <= end, let session else {
            return
        }
        let file = folder.appendingPathComponent("andcast.part\(index)")
        let values = try? file.resourceValues(forKeys: [.fileSizeKey])
        let done = min(Int64(values?.fileSize ?? 0), end - start + 1)
        var part = Part(
            index: index, start: start, end: end, file: file, handle: nil, written: done
        )
        guard start + done <= end else {
            parts[index] = part
            return
        }
        if done == 0 {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        part.handle = try? FileHandle(forWritingTo: file)
        part.handle?.seekToEndOfFile()
        parts[index] = part
        var ranged = request
        ranged.setValue("bytes=\(start + done)-\(end)", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: ranged)
        task.taskDescription = "\(index)"
        left += 1
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard token?.isCancelled != true, let index = Int(dataTask.taskDescription ?? ""),
              var part = parts[index] else {
            dataTask.cancel()
            return
        }
        part.handle?.write(data)
        part.written += Int64(data.count)
        parts[index] = part
        // Twice a second is enough for a percentage; every chunk would
        // flood the main queue with row refreshes.
        guard Date().timeIntervalSince(reportedAt) >= 0.5 else {
            return
        }
        reportedAt = Date()
        let got = parts.values.reduce(Int64(0)) { $0 + $1.written }
        let fraction = Double(got) / Double(max(total, 1))
        DispatchQueue.main.async { self.onProgress(min(fraction, 1)) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if let index = Int(task.taskDescription ?? "") {
            parts[index]?.handle?.closeFile()
            parts[index]?.handle = nil
        }
        if let error {
            failure = failure ?? error
        } else if status != 206 && status != 200 {
            failure = failure ?? YT6AndCastError.http(status)
        }
        left -= 1
        if left == 0 {
            if let failure {
                finish(.failure(failure))
            } else {
                join()
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    /// The parts in order into one file; the parts stay until it checks out.
    private func join() {
        let output = folder.appendingPathComponent("andcast.joined")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let target = try? FileHandle(forWritingTo: output) else {
            finish(.failure(DownloadError.storage))
            return
        }
        for index in parts.keys.sorted() {
            guard let file = parts[index]?.file,
                  let source = try? FileHandle(forReadingFrom: file) else {
                continue
            }
            while case let chunk = source.readData(ofLength: 4 * 1_048_576), !chunk.isEmpty {
                target.write(chunk)
            }
            source.closeFile()
        }
        target.closeFile()
        finish(.success(output))
    }

    private func finish(_ result: Result<URL, Error>) {
        session?.finishTasksAndInvalidate()
        session = nil
        DispatchQueue.main.async {
            Self.running.removeAll { $0 === self }
            self.completion(result)
        }
    }
}
