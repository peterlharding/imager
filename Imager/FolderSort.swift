import Foundation

/// How the images in a browsed folder are ordered.
enum FolderSortOrder: String, CaseIterable, Identifiable {
    case name
    case dateModified
    case size

    var id: Self { self }

    var label: String {
        switch self {
        case .name: "Name"
        case .dateModified: "Date Modified"
        case .size: "File Size"
        }
    }

    static let orderKey = "folder.sortOrder"
    static let reversedKey = "folder.sortReversed"
    static let defaultOrder = FolderSortOrder.name
}
