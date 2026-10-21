import Foundation

extension ServiceContainer {
    /// youtube6: the screens' data from andCast or the saved videos while
    /// the source mode keeps YouTube out (REQUEST724); YouTube's otherwise.
    static func yt6Pick<T>(_ youtube: T) -> T {
        guard YT6.isEnabled, YT6Source.isLocal, let local = YT6Library.shared as? T else {
            return youtube
        }
        return local
    }
}
