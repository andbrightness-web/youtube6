import Foundation

/// Remembers which playback clients YouTube is bot-checking, so an open
/// does not ask them first again.
///
/// Since 21.10 ~12:07 every VISIONOS `/player` answers LOGIN_REQUIRED ("sign
/// in to confirm you're not a bot"), and each open paid for it twice —
/// visionos.range, then visionos.sabr with the same request — each after a
/// fresh watch-page fetch for a new visitor identity: 1.5–2 s, up to 6.8 s,
/// before tv.sabr even started (log 21.10 12:07–13:03, 10 opens). The verdict
/// belongs to the address and the client, not to the video: a client that
/// was just bot-checked goes to the end of the chain for a while, and the
/// other steps of the same client are skipped on that open.
///
/// APPROXIMATION: the cool-down is a guess. After it the client is first
/// again, which is how its return is noticed; nothing is switched off.
enum YT6ChainMemory {
    /// How long a bot-checked client stays at the end of the chain.
    static let coolDown: TimeInterval = 15 * 60

    private static var checkedAt: [String: Date] = [:]
    private static let lock = NSLock()

    /// Steps of one client share their `/player` request: `visionos.range`
    /// and `visionos.sabr` are both VISIONOS.
    static func client(of step: PlaybackStep) -> String {
        String(step.id.split(separator: ".").first ?? Substring(step.id))
    }

    private static func isCooling(_ client: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let at = checkedAt[client] else {
            return false
        }
        return now.timeIntervalSince(at) < coolDown
    }

    /// The chain for one open: bot-checked clients after the others, each
    /// group in the user's order.
    static func ordered(_ steps: [PlaybackStep], logs: Bool = true) -> [PlaybackStep] {
        let late = steps.filter { isCooling(client(of: $0)) }
        guard !late.isEmpty, late.count < steps.count else {
            return steps
        }
        guard logs else {
            return steps.filter { !isCooling(client(of: $0)) } + late
        }
        AppLog.player(
            "[Speed] chain: bot-checked last — \(late.map(\.id).joined(separator: ", "))"
        )
        return steps.filter { !isCooling(client(of: $0)) } + late
    }

    /// The step to try after `index` failed with `error`: past every step of
    /// the same client when the failure was a bot check, the next one
    /// otherwise. `steps.count` when none is left. The video's cached
    /// answers go too: they may be what failed.
    static func next(
        after index: Int, in steps: [PlaybackStep], failure error: Error, videoId: String
    ) -> Int {
        YT6PlaybackCache.forget(videoId: videoId)
        guard let apiError = error as? APIError, case .botCheck = apiError else {
            return index + 1
        }
        let failed = client(of: steps[index])
        lock.lock()
        checkedAt[failed] = Date()
        lock.unlock()
        let next = steps.indices.first { $0 > index && client(of: steps[$0]) != failed }
        AppLog.player("[Speed] chain: \(failed) bot-checked, its other steps skipped")
        return next ?? steps.count
    }
}
