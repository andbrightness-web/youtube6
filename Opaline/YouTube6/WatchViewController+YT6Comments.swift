import UIKit

/// The 2.0.0 comments section in place on the page (REQUEST: no Opaline
/// panel). A tap on «КОММЕНТАРИИ · N» flips the header's arrow and inserts
/// the comments under the input row (`didSelectRow:fromView:` @3eeeac →
/// `setExpanded:` @3ef578 → `requestComments` @3ef81c); the threads are the
/// ones upstream already loads (`commentThreads`, `loadComments`).
extension WatchViewController {
    /// How far before the end of the page the next comments page is asked
    /// for. APPROXIMATION: the feed's own trigger is not read.
    private static let commentsPrefetchDistance: CGFloat = 600

    /// `didSelectRow:` row 0: toggle; expanding asks for comments if none.
    @objc
    func yt6ToggleComments() {
        guard let chrome = yt6 else {
            return
        }
        yt6FoldCommentsOnNewVideo(chrome)
        chrome.commentsExpanded.toggle()
        if chrome.commentsExpanded, commentThreads.isEmpty, !isLoadingComments {
            loadComments()
        }
        yt6SyncComments()
    }

    /// Each layout pass (upstream's `renderComments` ends in one): rebuilds
    /// the rows when what they show changed. A new video starts folded, as
    /// a fresh section controller would.
    func yt6SyncComments() {
        guard let chrome = yt6 else {
            return
        }
        yt6FoldCommentsOnNewVideo(chrome)
        let state = [
            initialVideo.id,
            "\(commentThreads.count)",
            commentThreads.first?.comment.id ?? "",
            "\(isLoadingComments) \(commentsContinuation != nil) \(hasLoadedComments)",
            "\(chrome.commentsExpanded)"
        ].joined(separator: "|")
        guard state != chrome.commentsState else {
            return
        }
        chrome.commentsState = state
        yt6RenderComments()
    }

    private func yt6FoldCommentsOnNewVideo(_ chrome: YT6WatchChrome) {
        if chrome.commentsVideoId != initialVideo.id {
            chrome.commentsVideoId = initialVideo.id
            chrome.commentsExpanded = false
        }
    }

    /// Rebuilds the rows from upstream's threads (top level only).
    private func yt6RenderComments() {
        guard let chrome = yt6 else {
            return
        }
        chrome.commentsArrow.image = YT6.image(
            chrome.commentsExpanded
                ? "card_disclosure_arrow_expanded"
                : "card_disclosure_arrow_collapsed"
        )
        chrome.comments.addRow.setUserThumbnail(UserProfileStore.shared.avatarImage)
        guard chrome.commentsExpanded else {
            chrome.comments.setRows([])
            return
        }
        var rows = commentThreads.map { YT6CommentsView.Row.comment($0.comment) }
        if isLoadingComments || commentsContinuation != nil {
            rows.append(.status(nil))
        } else if rows.isEmpty, hasLoadedComments {
            rows.append(.status(YT6.string(
                "status.empty.comments",
                fallback: "This video has no comments"
            )))
        }
        chrome.comments.setRows(rows)
    }

    /// Endless list: the next page once the end of the page comes near.
    func yt6LoadMoreCommentsIfNeeded(_ scrollView: UIScrollView) {
        guard yt6?.commentsExpanded == true,
              let continuation = commentsContinuation,
              !isLoadingComments
        else {
            return
        }
        let bottom = scrollView.contentOffset.y + scrollView.bounds.height
        if bottom > scrollView.contentSize.height - Self.commentsPrefetchDistance {
            loadComments(continuation: continuation)
        }
    }

    /// APPROXIMATION: 2.0.0 sends the comment (`addComment` @3ef8d0); upstream
    /// has no comment-posting call, so the field says so instead.
    func yt6AddCommentTapped() {
        let isRussian = YT6.isRussianInterface
        let message = isRussian
            ? "Отправка комментариев пока не поддерживается."
            : "Posting comments isn't supported yet."
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
