import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import AVFoundation
import UIKit
import UniformTypeIdentifiers

// MARK: - Draft

/// A file the user has picked but not yet committed — staged in memory while
/// the "new transaction" sheet is open, then materialized into a
/// `TransactionAttachment` row on save.
///
/// `existing` bridges edit mode: when the sheet opens on a saved row, each
/// persisted attachment is wrapped in a draft that remembers its origin, so
/// the save path can diff (keep, delete, insert) without re-reading blobs.
struct AttachmentDraft: Identifiable {
    let id: UUID
    var filename: String
    var data: Data
    var typeIdentifier: String
    /// The persisted attachment this draft mirrors, or `nil` for a brand-new
    /// pick. Drives the keep/delete/insert diff on save.
    var existing: TransactionAttachment?

    init(
        id: UUID = UUID(),
        filename: String,
        data: Data,
        typeIdentifier: String,
        existing: TransactionAttachment? = nil
    ) {
        self.id = id
        self.filename = filename
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.existing = existing
    }

    /// Seed a draft from an already-persisted attachment (edit mode). Fails
    /// when the row has no readable bytes — nothing to show or re-save.
    init?(existing attachment: TransactionAttachment) {
        guard let data = attachment.data else { return nil }
        self.init(
            filename: attachment.filename,
            data: data,
            typeIdentifier: attachment.typeIdentifier,
            existing: attachment
        )
    }

    var contentType: UTType? { UTType(typeIdentifier) }
    var isPDF: Bool { contentType?.conforms(to: .pdf) ?? filename.lowercased().hasSuffix(".pdf") }
    var isImage: Bool { contentType?.conforms(to: .image) ?? false }
}

// MARK: - Encoding limits

/// Tunables for shrinking images before they're stored. Receipts don't need
/// to be full-resolution, and keeping blobs small matters for the on-device
/// store (and any future iCloud sync, where originals would eat quota).
private enum AttachmentLimits {
    // `nonisolated` so the constants stay reachable from the off-actor decode
    // task; under default main-actor isolation they'd otherwise be inferred
    // `@MainActor`.
    nonisolated static let maxImageDimension: CGFloat = 2000
    nonisolated static let jpegQuality: CGFloat = 0.7
    /// Smaller cap for the on-screen thumbnails the tiles decode.
    nonisolated static let thumbnailDimension: CGFloat = 240
}

private extension UIImage {
    /// Proportionally shrink so the longest side is at most `maxDimension`
    /// points; returns self when it's already small enough. Drawing through
    /// a renderer also normalizes EXIF orientation, so a sideways camera
    /// shot comes back upright.
    ///
    /// `nonisolated` so it can run on the detached decode task off the main
    /// actor — under default main-actor isolation it would otherwise be
    /// inferred `@MainActor`, forcing the resize back onto the main thread.
    nonisolated func downscaled(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // newSize is already the pixel size we want
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Draft factories

/// Re-encode an image into a compact JPEG draft. `suggestedName` keeps a
/// picked file's name (extension swapped to .jpg); camera/Photos picks get a
/// timestamped name since the system doesn't hand us one.
private func makeImageDraft(from image: UIImage, suggestedName: String? = nil) -> AttachmentDraft? {
    let resized = image.downscaled(toMaxDimension: AttachmentLimits.maxImageDimension)
    guard let data = resized.jpegData(compressionQuality: AttachmentLimits.jpegQuality) else { return nil }
    let name: String
    if let suggestedName, !suggestedName.isEmpty {
        name = (suggestedName as NSString).deletingPathExtension + ".jpg"
    } else {
        // Millisecond precision so two snaps in the same second don't collide.
        name = "תמונה-\(Int(Date.now.timeIntervalSince1970 * 1000)).jpg"
    }
    return AttachmentDraft(filename: name, data: data, typeIdentifier: UTType.jpeg.identifier)
}

/// Read a file the user picked in the Files browser into a draft. PDFs are
/// stored verbatim; images funnel through `makeImageDraft` so they're shrunk
/// like camera/Photos picks. Handles the security-scoped access Files needs.
private func makeFileDraft(from url: URL) -> AttachmentDraft? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    guard let data = try? Data(contentsOf: url) else { return nil }
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        ?? UTType(filenameExtension: url.pathExtension)

    if let type, type.conforms(to: .pdf) {
        return AttachmentDraft(filename: url.lastPathComponent, data: data, typeIdentifier: type.identifier)
    }
    if let image = UIImage(data: data) {
        return makeImageDraft(from: image, suggestedName: url.lastPathComponent)
    }
    // Unknown but typed — keep it rather than silently dropping the pick.
    if let type {
        return AttachmentDraft(filename: url.lastPathComponent, data: data, typeIdentifier: type.identifier)
    }
    return nil
}

// MARK: - Temp file store (for QuickLook)

/// QuickLook previews files by URL, but our bytes live in SwiftData blobs, so
/// we spill them to a temp file on demand. The temp directory is volatile and
/// fine to leave to the system to reclaim.
enum AttachmentFileStore {
    static func temporaryURL(filename: String, data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = filename.isEmpty ? "attachment" : filename
        let url = dir.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Identifies a file to preview. A value type so it can drive
/// `.fullScreenCover(item:)`.
struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Build a preview item by spilling the bytes to a temp file. `nil` when
/// there's nothing readable to preview.
func makePreviewItem(filename: String, data: Data?) -> AttachmentPreviewItem? {
    guard let data, let url = AttachmentFileStore.temporaryURL(filename: filename, data: data) else { return nil }
    return AttachmentPreviewItem(url: url)
}

// MARK: - QuickLook

/// Thin wrapper over `QLPreviewController` so SwiftUI can show a single file
/// (image or PDF) with the system's pinch-zoom / paging for free.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

/// Full-screen preview shell with a Hebrew "סגירה" button — `QuickLookPreview`
/// on its own has no dismiss affordance when hosted in a SwiftUI cover.
struct AttachmentPreviewScreen: View {
    let item: AttachmentPreviewItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: item.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("סגירה") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Camera

/// Wraps `UIImagePickerController` in camera mode — SwiftUI still ships no
/// native capture view in iOS 26, so this UIKit bridge is the path to a photo
/// (consistent with the project's other representables). Hands back a single
/// captured `UIImage`.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Tile

/// One attachment shown as a square tile: an image thumbnail or a PDF
/// document card. Used both while composing (with a remove button) and in the
/// expanded card (tap to preview).
struct AttachmentTile: View {
    let filename: String
    let data: Data?
    let isPDF: Bool
    let isImage: Bool
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @State private var thumbnail: UIImage?

    private let side: CGFloat = 72

    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Colors.background)
                content
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        // Remove button floats over the top-trailing corner while editing.
        .overlay(alignment: .topTrailing) { removeButton }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isPDF ? "מסמך \(filename)" : "תמונה \(filename)"))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .task(id: filename) { await loadThumbnailIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if isImage, let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isPDF ? "doc.richtext" : "paperclip")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.Colors.accent)
                Text(filename)
                    .font(Theme.Typography.captionSmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if let onRemove {
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Theme.Colors.expense)
                    .background(Circle().fill(.white).padding(3))
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel(Text("הסרת הקובץ"))
        }
    }

    /// Decode + downsize the thumbnail off the main actor (Data is Sendable,
    /// so it crosses the boundary cleanly), then hand back the small image.
    private func loadThumbnailIfNeeded() async {
        guard isImage, thumbnail == nil, let data else { return }
        let small = await Task.detached(priority: .utility) { () -> UIImage? in
            UIImage(data: data)?.downscaled(toMaxDimension: AttachmentLimits.thumbnailDimension)
        }.value
        thumbnail = small
    }
}

