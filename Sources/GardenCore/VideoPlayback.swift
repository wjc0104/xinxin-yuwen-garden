import Foundation

public struct VideoPlaybackSource {
    public let url: URL
    public let offeredHeight: Int?
    public let duration: Double?
}
public struct BilibiliReference {
    public let bvid: String
    public let page: Int
    public var partListURL: URL { URL(string: "https://api.bilibili.com/x/player/pagelist?bvid=" + bvid)! }
    public var originalURL: URL { URL(string: "https://www.bilibili.com/video/\(bvid)/?p=\(page)")! }
    public var metadataURL: URL { URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=" + bvid)! }
    public func playbackURL(cid: Int) -> URL {
        var parts = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        parts.queryItems = [URLQueryItem(name: "bvid", value: bvid), URLQueryItem(name: "cid", value: String(cid)), URLQueryItem(name: "qn", value: "80"), URLQueryItem(name: "fnval", value: "1"), URLQueryItem(name: "fnver", value: "0"), URLQueryItem(name: "fourk", value: "0")]
        return parts.url!
    }
}
/// Public, unauthenticated source discovery. Never infer received quality from accept_quality.
public enum BilibiliPlayback {
    private struct Status: Decodable { let code: Int }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Metadata: Decodable {
        struct Part: Decodable { let page: Int; let cid: Int }
        let pages: [Part]
    }
    private struct Playback: Decodable {
        struct Part: Decodable { let url: String }
        let quality: Int?
        let format: String?
        let timelength: Double?
        let durl: [Part]?
        let is_preview: Bool?
    }
    public static func reference(_ raw: String) throws -> BilibiliReference {
        guard let parts = URLComponents(string: raw), parts.scheme == "https", ["www.bilibili.com","bilibili.com"].contains(parts.host ?? ""), parts.user == nil, parts.password == nil, parts.port == nil,
              let url = parts.url else { throw GardenError.invalid("这不是可识别的视频地址。") }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 2, path[0] == "video", path[1].hasPrefix("BV"), path[1].count == 12, path[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw GardenError.invalid("视频编号不完整，请打开具体视频。") }
        let pageText = parts.queryItems?.first { $0.name == "p" }?.value ?? "1"
        guard let page = Int(pageText), (1...5000).contains(page) else { throw GardenError.invalid("视频分集编号无效。") }
        return BilibiliReference(bvid: path[1], page: page)
    }
    public static func contentID(_ data: Data, page: Int) throws -> Int {
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.code == 0 else { throw GardenError.invalid("原站视频服务暂不可用（\(status.code)），请稍后重试。") }
        let envelope = try JSONDecoder().decode(Envelope<Metadata>.self, from: data)
        guard let id = envelope.data?.pages.first(where: { $0.page == page })?.cid, id > 0 else { throw GardenError.invalid("原站没有返回这一集，未改播其他分集。") }
        return id
    }
    public static func parts(_ data: Data) throws -> [BilibiliPart] {
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.code == 0 else { throw GardenError.invalid("原站视频服务暂不可用（\(status.code)），请稍后重试。") }
        let envelope = try JSONDecoder().decode(Envelope<[BilibiliPart]>.self, from: data)
        guard let parts = envelope.data, !parts.isEmpty, parts.allSatisfy({ $0.cid > 0 && (1...5000).contains($0.page) }), Set(parts.map(\.cid)).count == parts.count, Set(parts.map(\.page)).count == parts.count else { throw GardenError.invalid("原站返回的分集信息不完整。") }
        return parts
    }
    public static func resolve(_ parts: [BilibiliPart], reference: BilibiliReference, knownCID: Int?) throws -> BilibiliPart {
        if let cid = knownCID {
            guard let part = parts.first(where: { $0.cid == cid }) else { throw GardenError.invalid("原分集已被移除或更新，请刷新本课资料；未改播其他分集。") }
            return part
        }
        guard let part = parts.first(where: { $0.page == reference.page }) else { throw GardenError.invalid("原站没有返回这一集，未改播其他分集。") }
        return part
    }
    public static func source(_ data: Data) throws -> VideoPlaybackSource {
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.code == 0 else { throw GardenError.invalid("原站播放服务暂不可用（\(status.code)），请稍后重试。") }
        let envelope = try JSONDecoder().decode(Envelope<Playback>.self, from: data)
        guard envelope.code == 0, let value = envelope.data, value.is_preview != true, value.format?.hasPrefix("mp4") == true,
              let segments = value.durl, segments.count == 1, let url = URL(string: segments[0].url), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host, host == "bilivideo.com" || host.hasSuffix(".bilivideo.com") || host == "upos-hz-mirrorakam.akamaized.net" else { throw GardenError.invalid("未取得可直接播放的完整视频。可以重试，或打开原视频核对。") }
        let heights = [16:360,32:480,64:720,74:720,80:1080,112:1080,116:1080,120:2160]
        return VideoPlaybackSource(url: url, offeredHeight: value.quality.flatMap { heights[$0] }, duration: value.timelength.map { $0 / 1000 })
    }
}

public struct BilibiliPart: Decodable, Equatable {
    public let page: Int
    public let cid: Int
    public let part: String
    public let duration: Int?
    public init(page: Int, cid: Int, part: String, duration: Int? = nil) { self.page = page; self.cid = cid; self.part = part; self.duration = duration }
}
