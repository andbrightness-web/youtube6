import Foundation

/// One merged channel in «andCast only» (REQUEST727): YouTube's header
/// (avatar, banner, subscribers, description) when the channel is matched
/// to its YouTube id and YouTube answers within 5 s; the andCast base's
/// otherwise — the channel's avatar, `Overview` and the subscriber count
/// of the stats base. The videos are always the server's.
extension YT6Library {
    static func merge(_ info: ChannelInfo, local: ChannelInfo) -> ChannelInfo {
        ChannelInfo(
            id: info.id,
            title: info.title.isEmpty ? local.title : info.title,
            avatarURL: info.avatarURL ?? local.avatarURL,
            subscriberCountText: info.subscriberCountText ?? local.subscriberCountText,
            bannerURL: info.bannerURL,
            isVerified: info.isVerified,
            description: info.description ?? local.description,
            contactInfo: info.contactInfo,
            videoCountText: local.videoCountText
        )
    }
}
    func localInfo(_ channelId: String) -> ChannelInfo {
        let channel = YT6AndCastChannelMap.channel(channelId)
        let list = videos(ofChannel: channelId)
        let avatar = channel.flatMap { YT6AndCast.artworkURL($0.id, revision: $0.artwork) }
        let subscribers = channel.flatMap { YT6AndCastNumbers.shared.subscribers(channel: $0.id) }
        return ChannelInfo(
            id: channelId,
            title: channel?.title ?? list.first?.channelName ?? "",
            avatarURL: avatar ?? list.first?.channelAvatarURL,
            subscriberCountText: YT6AndCastNumbers.subscribersText(subscribers),
            bannerURL: nil,
            isVerified: false,
            description: channel?.overview,
            contactInfo: nil,
            videoCountText: "\(list.count) videos on andCast"
        )
    }

    func mergedInfo(_ channelId: String, completion: @escaping (ChannelInfo) -> Void) {
        let local = localInfo(channelId)
        guard YT6Source.mode == .andCastOnly,
              let channel = YT6AndCastChannelMap.channel(channelId),
              let youtube = YT6AndCastChannelMap.youtubeId(of: channel) else {
            DispatchQueue.main.async { completion(local) }
            return
        }
        YT6Race.first(within: 5, fallback: local, completion: completion) { done in
            ServiceContainer.client.fetchChannelInfo(channelId: youtube) { result in
                guard case .success(let info) = result else {
                    YT6AndCast.log("library: channel \(channel.id) from the andCast base")
                    done(nil)
                    return
                }
                YT6AndCast.log("library: channel \(channel.id) header from YouTube \(youtube)")
                done(Self.merge(info, local: local))
            }
        }
    }
