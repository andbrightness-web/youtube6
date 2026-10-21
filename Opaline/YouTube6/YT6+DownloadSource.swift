import Foundation
import QuartzCore

/// Where a download's bytes come from (REQUEST718: «закачки … не работают
/// вообще, не качается»).
///
/// Upstream asks VISIONOS only — the one anonymous client whose direct URLs
/// googlevideo serves past the first minute (Opaline#76). Since 21.10
/// ~12:07 every VISIONOS `/player` answers LOGIN_REQUIRED (bot check, log
/// 21.10 13:57:22 `[Downloads] options failed: botCheck`), and nothing else
/// was tried. What each path gives (read from this code base):
///
/// - VISIONOS, direct URLs (`visionos.range`): the whole file by byte
///   ranges; bot-checked now.
/// - VISIONOS over SABR (`visionos.sabr`): the same `/player`, the same
///   bot check.
/// - ANDROID / ANDROID_VR / IOS: anonymous direct URLs that stop between
///   59.9 and 69.9 s of media (VisionOSClient's note, measured 2026-08-18) —
///   a download would be cut after the first minute. ANDROID's progressive
///   360p is the same story.
/// - TVHTML5 under the account (`tv.sabr`, what plays now): formats carry
///   no URL, only SABR, with a PoToken bound to the living-room id and an
///   `n` solved by the TV player; served to the end (TVClient's note).
///
/// So: VISIONOS while it answers (fast 8 MB ranges), tv.sabr when it is
/// bot-checked — segment by segment as `SABRDelivery` feeds AVPlayer, into
/// the same two part files upstream's mux already joins.
enum YT6DownloadRoute {
    /// `YT6ChainMemory`'s name for the client: the prefix of its step ids.
    static let visionOS = "visionos"

    static func ms(since start: CFTimeInterval) -> Int {
        Int((CACurrentMediaTime() - start) * 1_000)
    }

    /// The TV client as tv.sabr builds it, for its `/player` (mints the
    /// PoToken first, shares `YT6PlaybackCache` with playback).
    static func tvSource(apiClient: WatchService) -> InnertubeVideoSource {
        InnertubeVideoSource(
            apiClient: apiClient,
            client: TVClient(),
            name: "download.tv",
            deliveryFactory: SABRDeliveryFactory()
        )
    }

    static func isBotCheck(_ error: Error?) -> Bool {
        guard let apiError = error as? APIError, case .botCheck = apiError else {
            return false
        }
        return true
    }

    /// The renditions tv.sabr can save: the same H.264 + AAC pick as
    /// upstream, without its demand for a direct URL.
    static func tvOptions(
        _ videoId: String,
        apiClient: WatchService,
        started: CFTimeInterval,
        completion: @escaping (Result<[DownloadOption], Error>) -> Void
    ) {
        guard OAuthClient.shared.isSignedIn else {
            AppLog.downloads("options \(videoId): tv needs an account, none signed in")
            completion(.failure(YT6DownloadFailure.signInNeeded))
            return
        }
        let source = tvSource(apiClient: apiClient)
        source.fetchInfo(videoId: videoId, cancellation: nil) { result in
            withExtendedLifetime(source) {}
            switch result {
            case .failure(let error):
                AppLog.downloads("options \(videoId): tv /player failed: \(error)")
                completion(.failure(error))
            case .success(let info) where SABRDelivery.canServe(info):
                let options = VideoDownloader.options(in: info, overSABR: true)
                AppLog.downloads(
                    "options \(videoId): source tv.sabr, \(options.count) renditions"
                        + " [\(options.map(\.label).joined(separator: ","))]"
                        + " in \(ms(since: started)) ms"
                )
                completion(.success(options))
            case .success:
                AppLog.downloads("options \(videoId): tv answer carries no SABR stream")
                completion(.failure(SABRError.server("no SABR stream")))
            }
        }
    }
}

