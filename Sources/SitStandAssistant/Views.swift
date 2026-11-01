import SwiftUI
import ServiceManagement

private let accent = Color(red: 0.12, green: 0.46, blue: 0.39)

@MainActor
final class LoginItem: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var message: String?

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        if SMAppService.mainApp.status == .requiresApproval { message = "请在系统设置 → 通用 → 登录项中允许坐站助手。" }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch { message = "登录启动设置失败：\(error.localizedDescription)" }
        refresh()
    }
}

struct MainView: View {
    @ObservedObject var engine: Engine
    @StateObject private var login = LoginItem()
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "figure.stand.line.dotted.figure.stand")
                    .font(.system(size: 27, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 48, height: 48).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("坐站助手").font(.system(size: 22, weight: .semibold))
                    Text("给专注留一点活动的空隙").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("1.1.0").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }.padding(24)
            Picker("页面", selection: $tab) {
                Text("今日状态").tag(0)
                Text("提醒设置").tag(1)
                Text("每日调度").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if tab == 0 { dashboard }
                    else if tab == 1 { preferences }
                    else { schedule }
                    if let error = engine.storageError { notice(error, warning: true) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Circle().fill(engine.session == nil ? Color.secondary.opacity(0.5) : accent).frame(width: 6, height: 6)
                Text(engine.session == nil ? "随时可以开始" : engine.isDue ? "等待你确认切换姿势" : "提醒运行中")
                Spacer()
                Image(systemName: "menubar.rectangle")
                Text("关闭窗口后，仍在状态栏运行")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 13)
        }
        .frame(minWidth: 620, idealWidth: 680, maxWidth: .infinity, minHeight: 640, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .onAppear { login.refresh() }
    }

    @ViewBuilder private var dashboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Label(engine.session == nil ? "准备开始" : engine.posture.title + " · " + (engine.session?.scheduleKey == nil ? "手动提醒" : "自动时段"), systemImage: engine.posture.symbol)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
                    Text(engine.session == nil ? "坐一会，\n也站一会。" : engine.isDue ? "该换姿势了" : engine.countdown)
                        .font(.system(size: engine.session == nil ? 34 : 46, weight: .semibold, design: engine.session == nil || engine.isDue ? .default : .rounded))
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    Text(engine.session == nil ? "从一个适合你的节奏开始。" : engine.isDue ? "确认后才会切换，当前仍计入\(engine.posture.title)时间。" : "距离下一次\(engine.posture == .sitting ? "站起来" : "坐下")")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: engine.posture.symbol).font(.system(size: 80, weight: .ultraLight))
                    .foregroundStyle(accent.opacity(0.65)).frame(width: 110, height: 130)
            }
            if engine.session == nil {
                HStack(spacing: 12) {
                    Picker("从", selection: Binding(get: { engine.posture }, set: { engine.selectPosture($0) })) {
                        Text("坐着开始").tag(Posture.sitting)
                        Text("站着开始").tag(Posture.standing)
                    }.labelsHidden().frame(width: 150)
                    Button("开始提醒") { engine.start() }.buttonStyle(.borderedProminent).controlSize(.large)
                }
            } else {
                HStack(spacing: 10) {
                    Button(engine.posture.confirmation) { engine.confirm() }.buttonStyle(.borderedProminent).controlSize(.large)
                    if engine.isDue {
                        Button("延后 \(engine.settings.snoozeMinutes) 分钟") { engine.snooze() }.controlSize(.large)
                    }
                    Spacer()
                    Button("结束提醒") { engine.stop() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今天的坐站时间").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(engine.now, format: .dateTime.month().day()).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                statistic("累计坐姿", symbol: "chair.fill", seconds: engine.today.sitting, color: accent)
                statistic("累计站姿", symbol: "figure.stand", seconds: engine.today.standing, color: .orange)
            }
            Text("按你确认的姿势记录；睡眠、用户会话暂离及停止期间不累计。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        notice("提醒是一个轻柔的提示。坐站时长可以按自己的舒适程度调整；应用不会自动识别你的身体姿势。")
    }

    private func statistic(_ title: String, symbol: String, seconds: TimeInterval, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol).font(.system(size: 12)).foregroundStyle(color)
            Text(DayTotal.formatted(seconds)).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("找到你的节奏", subtitle: "时长修改会在下一轮计时生效。")
            card {
                durationRow("坐姿时长", symbol: "chair.fill", key: \.sittingMinutes, range: 1...240)
                Divider()
                durationRow("站姿时长", symbol: "figure.stand", key: \.standingMinutes, range: 1...240)
                Divider()
                durationRow("延后时长", symbol: "clock.arrow.circlepath", key: \.snoozeMinutes, range: 1...60)
            }
            card {
                Toggle("播放提示音", isOn: setting(\.soundEnabled))
                Text("默认静音。开启后，提醒等待确认期间每 30 秒播放一次。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider().padding(.vertical, 5)
                Toggle("登录 Mac 时自动启动", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if let message = login.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("打开系统登录项") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            notice("设置和统计仅保存在这台 Mac。退出后重新打开会恢复计时；退出和睡眠期间不能显示提醒。")
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("让提醒融入工作日", subtitle: "每个时段从坐姿开始，到结束时间自动停止。")
            card {
                Toggle("按时段自动开始和结束", isOn: setting(\.scheduleEnabled))
                Divider().padding(.vertical, 5)
                Toggle("仅周一至周五生效", isOn: setting(\.weekdaysOnly))
                Text("不识别法定节假日和调休。手动开始的提醒由你结束。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            card {
                HStack {
                    Text("每日时段").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(engine.settings.periods.count) / 12").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(engine.settings.periods) { period in
                    HStack(spacing: 12) {
                        Image(systemName: "clock").foregroundStyle(accent)
                        DatePicker("开始", selection: periodTime(period.id, start: true), displayedComponents: .hourAndMinute).labelsHidden()
                        Text("至").foregroundStyle(.secondary)
                        DatePicker("结束", selection: periodTime(period.id, start: false), displayedComponents: .hourAndMinute).labelsHidden()
                        Spacer()
                        Button { engine.updateSettings { $0.periods.removeAll { $0.id == period.id } } } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }.buttonStyle(.borderless).help("删除时段")
                    }.padding(.vertical, 5)
                }
                Button {
                    engine.updateSettings { settings in
                        let start = min(1380, settings.periods.map(\.end).max() ?? 540)
                        settings.periods.append(SchedulePeriod(start: start, end: min(1439, start + 60)))
                    }
                } label: { Label("添加时段", systemImage: "plus") }
                .disabled(engine.settings.periods.count >= 12)
            }
            if let error = engine.settings.scheduleError { notice(error + " 自动调度已暂停。", warning: true) }
            notice("调度需要应用正在运行。关闭设置窗口没有影响；如希望每天生效，可在提醒设置中开启登录启动。同一时段内手动结束后，不会再次自动开始。")
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 23, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func notice(_ text: String, warning: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: warning ? "exclamationmark.triangle" : "info.circle")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).foregroundStyle(warning ? Color.orange : Color.secondary)
            .lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setting<Value>(_ key: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(get: { engine.settings[keyPath: key] }, set: { value in engine.updateSettings { $0[keyPath: key] = value } })
    }

    private func durationRow(_ title: String, symbol: String, key: WritableKeyPath<Settings, Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Label(title, systemImage: symbol).frame(width: 125, alignment: .leading)
            Spacer()
            TextField("分钟", value: setting(key), format: .number)
                .multilineTextAlignment(.trailing).frame(width: 55).textFieldStyle(.roundedBorder)
            Text("分钟").foregroundStyle(.secondary)
            Stepper(title, value: setting(key), in: range).labelsHidden()
        }.padding(.vertical, 5)
    }

    private func periodTime(_ id: UUID, start: Bool) -> Binding<Date> {
        Binding(get: {
            let period = engine.settings.periods.first { $0.id == id }
            let minutes = (start ? period?.start : period?.end) ?? 0
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: engine.now) ?? engine.now
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            engine.updateSettings { settings in
                guard let index = settings.periods.firstIndex(where: { $0.id == id }) else { return }
                if start { settings.periods[index].start = c.hour! * 60 + c.minute! }
                else { settings.periods[index].end = c.hour! * 60 + c.minute! }
            }
        })
    }
}

struct ReminderView: View {
    @ObservedObject var engine: Engine
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: engine.posture.opposite.symbol).font(.system(size: 53, weight: .light))
                .foregroundStyle(accent).frame(width: 100, height: 100)
                .background(accent.opacity(0.08), in: Circle())
            VStack(spacing: 9) {
                Text(engine.posture == .sitting ? "站起来，换个姿势" : "坐下来，放松一下")
                    .font(.system(size: 25, weight: .semibold))
                Text("准备好了，再确认切换。\n当前仍按\(engine.posture.title)记录时间。")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            }
            Button(engine.posture.confirmation) { engine.confirm() }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(accent)
            Button("延后 \(engine.settings.snoozeMinutes) 分钟") { engine.snooze() }.buttonStyle(.borderless)
            Divider()
            Button("结束提醒") { engine.stop() }.buttonStyle(.borderless).foregroundStyle(.secondary).font(.system(size: 12))
        }.padding(30).frame(width: 360)
    }
}