// MARK: - Compose/edit strip

/// The attachments control inside the "new transaction" sheet: a horizontal
/// strip of tiles plus an "add" menu offering Camera / Photos / Files. Binds
/// to the sheet's draft array; the sheet owns persistence on save.
struct AttachmentsEditor: View {
    @Binding var drafts: [AttachmentDraft]

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isShowingPhotosPicker = false
    @State private var isShowingFileImporter = false
    @State private var isShowingCamera = false
    @State private var showCameraDeniedAlert = false
    @State private var previewItem: AttachmentPreviewItem?

    private let tileSide: CGFloat = 72

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(drafts) { draft in
                    AttachmentTile(
                        filename: draft.filename,
                        data: draft.data,
                        isPDF: draft.isPDF,
                        isImage: draft.isImage,
                        onTap: { previewItem = makePreviewItem(filename: draft.filename, data: draft.data) },
                        onRemove: { remove(draft) }
                    )
                }
                addMenu
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .photosPicker(
            isPresented: $isShowingPhotosPicker,
            selection: $photoItems,
            matching: .images,
            photoLibrary: .shared()
        )
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                drafts.append(contentsOf: urls.compactMap(makeFileDraft))
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                if let draft = makeImageDraft(from: image) { drafts.append(draft) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $previewItem) { item in
            AttachmentPreviewScreen(item: item)
        }
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await appendPhotos(newItems) }
        }
        .alert("אין גישה למצלמה", isPresented: $showCameraDeniedAlert) {
            Button("פתיחת הגדרות") { openSettings() }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("כדי לצלם קבלות, אפשרו לעכבר עו״ש גישה למצלמה דרך ההגדרות.")
        }
    }

    private var addMenu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { handleCameraTap() } label: {
                    Label("צילום קבלה", systemImage: "camera")
                }
            }
            Button { isShowingPhotosPicker = true } label: {
                Label("תמונה מהגלריה", systemImage: "photo")
            }
            Button { isShowingFileImporter = true } label: {
                Label("קובץ / PDF", systemImage: "doc")
            }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("הוספה")
                    .font(Theme.Typography.captionSmall)
            }
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: tileSide, height: tileSide)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Colors.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .accessibilityLabel(Text("הוספת קובץ מצורף"))
    }

    // MARK: Actions

    private func remove(_ draft: AttachmentDraft) {
        drafts.removeAll { $0.id == draft.id }
    }

    @MainActor
    private func appendPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let draft = makeImageDraft(from: image) {
                drafts.append(draft)
            }
        }
        photoItems = []
    }

    /// Gate the camera behind an explicit authorization check so a denied
    /// user gets a calm "open Settings" path instead of a black viewfinder.
    private func handleCameraTap() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { isShowingCamera = true } else { showCameraDeniedAlert = true }
                }
            }
        default:
            showCameraDeniedAlert = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Read-only strip (expanded card)

/// The attachments shown in the expanded transaction card — tiles only, no
/// remove buttons; tapping a tile previews the file. Reads straight off the
/// persisted `TransactionAttachment` rows.
struct AttachmentStrip: View {
    let attachments: [TransactionAttachment]
    @State private var previewItem: AttachmentPreviewItem?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(attachments) { attachment in
                    AttachmentTile(
                        filename: attachment.filename,
                        data: attachment.data,
                        isPDF: attachment.isPDF,
                        isImage: attachment.isImage,
                        onTap: { previewItem = makePreviewItem(filename: attachment.filename, data: attachment.data) }
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .fullScreenCover(item: $previewItem) { item in
            AttachmentPreviewScreen(item: item)
        }
    }
}
