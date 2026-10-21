import Foundation

/// The guide in «andCast only» / «Downloaded only» (REQUEST724): What To
/// Watch and My Subscriptions over the server's (or the iPod's) channels,
/// History and Downloads under a section named for the source, Settings.
/// Nothing from YouTube is listed: no account rows, no FROM YOUTUBE.
/// APPROXIMATION: the section titles «ANDCAST» / «ON THIS IPOD» follow
/// 2.0.0's uppercase guide headers; 2.0.0 had no such sections.
extension YT6GuideViewController {
    var yt6LocalSections: [(header: String?, rows: [Row])] {
        let offline = YT6Source.mode == .downloadedOnly
        let library: [Row] = offline
            ? [.section(.downloads)]
            : [.section(.history), .section(.downloads)]
        let feeds = [Row.section(.whatToWatch), .section(.subscriptions)]
        return [
            (nil, feeds + channels.indices.map(Row.channel)),
            (offline ? "ON THIS IPOD" : "ANDCAST", library),
            (nil, [.settings])
        ]
    }
}
