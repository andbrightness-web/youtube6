import Foundation

/// «Try YouTube first, show the andCast base when it does not answer»
/// (REQUEST727): the first of a YouTube answer and a deadline wins, once,
/// on the main queue. A late YouTube answer is dropped.
enum YT6Race {
    private final class Once {
        var done = false
    }

    static func first<T>(
        within seconds: TimeInterval,
        fallback: @autoclosure @escaping () -> T,
        completion: @escaping (T) -> Void,
        attempt: (@escaping (T?) -> Void) -> Void
    ) {
        let once = Once()
        let finish: (T?) -> Void = { value in
            DispatchQueue.main.async {
                guard !once.done else {
                    return
                }
                once.done = true
                completion(value ?? fallback())
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            finish(nil)
        }
        attempt(finish)
    }
}
