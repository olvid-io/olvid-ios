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
import ObvUICoreData
import SwiftUI
import CoreData
import Combine

extension FyleMessageJoinWithStatus: DeleteActionCanBeMadeAvailableProtocol { }

@available(iOS 17.0, *)
@Observable
class StorageManagementFileListViewModel: StorageManagementFileListViewModelProtocol, @unchecked Sendable {

    typealias StorageFileRepresentation = FyleMessageJoinWithStatus
    
    private(set) var storageFiles: [FyleMessageJoinWithStatus] = []
    
    private(set) var storageFilesLocation: [CGRect] = []
    
    private(set) var storageFilesMediaViewModels = [StorageManagementMediaCellViewModel]()
    
    var quicklookURL: URL? = nil
    
    @ObservationIgnored private(set) var quicklookURLs: [URL] = []
    
    var sortOrder: StorageManagementSortOrder = .size
    
    var sortDirection: StorageManagementSortDirection = .descending
    
    var selectionProperties = FileListSelectionProperties<StorageFileRepresentation>()
    var isSelectionEnabled: Bool = false
    let cacheManager: DiscussionCacheManager
    var showDeletionAlert: Bool = false
    
    private var fetchRequest: NSFetchRequest<FyleMessageJoinWithStatus>
    
    weak var router: StorageManagerRouter?
    
    init(fetchRequest: NSFetchRequest<FyleMessageJoinWithStatus>, cacheManager: DiscussionCacheManager) {
        self.fetchRequest = fetchRequest
        self.cacheManager = cacheManager
    }
    
    private func createCellViewModels() {
        self.storageFilesMediaViewModels = storageFiles.compactMap({ attachment in
            StorageManagementMediaCellViewModel(attachment: attachment, cacheManager: cacheManager)
        })
    }
    
    @ViewBuilder
    func cellForStorageFile(_ storageFile: FyleMessageJoinWithStatus, isSelected: Bool) -> some View {
        if let viewModel = storageFilesMediaViewModels.first(where: { $0.attachment == storageFile }) {
            let _ = (viewModel.isSelected = isSelected)
            StorageManagementMediaCellView(model: viewModel)
        } else {
            EmptyView()
        }
    }

    @MainActor
    func itemHasDuplicate(_ fyleMessageJoin: StorageFileRepresentation) -> Bool {

        // we first fetch all fyle message joins linked to current fyle
        guard let ownedCryptoId = fyleMessageJoin.message?.discussion?.ownedIdentity?.cryptoId,
              let allFyleMessageJoinWithStatus = fyleMessageJoin.fyle?.fyleMessageJoinWithStatuses(ownedCryptoId: ownedCryptoId) else { return false }
                
        return allFyleMessageJoinWithStatus.count > 1
    }
    
    @MainActor
    func itemHasBeenTapped(for fyleMessageJoin: StorageFileRepresentation) {
        // We are fetching url directly from the cacheManager instead of using quicklookPreviewURLs to ensure that the hardlink is the one we want to display
        if let hardlink = cacheManager.getCachedHardlinkForFyleMessageJoinWithStatus(with: fyleMessageJoin.typedObjectID) {
            self.quicklookURL = hardlink.hardlinkURL
        } else { // no hardlink available, we redirect to the message within the discussion
            goToDiscussion(for: fyleMessageJoin)
        }
    }

    @MainActor
    func toggleSelection(for fyleMessageJoin: StorageFileRepresentation) {
        if selectionProperties.multipleSelections.contains(fyleMessageJoin) {
            selectionProperties.multipleSelections.removeAll { $0 == fyleMessageJoin }
        } else {
            selectionProperties.multipleSelections.append(fyleMessageJoin)
        }
        
        selectionProperties.previousSelections = selectionProperties.multipleSelections
    }
    
    @MainActor
    func updateSelection(for fyleMessageJoin: StorageFileRepresentation) {
        guard let index = self.storageFiles.firstIndex(of: fyleMessageJoin) else { return }
        if selectionProperties.start == nil {
            selectionProperties.start = index
            selectionProperties.isDeleteDrag = selectionProperties.previousSelections.contains(fyleMessageJoin)
        }
        
        selectionProperties.end = index
        
        if let start = selectionProperties.start, let end = selectionProperties.end {
            let indices = (min(start, end)...max(start, end)).compactMap { $0 }
            let fyleMessageJoins = indices.compactMap({ storageFiles[safe: $0]})
            if selectionProperties.isDeleteDrag {
                selectionProperties.toBeDeleted = Set(selectionProperties.previousSelections).intersection(fyleMessageJoins).compactMap { $0 }
            } else {
                selectionProperties.multipleSelections = Set(selectionProperties.previousSelections).union(fyleMessageJoins).compactMap { $0 }
            }
        }
        
    }
    
    func updateStorageFileLocation(for fyleMessageJoin: FyleMessageJoinWithStatus, frame: CGRect) {
        if let index = storageFiles.firstIndex(of: fyleMessageJoin), index < storageFilesLocation.count {
            storageFilesLocation[index] = frame
        }
    }
    
    @MainActor
    func isFileSelected(fyleMessageJoin: FyleMessageJoinWithStatus) -> Bool {
        return selectionProperties.multipleSelections.contains(fyleMessageJoin) && !selectionProperties.toBeDeleted.contains(fyleMessageJoin)
    }
    
