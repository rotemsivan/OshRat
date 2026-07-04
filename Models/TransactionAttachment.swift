import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A file the user attached to a `Transaction` — a photographed receipt,
/// a PDF invoice, a screenshot. Stored entirely on-device.
@Model
final class TransactionAttachment {
    /// Display / share-out filename, e.g. "קבלה.pdf". Defaulted for CloudKit.
    var filename: String = ""

    /// The file's bytes. `.externalStorage` keeps large blobs (a photo can be
    /// several MB) out of the main SQLite store, and stays CloudKit-compatible.
    /// `nil` reads as an unreadable/missing attachment in the UI.
    @Attribute(.externalStorage) var data: Data?

    /// Uniform Type Identifier, e.g. "public.jpeg". A plain `String` (not
    /// `UTType`) so the column is a CloudKit-friendly scalar and new types
    /// never force a schema migration.
    var typeIdentifier: String = ""

    /// When the file was attached — gives lists a deterministic order.
    var createdAt: Date = Date.now

    /// Owning transaction. Inverse of `Transaction.attachments`; optional,
    /// as CloudKit requires.
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

    /// Decoded `UTType`, or `nil` for an unknown identifier.
    var contentType: UTType? {
        UTType(typeIdentifier)
    }

    /// PDFs get a document tile instead of an image preview. Falls back to
    /// the filename extension when `typeIdentifier` is empty or odd.
    var isPDF: Bool {
        if let contentType { return contentType.conforms(to: .pdf) }
        return filename.lowercased().hasSuffix(".pdf")
    }

    /// Raster/vector images (JPEG, PNG, HEIC…) — rendered as inline thumbnails.
    var isImage: Bool {
        if let contentType { return contentType.conforms(to: .image) }
        return false
    }
}
