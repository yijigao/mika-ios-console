import SwiftUI

@MainActor struct TaskListView: View {
    @EnvironmentObject private var store: ConsoleStore
    @State private var path: [String] = []
    @State private var showCreate = false
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.client == nil { Text("请先在“连接”页保存基址与令牌。") }
                if let error = store.error { Section("同步提示") { Text(error).font(.footnote).foregroundStyle(.red) } }
                if store.refreshing { ProgressView("正在对齐任务状态…") }
                Section("最近任务与本机恢复记录") {
                    if store.savedIDs.isEmpty { Text("暂无任务，下拉刷新或新建任务。提交后请等待响应，勿重复操作。") .foregroundStyle(.secondary) }
                    ForEach(store.orderedIDs, id: \.self) { id in
                        NavigationLink(value: id) {
                            VStack(alignment: .leading, spacing: 5) {
                                if let task = store.tasks[id] {
                                    Text(task.goal).lineLimit(2)
                                    Text(task.statusLabel).font(.subheadline).foregroundStyle(.secondary)
                                    if let date = task.created { Text(date, format: .dateTime.year().month().day().hour().minute().second()).font(.caption) }
                                    else { Text("服务端未提供创建时间").font(.caption).foregroundStyle(.secondary) }
                                } else { Text("待恢复 / 暂不可用") }
                                Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if let error = store.taskErrors[id] { Text(error).font(.caption).foregroundStyle(.red) }
                            }
                        }
                    }
                }
                Section { SafetyNotice() }
            }
            .navigationTitle("Mika 控制台")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.client == nil || store.refreshing).accessibilityLabel("刷新任务") }
                ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") }.disabled(store.client == nil).accessibilityLabel("新建任务") }
            }
            .refreshable { await store.refresh() }
            .navigationDestination(for: String.self) { TaskDetailView(id: $0) }
            .sheet(isPresented: $showCreate) {
                NewTaskView { id in showCreate = false; path.append(id) }.environmentObject(store)
            }
        }
    }
}

@MainActor struct NewTaskView: View {
    @EnvironmentObject private var store: ConsoleStore
    @Environment(\.dismiss) private var dismiss
    @State private var goal = ""
    @State private var conversation = ""
    let onCreated: (String) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("任务目标") {
                    TextEditor(text: $goal).frame(minHeight: 160).accessibilityLabel("任务目标")
                    Text("服务端返回的输入上限可在连接检测结果查看；超限会显示服务端校验错误。") .font(.footnote).foregroundStyle(.secondary)
                }
                Section("可选：继续远程对话") {
                    TextField("conversation ID（可留空）", text: $conversation).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section { SafetyNotice() }
                if let error = store.error { Section("提交提示") { Text(error).foregroundStyle(.red) } }
                Button("提交任务") {
                    Task {
                        if let id = await store.create(goal: goal.trimmingCharacters(in: .whitespacesAndNewlines), conversation: conversation.trimmingCharacters(in: .whitespacesAndNewlines)) { onCreated(id) }
                    }
                }.disabled(store.submitting || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.submitting { ProgressView("正在提交，请勿重复操作…") }
            }
            .navigationTitle("新建任务")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(store.submitting) } }
            .interactiveDismissDisabled(store.submitting)
        }
    }
}

@MainActor struct TaskDetailView: View {
    let id: String
    @EnvironmentObject private var store: ConsoleStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var monitorID = UUID()
    private var task: RemoteTask? { store.tasks[id] }
    var body: some View {
        List {
            Section("任务") {
                Text(id).font(.caption.monospaced()).textSelection(.enabled)
                if let task {
                    Text(task.goal).textSelection(.enabled)
                    LabeledContent("状态", value: task.statusLabel)
                    if let created = task.created { LabeledContent("创建时间") { Text(created, format: .dateTime) } }
                    if task.isTerminal { LabeledContent("耗时", value: task.duration) }
                    if let progress = task.progress { Text(progress).textSelection(.enabled) }
                } else { ProgressView("正在获取任务…") }
            }
            if let error = store.taskErrors[id] {
                Section("连接 / 协议提示") { Text(error).foregroundStyle(.red); Text("非 404 错误将降级每 5 秒查询；旧状态可能已过期。404 可能表示安卓服务重启丢失任务索引，不会重新提交。") .font(.footnote) }
            }
            if let task {
                if let question = task.question { Section("当前追问") { Text(question).textSelection(.enabled) } }
                if task.status == "waiting_on_phone" { Section { Text("请在安卓手机上完成操作。这里无法代答、同意或付款。") } }
                if task.canAnswer || task.canSteer {
                    Section(task.canAnswer ? "回答追问" : "追加要求") {
                        TextEditor(text: $text).frame(minHeight: 100).accessibilityLabel(task.canAnswer ? "回答内容" : "追加要求内容")
                        Button(task.canAnswer ? "发送回答" : "发送追加要求") { perform(task.canAnswer ? "answer" : "steer") }
                            .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !task.isTerminal {
                    Section { Button("请求取消任务", role: .destructive) { perform("cancel") }.disabled(busy)
                        Text("仅查询到“已取消”才代表取消生效；请求被接受不代表已经停止。") .font(.footnote).foregroundStyle(.secondary) }
                }
                if task.isTerminal { Section("最终结果") { Text(task.result ?? "服务端未返回结果文本，请查看下方原始任务状态。").textSelection(.enabled) } }
                Section("状态流（本次打开期间观察）") {
                    ForEach(store.events[id] ?? []) { event in
                        VStack(alignment: .leading) { Text(event.date, format: .dateTime.hour().minute().second()).font(.caption); Text(event.text) }
                    }
                }
                Section("完整任务状态 / 追加要求去向") {
                    Text(store.client?.redact(task.payload.pretty) ?? task.payload.pretty).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            if busy { ProgressView("正在发送…") }
            if let notice { Section("操作回执") { Text(notice).textSelection(.enabled) } }
            Section { SafetyNotice() }
        }
        .navigationTitle("任务详情")
        .toolbar { Button("重新对齐") { monitorID = UUID() }.disabled(busy) }
        .task(id: "\(scenePhase)-\(store.connectionID)-\(monitorID)") {
            if scenePhase == .active { await store.watch(id: id) }
        }
    }
    private func perform(_ name: String) {
        guard !busy else { return }; busy = true; notice = nil
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { busy = false; monitorID = UUID() }
            do { notice = try await store.action(id: id, name: name, text: input); if name != "cancel" { text = "" } }
            catch { notice = "请求结果未确认，请查询当前状态；不要自动重发。\n" + store.message(error) }
        }
    }
}
