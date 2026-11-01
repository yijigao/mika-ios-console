import SwiftUI

@MainActor struct ConnectionView: View {
    @EnvironmentObject private var store: ConsoleStore
    @State private var address = ""
    @State private var token = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("安卓 Mika 连接") {
                    TextField("http://192.168.1.23:8765", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("令牌（留空使用已保存令牌）", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Text("安卓 Mika ≥ v0.1.23：设置 › 连接电脑 › 开启网络访问。两台手机须在同一局域网或私有 VPN。")
                        .font(.footnote)
                    Button("保存并检测连接") {
                        busy = true; message = nil
                        Task { @MainActor in
                            defer { busy = false }
                            do {
                                let base = try APIClient.normalize(address)
                                let secret = token.isEmpty ? (try TokenVault.read(for: base.absoluteString) ?? "") : token
                                try store.saveConnection(address: address, token: secret)
                                token = ""; address = store.baseAddress
                                await store.checkConnection()
                            } catch { message = "连接保存失败：" + error.localizedDescription }
                        }
                    }.disabled(busy || store.submitting)
                    if busy { ProgressView("检测中…") }
                    if store.client != nil {
                        Button("移除当前连接令牌", role: .destructive) {
                            do { try store.forgetConnection(); token = ""; address = "" }
                            catch { message = error.localizedDescription }
                        }.disabled(busy || store.submitting)
                    }
                }
                if let message { Section("提示") { Text(message).foregroundStyle(.red) } }
                Section("检测结果") { Text(store.connectionReport).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                Section("安全边界") { SafetyNotice(); Text("令牌只持久化至本设备 Keychain。任务 ID 按基址保存在本机，不自动重发新建、回答、追加或取消请求。") .font(.footnote) }
            }
            .navigationTitle("连接")
            .onAppear { address = store.baseAddress }
        }
    }
}
