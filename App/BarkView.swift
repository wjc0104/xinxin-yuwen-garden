import SwiftUI

struct BarkView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var bark = BarkBridge.shared
    @State private var address = ""
    @State private var connection = ""
    @State private var showService = false
    var body: some View {
        GardenPage {
            GardenCard {
                Label("让 iPhone 16 提醒你", systemImage: "bell.badge").font(.headline)
                Text("提前一小时收到上课时间和班级。作文连堂提醒一次，中间休息照常。").font(.subheadline)
                Label(bark.status, systemImage: bark.enabled ? "bell.fill" : "bell.slash").font(.subheadline).foregroundColor(bark.enabled ? GardenTheme.mint : .secondary)
            }
            GardenCard {
                Text("1 · 设置接收手机").font(.headline)
                Link("在 iPhone 16 安装 Bark", destination: URL(string: "https://apps.apple.com/cn/app/id1403753865")!)
                Caption(text: "在 Bark 允许通知，将首页的推送地址粘贴到这里。无需日历权限。")
                SecureField("粘贴 Bark 推送地址", text: $address).textContentType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(bark.enabled)
                Button("保存接收手机") { do { try bark.save(address: address, connection: connection) } catch { store.error = error.localizedDescription } }.disabled(bark.enabled || bark.busy)
                Button("发送测试通知") { Task { do { try await bark.test() } catch { store.error = error.localizedDescription } } }.disabled(bark.address.isEmpty || bark.busy)
            }
            GardenCard {
                Text("2 · 自动上课提醒").font(.headline)
                Text("在线服务负责定时发送，XR 和电脑关机后也能继续。接收手机需要联网。").font(.subheadline)
                DisclosureGroup("连接定时服务", isExpanded: $showService) {
                    SecureField("粘贴服务连接", text: $connection).textInputAutocapitalization(.never).disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(bark.enabled)
                    Caption(text: "服务尚未部署时可以先测试接收通知，自动提醒不会自行开启。")
                }
                if bark.enabled {
                    Button("更新提醒") { Task { do { try await bark.refresh(store.data) } catch { store.error = error.localizedDescription } } }
                    Button("停用自动提醒", role: .destructive) { Task { do { try await bark.stop() } catch { store.error = error.localizedDescription } } }
                } else {
                    Button("启用自动提醒") { Task { do { try bark.save(address: address, connection: connection); try await bark.enable(store.data) } catch { store.error = error.localizedDescription } } }
                }
                if bark.busy { ProgressView("正在连接…") }
                Caption(text: "调课保存后会自动更新在线安排。未更新成功会明确提示；网络推送可能延迟，早起叫醒建议保留系统闹钟。")
            }.disabled(bark.busy)
        }.navigationTitle("上课提醒").navigationBarTitleDisplayMode(.inline)
        .onAppear { address = bark.address; connection = bark.connectionLink; showService = !connection.isEmpty }
    }
}
