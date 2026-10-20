import Foundation

public enum SearchEngine {
    public static func matches(_ query: String, lessons: [Lesson], resources: [StudyResource], marks: [StudyMark]) -> [Lesson] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return lessons }
        return lessons.filter { lesson in
            let extras = resources.filter { $0.lessonID == lesson.id }.map { $0.title + " " + $0.body + " " + $0.source }
            let notes = marks.filter { $0.lessonID == lesson.id }.map { $0.quote + " " + $0.note }
            let text = ([lesson.title, lesson.author] + lesson.focus + extras + notes).joined(separator: " ").lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }
    public static func webURL(source: SearchSource, query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let prefix: String
        let suffix: String
        switch source {
        case .bilibili: prefix = "https://search.bilibili.com/all?keyword="; suffix = ""
        case .all: prefix = "https://www.baidu.com/s?wd="; suffix = ""
        case .smartedu: prefix = "https://www.baidu.com/s?wd="; suffix = " site:basic.smartedu.cn"
        case .resources: prefix = "https://www.baidu.com/s?wd="; suffix = " 教学设计 逐字稿"
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = (trimmed + suffix).addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: prefix + encoded)
    }
    public static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }), let url = URL(string: trimmed),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return url
    }
}
