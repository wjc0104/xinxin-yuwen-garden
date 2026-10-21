import Foundation
print("OS", ProcessInfo.processInfo.operatingSystemVersionString)
let payload = Data(#"{"code":0,"data":{"result":[{"id":11654040,"title":"《<em>春</em>》语文试讲逐字稿","author":"老师","desc":"FULL COPYRIGHTED TEXT","image_urls":[]}]}}"#.utf8)
let root = try JSONSerialization.jsonObject(with: payload) as! [String:Any]
let data = root["data"] as! [String:Any]
let rows = data["result"] as! [[String:Any]]
print("code", type(of: root["code"]!), root["code"] as? Int as Any)
let row = rows[0]
print("id", type(of: row["id"]!), row["id"] as? Int as Any)
var title = row["title"] as! String
print("raw", title, title.utf16.count)
title = title.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
print("stripped", title)
title = title.replacingOccurrences(of: "[\\p{Cc}\\p{Cf}]", with: " ", options: .regularExpression)
print("control-stripped", title)
let pattern = "(^|[^\\p{Han}A-Za-z])" + NSRegularExpression.escapedPattern(for: "春") + "($|[^\\p{Han}A-Za-z])"
print("pattern", pattern)
print("String.range", title.range(of: pattern, options: .regularExpression) as Any)
let regex = try NSRegularExpression(pattern: pattern)
let range = NSRange(title.startIndex..<title.endIndex, in: title)
print("NSRegularExpression", regex.firstMatch(in: title, range: range)?.range as Any)
print("teaching", ["语文", "教学", "试讲"].contains { (title + "老师").contains($0) })

print("escaped", NSRegularExpression.escapedPattern(for: "春"))
for delimiter in ["《春》语文", "朱自清《春》", "春教学设计", "春望 教师试讲", "青春 语文"] {
    print("delimiter", delimiter, delimiter.range(of: pattern, options: .regularExpression) as Any)
}
