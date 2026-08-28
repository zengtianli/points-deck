import PhotosUI
import SwiftUI

/// 错题本 —— 手机就是相机，这条链在手机上天然顺。
///
/// 拍照**不涉及分值也不涉及身份**（服务端：登录即可传，拍照不是能刷分的动作），
/// 所以这一屏没有家长密码。
struct WrongView: View {
    @EnvironmentObject var store: Store
    @State private var items: [Api.Wrong] = []
    @State private var loading = true
    @State private var picking: PhotosPickerItem?
    @State private var showCamera = false
    @State private var subject = ""
    @State private var busy = false
    @State private var toast: String?

    private var era: Era { store.state?.era ?? .slum }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                buttons
                subjectPicker
                if loading {
                    ProgressView().tint(.white).padding(.top, 30)
                } else if items.isEmpty {
                    Text("还没有传过错题")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 30)
                } else {
                    ForEach(items) { w in row(w) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
        .task { await load() }
        .photosPicker(isPresented: Binding(get: { picking != nil && false }, set: { _ in }),
                      selection: $picking)
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in Task { await upload(image) } }
                .ignoresSafeArea()
        }
        .onChange(of: picking) { _, new in
            guard let new else { return }
            Task {
                if let d = try? await new.loadTransferable(type: Data.self),
                   let img = UIImage(data: d) {
                    await upload(img)
                }
                picking = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t).font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button { showCamera = true } label: {
                label("拍一张", "camera.fill")
            }
            .disabled(busy)
            PhotosPicker(selection: $picking, matching: .images) {
                label("从相册选", "photo.on.rectangle")
            }
            .disabled(busy)
        }
    }

    private func label(_ t: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            if busy { ProgressView().tint(.black) } else { Image(systemName: icon) }
            Text(t).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(era.accent, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.black)
    }

    private var subjectPicker: some View {
        HStack {
            Text("科目").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Picker("", selection: $subject) {
                Text("不填").tag("")
                ForEach(store.state?.subjects ?? []) { s in
                    Text("\(s.icon) \(s.name)").tag(s.id)
                }
            }
            .tint(era.accent)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ w: Api.Wrong) -> some View {
        HStack(spacing: 12) {
            Thumb(id: w.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.at).font(.subheadline).foregroundStyle(.white)
                Text(w.status == "new" ? "待录入题库" : "已进题库（原图已回收）")
                    .font(.caption)
                    .foregroundStyle(w.status == "new" ? era.accent : .white.opacity(0.45))
            }
            Spacer()
            if w.status == "new" {
                Button(role: .destructive) {
                    Task { await remove(w) }
                } label: {
                    Image(systemName: "trash").foregroundStyle(Color(hex: 0xFF9E9E))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    // ── 动作 ──────────────────────────────────────────────────────────────────
    private func load() async {
        loading = true; defer { loading = false }
        items = (try? await Api.wrongs()) ?? []
    }

    private func upload(_ image: UIImage) async {
        busy = true; defer { busy = false }
        guard let jpeg = Self.compress(image) else {
            show("这张图压不到 3MB 以内"); return
        }
        do {
            try await Api.uploadWrong(jpeg: jpeg, subject: subject, note: "")
            await load()
            show("传好了 · \(jpeg.count / 1000)KB")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func remove(_ w: Api.Wrong) async {
        do {
            try await Api.deleteWrong(id: w.id)
            await load()
            show("删了")
        } catch { show(error.localizedDescription) }
    }

    /// 压到服务端的 3MB 以内 —— **端上压完再传**，别把这件事推给服务端拒收。
    /// 先缩边长再降质量：手机原图 4000px 宽，光降质量压不下来，而错题只要看清字。
    static func compress(_ image: UIImage, limit: Int = 2_800_000) -> Data? {
        var img = image
        let maxSide: CGFloat = 2000
        let side = max(img.size.width, img.size.height)
        if side > maxSide {
            let k = maxSide / side
            let sz = CGSize(width: img.size.width * k, height: img.size.height * k)
            let r = UIGraphicsImageRenderer(size: sz)
            img = r.image { _ in img.draw(in: CGRect(origin: .zero, size: sz)) }
        }
        for q in stride(from: 0.85, through: 0.35, by: -0.1) {
            if let d = img.jpegData(compressionQuality: q), d.count <= limit { return d }
        }
        return img.jpegData(compressionQuality: 0.3)
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }
}

/// 缩略图 —— 原图要带 cookie 才取得到，所以不能用 AsyncImage 直接怼 URL。
private struct Thumb: View {
    let id: String
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.12))
                    .overlay { Image(systemName: "photo").foregroundStyle(.white.opacity(0.4)) }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            if let d = try? await Api.wrongImage(id: id) { img = UIImage(data: d) }
        }
    }
}

/// 系统相机 —— SwiftUI 没有原生相机视图，这层壳是必需的，不是造轮子。
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        // 模拟器没有相机，回落相册 —— 否则这里会黑屏，而黑屏看起来像 app 挂了
        c.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
