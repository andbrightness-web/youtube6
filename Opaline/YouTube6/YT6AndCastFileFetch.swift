import Foundation

/// One andCast file onto disk with progress for the downloader's bar: a
/// download task (the file never sits in memory), no redirects, cancelled
/// with the job.
final class YT6AndCastFileFetch: NSObject, URLSessionDownloadDelegate {
    /// Running fetches, kept alive until they finish.
    private static var running: [YT6AndCastFileFetch] = []

    private weak var downloader: VideoDownloader?
    /// The job's token when the fetch began: a later job brings its own.
    private let token: CancellationToken?
    private let scale: Double
    private let completion: (Result<URL, Error>) -> Void
    private var reported: Int64 = 0
    private var session: URLSession?

    private init(
        scale: Double,
        downloader: VideoDownloader,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.scale = scale
        self.downloader = downloader
        self.token = downloader.cancellation
        self.completion = completion
    }

    /// `scale` maps the file's bytes onto the option's estimate, so the
    /// shared progress reaches 100 % with the last byte.
    static func start(
        _ request: URLRequest,
        scale: Double,
        downloader: VideoDownloader,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let fetch = YT6AndCastFileFetch(
            scale: scale, downloader: downloader, completion: completion
        )
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: fetch, delegateQueue: nil)
        fetch.session = session
        running.append(fetch)
        session.downloadTask(with: request).resume()
    }

    // swiftlint:disable:next function_parameter_count
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard token?.isCancelled == false else {
            downloadTask.cancel()
            return
        }
        let scaled = Int64(Double(totalBytesWritten) * scale)
        let delta = scaled - reported
        reported = scaled
        DispatchQueue.main.async { [weak self] in
            self?.downloader?.advance(by: delta)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            finish(.failure(YT6AndCastError.http(status)))
            return
        }
        // The temporary file goes away when this returns: move it first.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt6-andcast-\(UUID().uuidString).mp4")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(DownloadError.storage))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
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

    private func finish(_ result: Result<URL, Error>) {
        session?.finishTasksAndInvalidate()
        session = nil
        DispatchQueue.main.async {
            Self.running.removeAll { $0 === self }
            self.completion(result)
        }
    }
}