enum YT6DownloadFailure: Error {
    /// VISIONOS is bot-checked and tv.sabr needs an account.
    case signInNeeded
}

extension VideoDownloader {
    /// `options(for:)` in youtube6: VISIONOS first unless it was just
    /// bot-checked (by playback or here), tv.sabr after it.
    func yt6Options(
        for videoId: String,
        completion: @escaping (Result<[DownloadOption], Error>) -> Void
    ) {
        YT6AndCastDownload.options(for: videoId) { [weak self] server in
            if let server {
                completion(server)
            } else {
                self?.yt6YouTubeOptions(for: videoId, completion: completion)
            }
        }
    }

    private func yt6YouTubeOptions(
        for videoId: String,
        completion: @escaping (Result<[DownloadOption], Error>) -> Void
    ) {
        let started = CACurrentMediaTime()
        let apiClient = apiClient
        guard !YT6ChainMemory.isBotChecked(YT6DownloadRoute.visionOS) else {
            AppLog.downloads("options \(videoId): visionos bot-checked lately, asking tv")
            YT6DownloadRoute.tvOptions(
                videoId, apiClient: apiClient, started: started, completion: completion
            )
            return
        }
        apiClient.fetchDirectPlayback(
            videoId: videoId, client: client, poToken: nil, cancellationToken: nil
        ) { result in
            let direct = (try? result.get()).map { Self.options(in: $0) } ?? []
            guard direct.isEmpty else {
                AppLog.downloads(
                    "options \(videoId): source visionos direct, \(direct.count)"
                        + " renditions in \(YT6DownloadRoute.ms(since: started)) ms"
                )
                completion(.success(direct))
                return
            }
            var error: Error?
            if case .failure(let failure) = result {
                error = failure
            }
            self.yt6AfterVisionOS(videoId, error: error, started: started, completion: completion)
        }
    }

    /// VISIONOS gave nothing to save: its bot check is remembered for
    /// playback too, and tv.sabr is asked.
    private func yt6AfterVisionOS(
        _ videoId: String,
        error: Error?,
        started: CFTimeInterval,
        completion: @escaping (Result<[DownloadOption], Error>) -> Void
    ) {
        if YT6DownloadRoute.isBotCheck(error) {
            YT6ChainMemory.noteBotCheck(YT6DownloadRoute.visionOS)
        }
        let why = error.map { "\($0)" } ?? "no H.264 with a URL"
        AppLog.downloads("options \(videoId): visionos gave nothing (\(why)), asking tv")
        YT6DownloadRoute.tvOptions(
            videoId, apiClient: apiClient, started: started, completion: completion
        )
    }
}

extension YT6 {
    /// A failed download in words that say what to do (REQUEST718), in place
    /// of upstream's one «Не удалось скачать это видео» for everything.
    static func downloadErrorText(_ error: Error) -> String {
        let russian = Locale.preferredLanguages.first?.hasPrefix("ru") == true
        if case YT6DownloadFailure.signInNeeded = error {
            return russian
                ? "YouTube проверяет на робота — войдите в аккаунт, чтобы сохранять"
                : "YouTube is checking for bots — sign in to save videos"
        }
        if YT6DownloadRoute.isBotCheck(error) {
            return russian
                ? "YouTube не отдаёт видео: проверка на робота"
                : "YouTube refused the video: bot check"
        }
        switch error as? DownloadError {
        case .storage:
            return russian ? "Не хватает места на iPod" : "Not enough space on the iPod"
        case .noTracks, .export, .missingFile:
            return russian ? "Не удалось собрать файл видео" : "Couldn't assemble the video file"
        default:
            break
        }
        if error is DownloadError || error is URLError || error is SABRError {
            return russian
                ? "Не удалось сохранить: сеть или YouTube не отдали видео"
                : "Couldn't save: the network or YouTube didn't serve the video"
        }
        return "downloads.error.failed".localized
    }
}
