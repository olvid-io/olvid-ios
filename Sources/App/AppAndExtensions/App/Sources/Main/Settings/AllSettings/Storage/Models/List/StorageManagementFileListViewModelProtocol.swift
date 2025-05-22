/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import SwiftUI

protocol DeleteActionCanBeMadeAvailableProtocol {
    var deleteActionCanBeMadeAvailable: Bool { get }
}

enum StorageManagementDeletionMode {
    case all
    case unique
}

@available(iOS 17.0, *)
protocol StorageManagementFileListViewModelProtocol: StorageManagerRouterAwarenessProtocol {
    
    associatedtype StorageFileRepresentation: Hashable, Identifiable, DeleteActionCanBeMadeAvailableProtocol
    
    associatedtype Content: View
    
    var storageFiles: [StorageFileRepresentation] { get }
    
    var selectionProperties: FileListSelectionProperties<StorageFileRepresentation> { get set }
    
    var storageFilesLocation: [CGRect] { get }
    
    var isSelectionEnabled: Bool { get set }
    
    var showDeletionAlert: Bool { get set }
    
    var quicklookURL: URL? { get set }
    
    func setQuicklookURL(_ url: URL?)
    
    var quicklookURLs: [URL] { get }

    var sortOrder: StorageManagementSortOrder { get }
    
    var sortDirection: StorageManagementSortDirection { get }
    
    func cellForStorageFile(_ storageFile: StorageFileRepresentation, isSelected: Bool) -> Content

    @MainActor
    func itemHasDuplicate(_ fyleMessageJoin: StorageFileRepresentation) -> Bool

    @MainActor
    func updateStorageFileLocation(for fyleMessageJoin: StorageFileRepresentation, frame: CGRect)
    
    @MainActor
    func itemHasBeenTapped(for fyleMessageJoin: StorageFileRepresentation)

    @MainActor
    func toggleSelection(for fyleMessageJoin: StorageFileRepresentation)

    @MainActor
    func updateSelection(for fyleMessageJoin: StorageFileRepresentation)

    @MainActor
    func isFileSelected(fyleMessageJoin: StorageFileRepresentation) -> Bool

    @MainActor
    func goToDiscussion(for file: StorageFileRepresentation)
    
    @MainActor
    func delete(_ file: StorageFileRepresentation)
    
    @MainActor
    func clearSelection()
    
    @MainActor
    func toggleSelectionMode()
    
    @MainActor
    func performDeletion(deletionMode: StorageManagementDeletionMode)
    
    @MainActor
    func showDeletionAlert(value: Bool)
    
    @MainActor
    func onTask() async throws
    
    @MainActor
    func updateSortOrder(sortOrder: StorageManagementSortOrder)

}

struct FileListSelectionProperties<StorageFileRepresentation: Equatable> {
    var start: Int?
    var end: Int?
    var singleSelected: StorageFileRepresentation? = nil
    var multipleSelections: [StorageFileRepresentation] = []
    var previousSelections: [StorageFileRepresentation] = []
    var toBeDeleted: [StorageFileRepresentation] = []
    var isDeleteDrag: Bool = false
    
    mutating func clear() {
        for index in toBeDeleted {
            multipleSelections.removeAll { $0 == index }
        }
        toBeDeleted = []
        previousSelections = multipleSelections
        start = nil
        end = nil
        isDeleteDrag = false
    }
}
