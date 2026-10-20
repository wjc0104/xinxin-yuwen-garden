import SwiftUI
import GardenCore

struct ScheduleView: View {
    @EnvironmentObject var store: AppStore
    @State private var date = Date()
    @State private var selected: Occurrence?
    @State private var weekly = false
    private var day: String { GardenDate.string(date) }
    private var courses: [Occurrence] { store.occurrences.filter { $0.date == day } }
    var body: some View {
        GardenPage {
            GardenCard {
                Text("上课的小约定").font(.title2.bold())
                Text("好好备课，也记得留一点时间给自己。🌿").font(.subheadline).foregroundColor(.secondary)
                Caption(text: "小数字是班级。周四作文分两节，中间各休息 15 分钟。")
                NavigationLink(destination: CalendarSyncView()) { Label("同步到日历，提醒 iPhone 16", systemImage: "bell.badge") }
                if !store.data.termConfirmed { Caption(text: "学期日期尚未确认，暂不生成提醒。请先在“我的”设置学期。") }
                Picker("课表视图", selection: $weekly) { Text("按日期").tag(false); Text("每周原课表").tag(true) }.pickerStyle(.segmented)
            }
            if weekly {
                ForEach(2...6, id: \.self) { weekday in
                    Text([2:"星期一",3:"星期二",4:"星期三",5:"星期四",6:"星期五"][weekday]!).font(.headline)
                    GardenCard { ForEach(store.data.slots.filter { $0.weekday == weekday }) { slot in
                        HStack { VStack(alignment: .leading, spacing: 6) { Text("第\(slot.period)节 · \(slot.subject) · \(slot.classNumber)班"); Caption(text: TimeLabel.clock(slot.startMinute) + "—" + TimeLabel.clock(slot.endMinute)) }; Spacer() }
                        if slot.id != store.data.slots.last(where: { $0.weekday == weekday })?.id { Divider() }
                    } }
                }
                Caption(text: "这里显示每周原始安排；临时与长期调课的实际结果请切换“按日期”查看。")
            } else {
                DatePicker("选择日期", selection: $date, displayedComponents: .date).environment(\.timeZone, GardenDate.calendar.timeZone).datePickerStyle(.compact)
                ForEach(courses) { occurrence in Button { selected = occurrence } label: { GardenCard { HStack { Text("\(occurrence.subject) · \(occurrence.classNumber)班").font(.headline); Spacer(); Text("第\(occurrence.period)节").font(.caption) }; Text(TimeLabel.clock(occurrence.startMinute) + "—" + TimeLabel.clock(occurrence.endMinute)).foregroundColor(GardenTheme.mint); Caption(text: "点此临时调课、停课或从本周起修改") } }.buttonStyle(.plain) }
                if courses.isEmpty { GardenEmpty(title: "今天没有安排课程", detail: day < store.data.termStart || day > store.data.termEnd ? "当前日期不在所设学期内；请在“我的”核对学期日期。" : "可以安心准备下一节课啦。") }
                if !store.data.changes.isEmpty { NavigationLink("查看调课记录与撤销", destination: ChangesView()) }
            }
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
        NavigationView { Form {
            Section(header: Text("\(occurrence.subject) · \(occurrence.classNumber)班 · 第\(occurrence.period)节")) {
                Caption(text: "原课次编号：" + occurrence.originalDate + "；调课后请重新同步日历。")
                Picker("修改范围", selection: $scope) { Text("只改这一次").tag(ChangeScope.once); Text("从原课次起每周").tag(ChangeScope.fromDate) }
                Toggle("本次停课／此后停课", isOn: $cancelled)
                if occurrence.group != nil { Toggle("作文两节一起调整", isOn: $moveGroup); Caption(text: "一起移动时保留两节之间的休息；提醒仍分别生成。") }
            }
            if !cancelled { Section(header: Text("调整后的上课时间")) {
                DatePicker("日期", selection: $date, displayedComponents: .date)
                DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
            } }
            if let problem = problem { Text(problem).foregroundColor(.red) }
        }.environment(\.timeZone, GardenDate.calendar.timeZone).navigationTitle("调整课程").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear { date = GardenDate.parse(occurrence.date) ?? Date(); start = GardenDate.at(occurrence.date, minute: occurrence.startMinute) ?? Date(); end = GardenDate.at(occurrence.date, minute: occurrence.endMinute) ?? Date() }
        }.navigationViewStyle(.stack)
    }
    private func minute(_ value: Date) -> Int { let c = GardenDate.calendar.dateComponents([.hour,.minute], from: value); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    private func save() {
        let startMinute = minute(start), endMinute = minute(end)
        guard cancelled || endMinute > startMinute else { problem = "结束时间要晚于开始时间。"; return }
        let target = GardenDate.string(date)
        if scope == .fromDate, let anchor = GardenDate.parse(occurrence.originalDate) {
            let shift = GardenDate.calendar.dateComponents([.day], from: anchor, to: date).day ?? 0
            guard abs(shift) <= 6 else { problem = "长期调课请选择原课次前后 6 天以内的新星期；跨周单次调课可选择“只改这一次”。"; return }
        }
        let related = moveGroup && occurrence.group != nil ? store.occurrences.filter { $0.originalDate == occurrence.originalDate && $0.group == occurrence.group } : [occurrence]
        let changes: [ScheduleChange]
        do { changes = try ScheduleEngine().movedChanges(occurrence: occurrence, related: related, targetDate: target, startMinute: startMinute, endMinute: endMinute, scope: scope, cancelled: cancelled) }
        catch { problem = error.localizedDescription; return }
        if store.update({ $0.changes.append(contentsOf: changes) }) { store.notice = "课表已更新。请点“同步到日历”更新 iPhone 16 使用的日历提醒。"; dismiss() }
    }
}
struct ChangesView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { List { ForEach(store.data.changes.reversed()) { change in VStack(alignment: .leading, spacing: 8) { Text(change.date + " · " + change.slotID); Caption(text: (change.scope == .once ? "仅这一次" : "此后每周") + (change.cancelled ? " · 停课" : " → " + (change.targetDate ?? change.date))); Button("撤销此节修改") { store.update { $0.changes.removeAll { $0.id == change.id } }; store.notice = "已撤销，请重新同步日历。" } } } }.navigationTitle("调课记录") }
}

struct CalendarSyncView: View {
    @EnvironmentObject var store: AppStore
    @State private var accounts: [CalendarAccount] = []
    @State private var sourceID = ""
    @State private var busy = false
    @State private var review: [String] = []
    @State private var confirmOverride = false
    @State private var proposals: [ScheduleChange] = []
    @State private var confirmImport = false
    @State private var bound = false
    @State private var result = ""
    var body: some View {
        GardenPage {
            GardenCard {
                Label("让主力机温柔提醒你", systemImage: "bell.badge").font(.headline)
                Text("XR 写入 iCloud 日历 → 同一 Apple ID 的 iPhone 16 系统日历提醒。").font(.subheadline)
                Caption(text: "请在两台手机开启 iCloud“日历”，在 16 上勾选小花园日历并允许日历通知。首次同步、断网或系统限制可能延迟，无法保证即时送达。同步完成后，16 的系统日历负责提醒。")
            }
            GardenCard {
                Text("权限由你决定").font(.headline)
                Caption(text: "仅点击下方按钮后请求日历权限。系统授权范围包含日历数据；应用只查询自己的课程编号，并在绑定的专用日历内按私有标记恢复编号，只写入专用日历。不开权限仍可学习和查看课表。")
                Text("学期：\(store.data.termStart) 至 \(store.data.termEnd)\n提前 \(store.data.reminderMinutes) 分钟提醒").font(.subheadline)
                if !store.data.termConfirmed { Text("请先到“我的”确认学期日期。").foregroundColor(GardenTheme.rose) }
                Button(busy ? "正在处理…" : "允许访问并检查日历账户") { authorize() }.disabled(busy || !store.data.termConfirmed)
                if !bound && !accounts.isEmpty {
                    Picker("写入账户", selection: $sourceID) { Text("请选择 iCloud 账户").tag(""); ForEach(accounts) { Text($0.title).tag($0.id) } }
                    Caption(text: "必须选择能同步到 16 的同一 iCloud 账户。本机日历不会跨设备同步；账户名称由系统提供，请核对。")
                    Button("新建专用日历并写入课程") { connectAndSync() }.disabled(sourceID.isEmpty || busy)
                }
                if bound { Caption(text: "绑定账户：" + (store.calendar.boundTitle() ?? "需要授权后检查")); Button("更新专用日历中的课程") { synchronize() }.disabled(busy || !store.data.termConfirmed) }
                if !result.isEmpty { Text(result).font(.subheadline).foregroundColor(GardenTheme.mint) }
            }
            if !review.isEmpty {
                GardenCard {
                    Text("日历里有新的变化").font(.headline)
                    Caption(text: "这些课程在系统日历中被改过或删除。已停止同步。可以采用日历的时间／停课修改，或以本机课表覆盖；课程名称和提醒分钟仍以本机设置为准。")
                    ForEach(Array(review.prefix(30).enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                    if review.count > 30 { Caption(text: "另有 \(review.count - 30) 项。") }
                    if proposals.count == review.count { Button("采用日历时间与停课，并重新同步") { confirmImport = true } }
                    else { Caption(text: "部分变化为全天或跨天课程，不能自动导入；请先在课表手动核对。") }
                    Button("已核对，以本机课表重新写入") { confirmOverride = true }.foregroundColor(GardenTheme.rose)
                }
            }
            Caption(text: "调课后请手动同步。XR 关机前，已同步到 16 的课程由 16 独立提醒；后来在 XR 修改但尚未同步的内容不会出现在 16。应用不发送消息，也不申请自身通知权限。")
        }.navigationTitle("同步上课提醒").navigationBarTitleDisplayMode(.inline)
        .onAppear { bound = store.calendar.hasBinding }
        .alert("覆盖已修改的课程？", isPresented: $confirmOverride) { Button("以本机课表覆盖", role: .destructive) { synchronize(force: true) }; Button("先保留日历变化", role: .cancel) {} } message: { Text("会把专用日历中由小花园创建的课程恢复为当前本机课表，并重建已删除的课程。其他日历不受影响。") }
        .alert("采用日历的上课安排？", isPresented: $confirmImport) { Button("采用并同步") { if store.update({ $0.changes.append(contentsOf: proposals) }) { synchronize(force: true) } }; Button("取消", role: .cancel) {} } message: { Text("\(proposals.count) 项变化会保存为单次调课／停课。课程名称和提前提醒分钟数仍按本机设置重新写入。") }
    }
    private func authorize() {
        busy = true
        Task { do { try await store.calendar.requestAccess(); accounts = try store.calendar.accounts(); bound = store.calendar.hasBinding } catch { store.error = error.localizedDescription }; busy = false }
    }
    private func connectAndSync() { do { try store.calendar.connect(sourceID: sourceID); bound = true; synchronize() } catch { store.error = error.localizedDescription } }
    private func synchronize(force: Bool = false) {
        busy = true; defer { busy = false }
        do { let count = try store.calendar.sync(store.data, overwriteReviewed: force); review = []; result = "已向账户日历写入 \(count) 节课。请在 iPhone 16 的系统日历确认课程与通知；这里无法确认 16 是否收到。" }
        catch let changes as CalendarReview { review = changes.messages; proposals = changes.proposals; result = "发现外部修改，尚未写入。" }
        catch { store.error = error.localizedDescription }
    }
}