    @MainActor
    func goToDiscussion(for file: FyleMessageJoinWithStatus){
        guard let messageAppIdentifier = try? file.message?.messageAppIdentifier else { return }
        let deeplink = ObvDeepLink.message(messageAppIdentifier)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deeplink).postOnDispatchQueue()
    }

    @MainActor
    func delete(_ file: FyleMessageJoinWithStatus){
        selectionProperties = .init()
        selectionProperties.singleSelected = file
        showDeletionAlert(value: true)
    }
    
    @MainActor
    func clearSelection() {
        selectionProperties.clear()
    }
    
    @MainActor
    func toggleSelectionMode() {
        isSelectionEnabled.toggle()
        if !isSelectionEnabled {
            selectionProperties = .init()
        }
    }
    
    @MainActor
    func showDeletionAlert(value: Bool) {
        guard !selectionProperties.multipleSelections.isEmpty || selectionProperties.singleSelected != nil else { return }
        self.showDeletionAlert = value
    }
    
    @MainActor
    func performDeletion(deletionMode: StorageManagementDeletionMode) {
        guard let ownedCryptoId = storageFiles.first?.message?.discussion?.ownedIdentity?.cryptoId else { return }
        
        var selectedIndices = selectionProperties.multipleSelections
        
        if let singleSelection = selectionProperties.singleSelected {
            selectedIndices = [singleSelection]
        }
        
        let filesToDelete: [FyleMessageJoinWithStatus]
        
        switch deletionMode {
        case .all:
            let flattenFilesToDelete = selectedIndices.compactMap { fyleMessageJoinWithStatus in
                return fyleMessageJoinWithStatus.fyle?.fyleMessageJoinWithStatuses(ownedCryptoId: ownedCryptoId) // Foreach fyleMessageJoinWithStatus, we delete all fyleMessageJoinWithStatues pointing to the same file.
            }.joined()
            filesToDelete = Array(flattenFilesToDelete)
        case .unique:
            filesToDelete = selectedIndices
        }
        
        let joinObjectIDs = Set(filesToDelete.map { $0.typedObjectID })

        ObvMessengerInternalNotification.userWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ownedCryptoId, objectIDs: joinObjectIDs)
            .postOnDispatchQueue()
        
        self.showDeletionAlert = false
           
        if isSelectionEnabled {
            toggleSelectionMode()
        }
    }
    
    func setQuicklookURL(_ url: URL?) {
        quicklookURL = url
    }
    
    @MainActor
    func updateSortOrder(sortOrder: StorageManagementSortOrder) {
        if self.sortOrder == sortOrder {
            self.sortDirection.toggle()
        } else {
            self.sortDirection = .descending
            self.sortOrder = sortOrder
        }
        withAnimation {
            self.recreateFilesModels(from: self.storageFiles)
        } completion: {
            Task {
                await self.preloadHardlinks()
            }
        }
    }
    
    @MainActor
    func onTask() async throws {
        
        let fetchRequestStream = ObvStack.shared.viewContext.fetchRequestStream(for: self.fetchRequest)
        
        for await files in fetchRequestStream.stream {
            
            if files.isEmpty {
                router?.dismiss()
                break
            }
            
            withAnimation {
                self.recreateFilesModels(from: files)
            } completion: {
                Task {
                    await self.preloadHardlinks()
                }
            }
            
        }
        
    }
}

@available(iOS 17.0, *)
extension StorageManagementFileListViewModel {
    
    private func sortedFiles(from files: [FyleMessageJoinWithStatus]) -> [FyleMessageJoinWithStatus] {
        switch self.sortOrder {
        case .size:
            return files.sorted(by: { self.sortDirection.compare(lhs: $0.totalByteCount,
                                                                 rhs: $1.totalByteCount) })
        case .date:
            return files.sorted(by: { self.sortDirection.compare(lhs: $0.message?.timestamp ?? .now,
                                                                 rhs: $1.message?.timestamp ?? .now) })
        case .type:
            return files.sorted(by: { self.sortDirection.compare(lhs: $0.attachmentType.orderValue,
                                                                 rhs: $1.attachmentType.orderValue) })
        default:
            return files
        }
    }
    
    @MainActor
    private func recreateFilesModels(from files: [FyleMessageJoinWithStatus]) {
        self.storageFiles = self.sortedFiles(from: files)
        self.storageFilesLocation = Array(repeating: .zero, count: files.count)
        self.createCellViewModels()
    }

}

@available(iOS 17.0, *)
extension StorageManagementFileListViewModel: Identifiable, Equatable, Hashable {
    
    static func == (lhs: StorageManagementFileListViewModel, rhs: StorageManagementFileListViewModel) -> Bool {
        return lhs.storageFiles == rhs.storageFiles
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(storageFiles)
    }
}

@available(iOS 17.0, *)
extension StorageManagementFileListViewModel {
    
    @MainActor
    private func preloadHardlinks() async {
        
        self.quicklookURLs.removeAll()
        
        for fyleMessageJoin in storageFiles {
            if let hardlinkURL = cacheManager.getCachedHardlinkForFyleMessageJoinWithStatus(with: fyleMessageJoin.typedObjectID)?.hardlinkURL {
                self.quicklookURLs.append(hardlinkURL)
            } else {
                try? await cacheManager.requestHardlinkForFyleMessageJoinWithStatus(with: fyleMessageJoin.typedObjectID)
                if let hardlinkURL = cacheManager.getCachedHardlinkForFyleMessageJoinWithStatus(with: fyleMessageJoin.typedObjectID)?.hardlinkURL {
                    self.quicklookURLs.append(hardlinkURL)
                }
            }
        }
    }
}


fileprivate extension FyleMessageJoinWithStatus.FyleMessageJoinType {
    
    var orderValue: Int {
        switch self {
        case .photo: return 0
        case .video: return 1
        case .audio: return 2
        case .other: return 3
        }
    }
    
}
