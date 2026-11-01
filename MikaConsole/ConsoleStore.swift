import Foundation
import Combine

@MainActor final class ConsoleStore: ObservableObject {
    @Published private(set) var baseAddress: String
    @Published private(set) var client: APIClient?
    @Published private(set) var connectionID = UUID()
    @Published private(set) var tasks: [String: RemoteTask] = [:]
    @Published private(set) var savedIDs: [String] = []
    @Published private(set) var taskErrors: [String: String] = [:]
    @Published private(set) var events: [String: [StateEvent]] = [:]
    @Published var error: String?
    @Published var connectionReport = "尚未检测连接"
    @Published private(set) var refreshing = false
    @Published private(set) var submitting = false
    private let defaults: UserDefaults
    private var refreshGeneration: UUID?
    private var idsKey: String { "taskIDs.v1." + baseAddress }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseAddress = defaults.string(forKey: "baseAddress.v1") ?? ""
        savedIDs = defaults.stringArray(forKey: "taskIDs.v1." + baseAddress) ?? []
        if !baseAddress.isEmpty {
            do {
                if let token = try TokenVault.read(for: baseAddress), !token.isEmpty {
                    client = APIClient(base: try APIClient.normalize(baseAddress), token: token)
                }
            } catch { self.error = "无法读取连接凭据，请在连接页重新保存。" }
        }
    }
    func message(_ error: Error) -> String {
        client?.redact(error.localizedDescription) ?? error.localizedDescription
    }
    func saveConnection(address: String, token: String) throws {
        let base = try APIClient.normalize(address)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, !secret.contains("\n"), !secret.contains("\r") else { throw ClientError.missingToken }
        try TokenVault.save(secret, for: base.absoluteString)
        baseAddress = base.absoluteString; defaults.set(baseAddress, forKey: "baseAddress.v1")
        client = APIClient(base: base, token: secret); connectionID = UUID()
        tasks = [:]; events = [:]; taskErrors = [:]; error = nil
        savedIDs = defaults.stringArray(forKey: idsKey) ?? []
        refreshGeneration = nil; refreshing = false; connectionReport = "已保存，尚未检测"
    }
    func forgetConnection() throws {
        try TokenVault.delete(for: baseAddress)
        client = nil; connectionID = UUID(); error = nil
        tasks = [:]; events = [:]; taskErrors = [:]; savedIDs = []
        defaults.removeObject(forKey: "baseAddress.v1"); baseAddress = ""
        refreshGeneration = nil; refreshing = false; connectionReport = "已移除连接凭据"
    }
    func checkConnection() async {
        guard let client else { return }
        let generation = connectionID
        var parts: [String] = []
        do { parts.append("API / 版本 / 能力 / 输入上限\n" + client.redact(try await client.request().pretty)) }
        catch { parts.append("API 检测失败\n" + client.redact(error.localizedDescription)) }
        guard generation == connectionID, !Task.isCancelled else { return }
        do { parts.append("设备状态\n" + client.redact(try await client.request(["device"]).pretty)) }
        catch { parts.append("设备检测失败\n" + client.redact(error.localizedDescription)) }
        guard generation == connectionID, !Task.isCancelled else { return }
        connectionReport = parts.joined(separator: "\n\n")
    }
    var orderedIDs: [String] {
        savedIDs.enumerated().sorted { lhs, rhs in
            let a = tasks[lhs.element]?.created ?? .distantPast
            let b = tasks[rhs.element]?.created ?? .distantPast
            return a == b ? lhs.offset < rhs.offset : a > b
        }.map { $0.element }
    }
    func record(_ task: RemoteTask) {
        let old = tasks[task.id]
        // Overlapping read requests must never resurrect a known terminal task.
        if old?.isTerminal == true && !task.isTerminal { return }
        tasks[task.id] = task; taskErrors[task.id] = nil
        if !savedIDs.contains(task.id) { savedIDs.insert(task.id, at: 0); defaults.set(savedIDs, forKey: idsKey) }
        if old?.status != task.status || old?.progress != task.progress {
            var history = events[task.id] ?? []
            history.append(StateEvent(text: task.statusLabel + (task.progress.map { " · " + $0 } ?? "")))
            events[task.id] = Array(history.suffix(200))
        }
    }
    /// Reads only: persisted IDs are never resubmitted, even after 404 or network failure.
    func refresh() async {
        guard let client, !refreshing else { return }
        let generation = connectionID; refreshGeneration = generation; refreshing = true
        defer { if refreshGeneration == generation { refreshing = false; refreshGeneration = nil } }
        var failures: [String] = []
        do {
            let recent = try await client.list()
            guard generation == connectionID, !Task.isCancelled else { return }
            recent.reversed().forEach(record)
        } catch {
            guard !Task.isCancelled else { return }
            failures.append(client.redact(error.localizedDescription))
        }
        guard generation == connectionID else { return }
        // Also fetch IDs outside the server's recent-ten window.
        for id in savedIDs {
            guard !Task.isCancelled, generation == connectionID else { return }
            do {
                let task = try await client.task(id)
                guard generation == connectionID else { return }; record(task)
            } catch {
                guard generation == connectionID, !Task.isCancelled else { return }
                taskErrors[id] = client.redact(error.localizedDescription)
                failures.append("\(id)：\(client.redact(error.localizedDescription))")
            }
        }
        guard generation == connectionID else { return }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    func create(goal: String, conversation: String) async -> String? {
        guard let client, !submitting else { return nil }
        submitting = true; defer { submitting = false }
        let generation = connectionID
        var body: [String: JSONValue] = ["goal": .string(goal)]
        if !conversation.isEmpty { body["conversation"] = .string(conversation) }
        do {
            let response = try await client.request(["tasks"], method: "POST", body: body)
            // Save an ID immediately, even if the remainder of the response is incompatible.
            let id = response.text("task_id", "id") ?? response["task"].text("task_id", "id")
            guard generation == connectionID else { return nil }
            if let id, !savedIDs.contains(id) { savedIDs.insert(id, at: 0); defaults.set(savedIDs, forKey: idsKey) }
            if let task = try? RemoteTask(response) { record(task); error = nil; return task.id }
            if let id { error = "任务已返回 ID，详情将重新查询。"; return id }
            throw ClientError.protocolMismatch
        } catch {
            guard generation == connectionID else { return nil }
            self.error = "提交未确认，可能已被手机接受。请先刷新最近任务核对，勿直接重复提交。\n" + client.redact(error.localizedDescription)
            return nil
        }
    }
    func watch(id: String) async {
        guard let client else { return }
        let generation = connectionID
        var fallback = false
        var initial = true
        while !Task.isCancelled, generation == connectionID {
            let started = Date()
            do {
                let task: RemoteTask
                if initial || fallback { task = try await client.task(id) }
                else { task = try await client.wait(id) }
                guard !Task.isCancelled, generation == connectionID else { return }
                record(task); initial = false
                if task.isTerminal { return }
                // wait can return immediately for answer/phone takeover: avoid a hot loop.
                let delay = fallback || task.canAnswer || task.status == "waiting_on_phone" ? 5.0 : max(0.5, 1 - Date().timeIntervalSince(started))
                try await Task.sleep(for: .seconds(delay))
            } catch {
                guard !Task.isCancelled, generation == connectionID else { return }
                taskErrors[id] = client.redact(error.localizedDescription)
                if let failure = error as? ClientError, failure.isNotFound { return }
                fallback = true; initial = false
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    func action(id: String, name: String, text: String = "") async throws -> String {
        guard let client else { throw ClientError.missingToken }
        let generation = connectionID
        let body: [String: JSONValue] = name == "cancel" ? [:] : ["text": .string(text)]
        let response = try await client.request(["tasks", id, name], method: "POST", body: body)
        guard generation == connectionID else { throw CancellationError() }
        // An accepted mutation does not imply that it has taken effect. Always read again.
        do { record(try await client.task(id)) }
        catch { taskErrors[id] = client.redact(error.localizedDescription) }
        return "请求已响应；以重新查询的任务状态为准。\n" + client.redact(response.pretty)
    }
}
