import Foundation
import Network

/// Streamed answers for the range proxy's segments (`YT6SegmentStream`):
/// the head goes out at once with the segment's full length, the body chunk
/// by chunk as googlevideo delivers it. A request for part of a segment
/// falls back to upstream's whole-body path, which waits on the same
/// download.
extension LocalMediaServer {
    /// 200 for the segment, 206 when it was asked for as a range from 0 to
    /// its end; nil for any other range — only whole segments stream.
    private static func yt6Head(for request: Request, stream: YT6SegmentStream) -> String? {
        let length = stream.length
        var status = "200 OK"
        var extra = ""
        if let range = request.range {
            guard range.start == 0, (range.end ?? length - 1) >= length - 1 else {
                return nil
            }
            status = "206 Partial Content"
            extra = "Content-Range: bytes 0-\(length - 1)/\(length)\r\n"
        }
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(stream.mime)\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += extra
        head += "Connection: keep-alive\r\n\r\n"
        return head
    }

    /// True when the stream answered the request.
    func yt6Stream(_ request: Request, on connection: NWConnection) -> Bool {
        guard let streamer = yt6Streamer, let stream = streamer(request.path) else {
            return false
        }
        guard let head = Self.yt6Head(for: request, stream: stream) else {
            return false
        }
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        guard request.method != "HEAD" else {
            receiveRequest(on: connection, buffer: Data())
            return true
        }
        stream.read(
            onData: { chunk in
                connection.send(content: chunk, completion: .contentProcessed { _ in })
            },
            onEnd: { [weak self] body in
                // A promised length that will not arrive: drop the socket so
                // the player asks again instead of waiting on it.
                guard body != nil else {
                    connection.cancel()
                    return
                }
                self?.receiveRequest(on: connection, buffer: Data())
            }
        )
        return true
    }
}
