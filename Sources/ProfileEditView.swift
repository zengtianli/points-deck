import SwiftUI

/// 改昵称 / 换头像 —— `/api/profile`，孩子自己就能改，**不要家长密码**（服务端如此）。
///
/// 头像候选来自 `/api/state` 的 `avatars`，不在端上写第二份：
/// 服务端的 `profile_update` 有个白名单校验，端上多写一个它没有的 emoji，
/// 表现是「点了没反应」而不是报错 —— 那种缺陷最难查。
struct ProfileEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var nick = ""
    @State private var emoji = ""
    @State private var busy = false
    @State private var err: String?

    private var s: LedgerState? { store.state }
    private var era: Era { s?.era ?? .slum }

    private let cols = [GridItem(.adaptive(minimum: 56), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text(emoji.isEmpty ? (s?.avatar ?? "🐯") : emoji)
                        .font(.system(size: 64))
                        .frame(width: 108, height: 108)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(era.accent.opacity(0.6), lineWidth: 2))
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("昵称").font(.footnote).foregroundStyle(.white.opacity(0.6))
                        TextField("", text: $nick)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        Text("1~16 个字").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("头像").font(.footnote).foregroundStyle(.white.opacity(0.6))
                        if (s?.avatarChoices ?? []).isEmpty {
                            Text("服务端没下发头像清单 —— 换个头像这一项暂时用不了")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(s?.avatarChoices ?? [], id: \.self) { e in
                                Button { emoji = e } label: {
                                    Text(e)
                                        .font(.system(size: 30))
                                        .frame(width: 56, height: 56)
                                        .background(.white.opacity(emoji == e ? 0.22 : 0.08),
                                                    in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .stroke(emoji == e ? era.accent : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let err {
                        Text(err).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(era.background.ignoresSafeArea())
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView() } else { Text("保存") }
                    }
                    .disabled(busy || !changed)
                }
            }
            .task {
                nick = s?.nick ?? ""
                emoji = s?.avatar ?? ""
            }
        }
    }

    /// 没改过就别让保存可点 —— 空提交会白打一次请求，还会让人以为改成功了。
    private var changed: Bool {
        let n = nick.trimmingCharacters(in: .whitespaces)
        return (!n.isEmpty && n != s?.nick) || (!emoji.isEmpty && emoji != s?.avatar)
    }

    private func save() async {
        busy = true; defer { busy = false }
        err = nil
        let n = nick.trimmingCharacters(in: .whitespaces)
        do {
            try await Api.profile(nick: n == s?.nick ? nil : n,
                                  emoji: emoji == s?.avatar ? nil : (emoji.isEmpty ? nil : emoji))
            await store.refresh()
            dismiss()
        } catch {
            err = error.localizedDescription
        }
    }
}
