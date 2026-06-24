import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A single file the user attached to a `Transaction` — a photographed
/// receipt, a PDF invoice, a screenshot of a confirmation.
///
/// Stored entirely on-device (like everything else in the app). The raw
/// bytes live in `data` with `.externalStorage`, which tells SwiftData to
/// keep large blobs in their own files on disk instead of bloating the
/// main SQLite store — important when a single photo can be several MB.
/// External storage is also CloudKit-compatible, so this leaves the door
/// open for sync exactly like the rest of the schema.
@Model
final class TransactionAttachment {
    /// Original (or synthesized) filename, used for display and when the
    /// user shares the file out of QuickLook — e.g. "קבלה.pdf",
    /// "IMG_2031.jpg". Never empty in practice; defaulted for CloudKit.
    var filename: String = ""

    /// The file's bytes. `.externalStorage` keeps the blob out of the main
    /// store file. Optional because CloudKit requires every stored property
    /// to be optional or defaulted — a `nil` here just means "no data yet",
    /// which the UI treats as an unreadable/missing attachment.
    @Attribute(.externalStorage) var data: Data?

    /// The Uniform Type Identifier as a plain string, e.g. "public.jpeg" or
    /// "com.adobe.pdf". Kept as a `String` (not a `UTType`) so the column
    /// is a simple, CloudKit-friendly scalar and new types never force a
    /// schema migration. Bridged back to `UTType` via the helpers below.
    var typeIdentifier: String = ""

    /// When the file was attached. Lets the card list attachments oldest- or
    /// newest-first deterministically.
    var createdAt: Date = Date.now

    /// The transaction this file belongs to. Inverse of
    /// `Transaction.attachments`; nilled out only transiently while the
    /// owning row is being cascade-deleted. Optional, as CloudKit requires.
    var transaction: Transaction?

    init(
        filename: String = "",
        data: Data? = nil,
        typeIdentifier: String = "",
        createdAt: Date = .now,
        transaction: Transaction? = nil
    ) {
        self.filename = filename
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.createdAt = createdAt
        self.transaction = transaction
    }

    /// The decoded `UTType`, or `nil` if the stored identifier is unknown.
    var contentType: UTType? {
        UTType(typeIdentifier)
    }

    /// True for PDFs — the card shows a document tile rather than an image
    /// preview. Falls back to a filename-extension check so a row written
    /// with an empty/odd `typeIdentifier` still classifies sensibly.
    var isPDF: Bool {
        if let contentType { return contentType.conforms(to: .pdf) }
        return filename.lowercased().hasSuffix(".pdf")
    }

    /// True for raster/vector images (JPEG, PNG, HEIC…). Used to decide
    /// whether to render an inline thumbnail.
    var isImage: Bool {
        if let contentType { return contentType.conforms(to: .image) }
        return false
    }
}
