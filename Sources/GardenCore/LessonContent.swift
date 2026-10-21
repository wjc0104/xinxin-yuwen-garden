import Foundation

public struct LessonVideoCandidate {
    public let bvid: String
    public let title: String
    public let author: String
    public let thumbnail: String?
    public let duration: Int?
}

/// Pure metadata parsers. Article descriptions and article bodies are intentionally never retained.
public enum LessonContent {
    public static func text(_ html: String) -> String {
        var value = html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] { value = value.replacingOccurrences(of: entity, with: replacement) }
        value = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "[\\p{Cc}\\p{Cf}]", with: " ", options: .regularExpression)
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }
    public static func imageURL(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let safe = raw.hasPrefix("//") ? "https:" + raw : raw.replacingOccurrences(of: "http://", with: "https://", options: .anchored)
        guard let url = URL(string: safe), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host, host == "hdslb.com" || host.hasSuffix(".hdslb.com") else { return nil }
        return url.absoluteString
    }
    private static func rows(_ data: Data) throws -> [[String: Any]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = root["code"] as? Int else { throw GardenError.invalid("原站返回的搜索信息无法读取。") }
        guard code == 0 else { throw GardenError.invalid("原站搜索服务暂不可用（\(code)）。") }
        guard let body = root["data"] as? [String: Any] else { throw GardenError.invalid("原站没有返回搜索数据。") }
        // Empty searches may return null rather than an array.
        if body["result"] == nil || body["result"] is NSNull { return [] }
        guard let rows = body["result"] as? [[String: Any]] else { throw GardenError.invalid("原站返回的搜索结果格式有误。") }
        return rows
    }
    public static func videos(_ data: Data) throws -> [LessonVideoCandidate] {
        try rows(data).compactMap { row in
            guard let bv = row["bvid"] as? String, bv.count == 12, bv.range(of: "^BV[A-Za-z0-9]{10}$", options: .regularExpression) != nil else { return nil }
            let title = text(row["title"] as? String ?? ""), author = text(row["author"] as? String ?? "")
            guard !title.isEmpty, !author.isEmpty else { return nil }
            return LessonVideoCandidate(bvid: bv, title: title, author: author, thumbnail: imageURL(row["pic"] as? String), duration: TimeLabel.seconds(row["duration"] as? String ?? ""))
        }
    }
    public static func articles(_ data: Data, lesson: Lesson, checkedAt: String) throws -> [StudyResource] {
        try rows(data).compactMap { row in
            guard let id = row["id"] as? Int, id > 0 else { return nil }
            let title = text(row["title"] as? String ?? ""), author = text(row["author"] as? String ?? "")
            guard !author.isEmpty, matches(title, lesson: lesson, context: author) else { return nil }
            let category = articleCategory(title)
            var item = StudyResource(id: "live-\(lesson.id)-cv\(id)", lessonID: lesson.id, title: title, kind: category == "试讲稿" ? .script : .link, url: "https://www.bilibili.com/read/cv\(id)", source: author + " · B站专栏原文")
            item.category = category; item.checkedAt = checkedAt
            item.thumbnail = imageURL((row["image_urls"] as? [String])?.first)
            return item
        }
    }
    public static func articleCategory(_ title: String) -> String {
        if title.contains("说课") { return "说课稿" }
        if ["试讲稿", "逐字稿", "试讲"].contains(where: title.contains) { return "试讲稿" }
        if ["教学设计", "教案", "教学实录"].contains(where: title.contains) { return "教学设计" }
        return "课文解读"
    }
    public static func keys(_ lesson: Lesson) -> [String] {
        let aliases = ["7d-02":["说和做"], "8u-04":["飞天凌空"], "8u-05":["一着惊海天"], "9u-05":["你是人间的四月天"], "8u-21":["人民英雄永垂不朽"], "7d-extra3-4":["晚春二首·其一"], "7d-extra6-3":["过松源晨炊漆公店六首·其五"], "9u-extra6-2":["无题·相见时难别亦难"]]
        let anthologies = ["短文两篇", "短文二篇", "散文二篇", "散文诗二首", "古代诗歌四首", "古代诗歌五首", "唐诗五首", "诗词五首", "词四首", "诗词三首", "诗词曲五首", "短诗五首", "唐诗三首", "《世说新语》二则", "《孟子》三章", "《诗经》二首", "《庄子》二则", "《礼记》二则", "消息二则", "阿西莫夫短文两篇", "寓言四则"]
        let titles = anthologies.contains(lesson.title) ? lesson.focus.filter { $0 != "课外古诗词诵读" } : [lesson.title] + (aliases[lesson.id] ?? [])
        return titles.map { $0.replacingOccurrences(of: "（节选）", with: "").replacingOccurrences(of: "(节选)", with: "").components(separatedBy: "——")[0] }.filter { !$0.isEmpty }
    }
    /// At most five named works, three first-page searches each; never use arbitrary teaching focus.
    public static func discoveryKeywords(_ lesson: Lesson) -> [String] {
        var seen = Set<String>()
        return keys(lesson).filter { seen.insert($0).inserted }.prefix(5).map { $0 + " 语文" }
    }
    public static func matches(_ raw: String, lesson: Lesson, context: String = "") -> Bool {
        let title = text(raw)
        let teaching = ["语文", "教学", "教案", "试讲", "说课", "课文", "课堂", "朗读", "初中", "七年级", "八年级", "九年级"]
        return keys(lesson).contains { key in
            if key.count > 2 { return normalized(title).contains(normalized(key)) }
            // A short work title must be a whole title/token plus author or teaching context.
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let whole = title.range(of: "(^|[^\\p{Han}A-Za-z])" + escaped + "($|[^\\p{Han}A-Za-z])", options: .regularExpression) != nil
            let prefix = title.hasPrefix(key) && teaching.contains { title.dropFirst(key.count).hasPrefix($0) }
            let hasContext = teaching.contains { (title + context).contains($0) } || (!lesson.author.isEmpty && (title + context).contains(lesson.author))
            return (whole || prefix) && hasContext
        }
    }
    private static func normalized(_ value: String) -> String { value.replacingOccurrences(of: "[^\\p{Han}A-Za-z0-9]", with: "", options: .regularExpression).lowercased() }
    public static func resources(_ candidate: LessonVideoCandidate, parts: [BilibiliPart], lesson: Lesson, checkedAt: String) -> [StudyResource] {
        parts.compactMap { part in
            // A collection title cannot identify a lesson's episode. Match its actual part.
            let title = text(part.part)
            let match = matches(title, lesson: lesson, context: candidate.author + " " + candidate.title)
            guard match || (parts.count == 1 && matches(candidate.title, lesson: lesson, context: candidate.author)) else { return nil }
            let seconds = part.duration ?? (parts.count == 1 ? candidate.duration : nil)
            guard let duration = seconds, (1...86400).contains(duration) else { return nil }
            var item = StudyResource(id: "live-\(lesson.id)-\(candidate.bvid)-\(part.cid)", lessonID: lesson.id, title: match ? title : candidate.title, kind: .video, url: "https://www.bilibili.com/video/\(candidate.bvid)/?p=\(part.page)", source: candidate.author)
            item.videoCID = part.cid; item.durationSeconds = duration; item.thumbnail = candidate.thumbnail; item.checkedAt = checkedAt
            item.category = (title + candidate.title).contains("试讲") ? "面试讲解" : "课堂示范"
            return item
        }
    }
    public static func identity(_ item: StudyResource) -> String {
        if item.kind == .video, let ref = try? BilibiliPlayback.reference(item.url), let cid = item.videoCID { return "\(item.lessonID)-\(ref.bvid)-\(cid)" }
        if let url = URL(string: item.url), ["www.bilibili.com", "bilibili.com"].contains(url.host ?? ""), url.path.hasPrefix("/read/cv"), let cv = url.pathComponents.last, cv.hasPrefix("cv"), Int(cv.dropFirst(2)).map({ $0 > 0 }) == true { return item.lessonID + "-" + cv }
        return "id-" + item.id
    }
    /// Add/update metadata only. Preserve curated IDs, all existing links, and every annotation relationship.
    public static func merge(_ incoming: [StudyResource], into saved: [StudyResource]) -> (resources: [StudyResource], addedIDs: Set<String>) {
        var result = saved, added = Set<String>()
        for item in incoming {
            if let index = result.firstIndex(where: { identity($0) == identity(item) || $0.id == item.id }) {
                // Keep editorial titles/categories and IDs; only update the current part URL and CID.
                if item.kind == .video { result[index].url = item.url; result[index].videoCID = item.videoCID }
            } else { result.append(item); added.insert(item.id) }
        }
        return (result, added)
    }
}
