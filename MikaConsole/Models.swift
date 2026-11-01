import Foundation

/// Preserve unknown protocol fields so capability/device output remains inspectable.
indirect enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var number: Double? { if case .number(let n) = self { return n }; return nil }
    func text(_ keys: String...) -> String? { keys.compactMap { self[$0].string }.first }
    var pretty: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? ""
    }
}

struct RemoteTask: Identifiable, Equatable {
    let id: String
    let payload: JSONValue
    init(_ response: JSONValue) throws {
        let value = response["task"] == .null ? response : response["task"]
        guard let id = value.text("task_id", "id"), !id.isEmpty,
              value.text("status", "state") != nil else { throw ClientError.protocolMismatch }
        self.id = id; payload = value
    }
    var status: String { payload.text("status", "state") ?? "unknown" }
    var goal: String { payload.text("goal", "goal_summary") ?? "（未返回目标）" }
    var isTerminal: Bool { ["done", "failed", "cancelled", "completed", "succeeded"].contains(status) }
    var canAnswer: Bool { ["waiting_for_answer", "waiting"].contains(status) }
    var canSteer: Bool { status == "running" }
    var statusLabel: String {
        ["starting": "启动中", "running": "运行中", "paused": "已暂停", "waiting": "等待回答",
         "waiting_for_answer": "等待回答", "waiting_on_phone": "请在手机处理", "done": "已完成",
         "failed": "失败", "cancelled": "已取消", "completed": "已完成", "succeeded": "已完成"][status] ?? status
    }
    var progress: String? { payload.text("progress", "latest_progress", "message") }
    var question: String? { payload.text("question", "pending_question") ?? payload["waiting"].text("question", "text") }
    var result: String? { payload.text("result", "answer", "final_answer", "error", "reason") ?? payload["result"].text("text", "answer") }
    static func date(_ value: JSONValue) -> Date? {
        if let n = value.number { return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n) }
        guard let s = value.string else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    var created: Date? { Self.date(payload["created_at"]) ?? Self.date(payload["created_at_ms"]) }
    var ended: Date? { Self.date(payload["finished_at"]) ?? Self.date(payload["finished_at_ms"]) ?? Self.date(payload["completed_at"]) }
    var duration: String {
        if let ms = payload["elapsed_ms"].number ?? payload["duration_ms"].number { return String(format: "%.1f 秒", ms / 1000) }
        if let seconds = payload["elapsed_s"].number { return String(format: "%.1f 秒", seconds) }
        if let start = created, let end = ended { return String(format: "%.1f 秒", max(0, end.timeIntervalSince(start))) }
        return "服务端未提供耗时"
    }
}

struct StateEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

enum ClientError: LocalizedError {
    case invalidAddress, missingToken, protocolMismatch, keychain(Int32), http(Int, String, String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "基址无效：请输入 http://IP:端口 或 HTTPS 根地址，不含账号、路径、查询和片段。"
        case .missingToken: return "请输入令牌。"
        case .protocolMismatch: return "响应不符合任务 API v1 格式；请核对安卓版本和基址。"
        case .keychain(let status): return "Keychain 操作失败（\(status)）。"
        case .http(let status, let code, let message): return "HTTP \(status) · \(code)\n\(message)"
        }
    }
    var isNotFound: Bool { if case .http(404, _, _) = self { return true }; return false }
}
