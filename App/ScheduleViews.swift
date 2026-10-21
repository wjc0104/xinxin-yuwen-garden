import SwiftUI
import GardenCore

struct ScheduleView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var bark = BarkBridge.shared
    @State private var date = Date()
    @State private var selected: Occurrence?
    var days: [Date] {
        let cal = GardenDate.calendar
        let weekday = cal.component(.weekday, from: date)
        let monday = cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: cal.startOfDay(for: date))!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }
    var courses: [Occurrence] { store.occurrences.filter { $0.date == GardenDate.string(date) } }
    var body: some View {
        GardenPage {
            HStack {
                DatePicker("日期", selection: $date, displayedComponents: .date).labelsHidden()
                Spacer()
                Button("今天") { date = Date() }
            }
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let active = GardenDate.string(day) == GardenDate.string(date)
                    Button { date = day } label: {
                        VStack(spacing: 8) { Text(["一","二","三","四","五","六","日"][index]).font(.caption); Text(String(GardenDate.calendar.component(.day, from: day))).font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 12).background(active ? GardenTheme.rose : GardenTheme.card).foregroundColor(active ? .white : .primary).clipShape(RoundedRectangle(cornerRadius: 12))
                    }.accessibilityLabel("星期" + ["一","二","三","四","五","六","日"][index])
                }
            }
            NavigationLink(destination: BarkView()) { HStack { Image(systemName: "bell"); Text(bark.status).font(.caption); Spacer(); Image(systemName: "chevron.right").font(.caption) } }.padding(.vertical, 5)
            ForEach(["上午","下午","晚上"], id: \.self) { section in
                let items = courses.filter { section == "上午" ? $0.startMinute < 720 : section == "下午" ? $0.startMinute >= 720 && $0.startMinute < 1080 : $0.startMinute >= 1080 }
                if !items.isEmpty {
                    Text(section).font(.headline)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { selected = item } label: {
                            GardenCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) { Text(TimeLabel.clock(item.startMinute)).font(.title2.weight(.semibold).monospacedDigit()); Text(TimeLabel.clock(item.endMinute)).font(.caption.monospacedDigit()).foregroundColor(.secondary) }.frame(width: 80, alignment: .leading)
                                    Rectangle().fill(item.subject == "作文" ? GardenTheme.rose : GardenTheme.mint).frame(width: 3, height: 44)
                                    VStack(alignment: .leading, spacing: 6) { Text("\(item.subject) · \(item.classNumber)班").font(.headline); Text("第\(item.period)节" + (item.group == nil ? "" : " · 连堂作文")).font(.caption).foregroundColor(.secondary) }
                                    Spacer(); Image(systemName: "pencil").foregroundColor(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        if index + 1 < items.count, item.group != nil, item.group == items[index+1].group, items[index+1].startMinute - item.endMinute == 15 { Text("休息15分钟").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity) }
                    }
                }
            }
            if courses.isEmpty { GardenEmpty(title: "这一天没有课", detail: GardenDate.string(date) < store.data.termStart || GardenDate.string(date) > store.data.termEnd ? "日期不在当前学期内，可在“我的”修改学期。" : "可以准备下一次的课程。") }
            if !store.data.changes.isEmpty { NavigationLink("调课记录", destination: ChangesView()) }
        }.navigationTitle("课表")
        .sheet(item: $selected) { ScheduleEditor(occurrence: $0) }
    }
}
struct ScheduleEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let occurrence: Occurrence
    @State private var scope = ChangeScope.once
    @State private var cancelled = false
    @State private var moveGroup = true
    @State private var date = Date()
    @State private var start = Date()
    @State private var end = Date()
    @State private var problem: String?
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("\(occurrence.subject) · \(occurrence.classNumber)班")) {
                    Picker("修改范围", selection: $scope) { Text("仅这一次").tag(ChangeScope.once); Text("以后每周").tag(ChangeScope.fromDate) }.pickerStyle(.segmented)
                    Toggle("停课", isOn: $cancelled)
                    if occurrence.group != nil { Toggle("两节作文一起调整", isOn: $moveGroup) }
                }
                if !cancelled { Section(header: Text("新的上课时间")) {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
                    if occurrence.group != nil && moveGroup { Caption(text: "按这一节的时长调整两节课，中间保留15分钟休息。") }
                } }
                if let problem = problem { Text(problem).foregroundColor(.red) }
            }.navigationTitle("调整课程").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
            .onAppear { date = GardenDate.parse(occurrence.date) ?? Date(); start = GardenDate.at(occurrence.date, minute: occurrence.startMinute) ?? Date(); end = GardenDate.at(occurrence.date, minute: occurrence.endMinute) ?? Date() }
        }.navigationViewStyle(.stack)
    }
    private func minute(_ value: Date) -> Int { let c = GardenDate.calendar.dateComponents([.hour,.minute], from: value); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    private func save() {
        let begin = minute(start), finish = minute(end)
        guard cancelled || finish > begin else { problem = "结束时间要晚于开始时间。"; return }
        if scope == .fromDate, let anchor = GardenDate.parse(occurrence.originalDate) {
            let shift = GardenDate.calendar.dateComponents([.day], from: anchor, to: date).day ?? 0
            guard abs(shift) <= 6 else { problem = "每周调课请选择原课次前后6天内的日期。"; return }
        }
        let related = moveGroup && occurrence.group != nil ? store.occurrences.filter { $0.originalDate == occurrence.originalDate && $0.group == occurrence.group } : [occurrence]
        do {
            let changes = try ScheduleEngine().movedChanges(occurrence: occurrence, related: related, targetDate: GardenDate.string(date), startMinute: begin, endMinute: finish, scope: scope, cancelled: cancelled)
            if store.update({ $0.changes.append(contentsOf: changes) }) { dismiss() }
        } catch { problem = error.localizedDescription }
    }
}
struct ChangesView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List { ForEach(store.data.changes.reversed()) { change in
            let slot = store.data.slots.first { $0.id == change.slotID }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(slot?.subject ?? "课程") · \(slot?.classNumber ?? 0)班 · " + change.date)
                Caption(text: (change.scope == .once ? "仅这一次" : "此后每周") + (change.cancelled ? " · 停课" : " → " + (change.targetDate ?? change.date)))
                Button("撤销修改") { store.update { $0.changes.removeAll { $0.id == change.id } } }
            }
        } }.navigationTitle("调课记录")
    }
}
