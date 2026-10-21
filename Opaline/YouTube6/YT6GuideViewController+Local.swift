import Foundation

/// The guide in «andCast only» / «Downloaded only» (REQUEST724, 728), in
/// the order of the YouTube mode's guide (`sections`): the account-like
/// group first — Watch Later, History, Playlists, Liked (andCast's lists)
/// and Downloads with its count, where ACCOUNT holds them — then What To
/// Watch, My Subscriptions and the channels that have videos here, then
/// Settings. Nothing from YouTube is listed: no account rows, no FROM
/// YOUTUBE.
/// APPROXIMATION: the group titles «ANDCAST» / «ON THIS IPOD» stand where
/// 2.0.0 writes ACCOUNT; 2.0.0 had no such sections.
extension YT6GuideViewController {
    /// «ANDCAST», with the sync's state while there is one (APPROXIMATION:
    /// the andCast client shows it over its library).
    private static var yt6AndCastHeader: String {
        let catalog = YT6AndCastCatalog.shared
        if catalog.phase != nil || catalog.serverRefreshing {
            return "ANDCAST · SYNCING"
        }
        return catalog.lastError == nil ? "ANDCAST" : "ANDCAST · OFFLINE"
    }

    var yt6LocalSections: [(header: String?, rows: [Row])] {
        let offline = YT6Source.mode == .downloadedOnly
        let saved: [YT6Section] = [.watchLater, .history, .playlists, .liked, .downloads]
        let library = saved.map(Row.section)
        let feeds = [Row.section(.whatToWatch), .section(.subscriptions)]
        return [
            (offline ? "ON THIS IPOD" : Self.yt6AndCastHeader, library),
            (nil, feeds + channels.indices.map(Row.channel)),
            (nil, [.settings])
        ]
    }
}
