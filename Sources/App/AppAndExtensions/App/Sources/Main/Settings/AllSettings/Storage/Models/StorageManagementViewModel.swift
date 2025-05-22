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
import ObvUICoreData
import Combine
import CoreData
import ObvTypes

@available(iOS 17.0, *)
@Observable
class StorageManagementViewModel: StorageManagementViewModelProtocol {

    static private let minThresholdForLargestFiles: Int64 = 5_000_000 // 5 MB
    
    private(set) var files: [FyleMessageJoinWithStatus] = []
    
    var chartModel: StorageManagementChartViewModel?
    
    var sentByMeModel: StorageManagementInlineFilesViewModel?
    
    var largestFilesModel: StorageManagementInlineFilesViewModel?
    
    var discussionSortOrder: StorageManagementSortOrder = .size
    
    var discussionSortDirection: StorageManagementSortDirection = .descending
    
    private(set) var cacheManager: DiscussionCacheManager
    private let ownedCryptoId: ObvCryptoId
    
    weak var router: StorageManagerRouter?
    
    init(ownedCryptoId: ObvCryptoId, cacheManager: DiscussionCacheManager) {
        self.ownedCryptoId = ownedCryptoId
        self.cacheManager = cacheManager
    }
    
    var largestFilesLocalizedThreshold: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        
        return formatter.string(fromByteCount: Self.minThresholdForLargestFiles)
    }
    
    var filesPerDiscussions: [PersistedDiscussion: [FyleMessageJoinWithStatus]] {
        
        let filesInDiscussion = files.filter { $0.message?.discussion != nil }
        
        let result = Dictionary(grouping: filesInDiscussion) { file in
            file.message!.discussion!
        }
        
        return result
    }
 
    var discussionsSorted: [PersistedDiscussion] {
        switch self.discussionSortOrder {
        case .size:
            filesPerDiscussions.keys.sorted { lhs, rhs in
                let lhFiles = filesPerDiscussions[lhs] ?? []
                let rhFiles = filesPerDiscussions[rhs] ?? []
                
                let lhTotalByteCount = lhFiles.reduce(0) { $0 + $1.totalByteCount }
                let rhTotalByteCount = rhFiles.reduce(0) { $0 + $1.totalByteCount }
                return discussionSortDirection.compare(lhs: lhTotalByteCount, rhs: rhTotalByteCount)
            }
        case .name:
            filesPerDiscussions.keys.sorted(by: { discussionSortDirection.compare(lhs: $0.title, rhs: $1.title ) })
        case .date:
            filesPerDiscussions.keys.sorted(by: { discussionSortDirection.compare(lhs: $0.timestampOfLastMessage, rhs: $1.timestampOfLastMessage) })
        default:
            Array(filesPerDiscussions.keys)
        }
    }
    
    @MainActor
    func updateDiscussionSortOrder(sortOrder: StorageManagementSortOrder) {
        if self.discussionSortOrder == sortOrder {
            self.discussionSortDirection.toggle()
        } else {
            self.discussionSortDirection = sortOrder == .name ? .ascending : .descending
            discussionSortOrder = sortOrder
        }
    }
    
    @MainActor
    func goToFilesSentByMe() {
        let viewModel = StorageManagementFileListViewModel(fetchRequest: StorageFetchRequest.sentByMe.fetchRequest(for: ownedCryptoId),
                                                           cacheManager: self.cacheManager)
        router?.navigateTo(.fileList(title: NSLocalizedString("STORAGE_SENT_BY_ME_HEADER", comment: ""),
                                     model: viewModel))
    }
    
    @MainActor
    func goToLargestFiles() {
        let viewModel = StorageManagementFileListViewModel(fetchRequest: StorageFetchRequest.largestThan(count: Self.minThresholdForLargestFiles).fetchRequest(for: ownedCryptoId),
                                                           cacheManager: self.cacheManager)
        router?.navigateTo(.fileList(title: String(format: NSLocalizedString("STORAGE_LARGEST_FILES_HEADER_%@", comment: ""), largestFilesLocalizedThreshold),
                                     model: viewModel))
    }
    
    @MainActor
    func goToAllFiles() {
        let viewModel = StorageManagementFileListViewModel(fetchRequest: StorageFetchRequest.all.fetchRequest(for: ownedCryptoId),
                                                           cacheManager: self.cacheManager)
        router?.navigateTo(.fileList(title: NSLocalizedString("STORAGE_ALL_HEADER", comment: ""),
                                     model: viewModel))
    }
    
    @MainActor func goToDiscussion(_ persistedDiscussion: PersistedDiscussion) {
        let viewModel = StorageManagementFileListViewModel(fetchRequest: StorageFetchRequest.discussion(discussionObjectID: persistedDiscussion.typedObjectID).fetchRequest(for: ownedCryptoId),
                                                           cacheManager: self.cacheManager)
        router?.navigateTo(.fileList(title: persistedDiscussion.title,
                                     model: viewModel))
    }
    

    @MainActor
    func onTaskForChartModel() async {
        let allFetchRequestStream: FetchRequestStream<FyleMessageJoinWithStatus> = StorageFetchRequest.all.fetchRequestStream(for: ownedCryptoId)
        for await files in allFetchRequestStream.stream {
            withAnimation {
                self.files = files
                self.chartModel = StorageManagementChartViewModel(filesPerDiscussions: filesPerDiscussions)
            }
        }
    }
    
    
    @MainActor
    func onTaskForSentByMeModel() async {
        let filesSentByMeFetchRequestStream: FetchRequestStream<FyleMessageJoinWithStatus> = StorageFetchRequest.sentByMe.fetchRequestStream(for: ownedCryptoId)
        for await filesSentByMe in filesSentByMeFetchRequestStream.stream {
            withAnimation {
                self.sentByMeModel = StorageManagementInlineFilesViewModel(files: filesSentByMe, cacheManager: self.cacheManager)
            }
        }
    }
    
    
    @MainActor
    func onTaskForLargestFilesModel() async {
        let largestFilesFetchRequestStream: FetchRequestStream<FyleMessageJoinWithStatus> = StorageFetchRequest.largestThan(count: Self.minThresholdForLargestFiles).fetchRequestStream(for: ownedCryptoId)
        for await largestFiles in largestFilesFetchRequestStream.stream {
            withAnimation {
                self.largestFilesModel = StorageManagementInlineFilesViewModel(files: largestFiles, cacheManager: self.cacheManager)
            }
        }
    }
    
}

@available(iOS 17.0, *)
extension StorageManagementViewModel: Identifiable, Equatable, Hashable {
    
    static func == (lhs: StorageManagementViewModel, rhs: StorageManagementViewModel) -> Bool {
        return lhs.files == rhs.files
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(files)
    }
}

@available(iOS 17.0, *)
extension StorageManagementViewModel {
    
    enum StorageFetchRequest {
        case all
        case sentByMe
        case largestThan(count: Int64)
        case discussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)

        
        // MARK: - Using FyleMessageJoinWithStatus only
        /// Fetch FyleMessageJoinWithStatus and handle duped FyleMessageJoinWithStatuses through Combine operation methods.
        func fetchRequest(for ownCryptoId: ObvCryptoId) -> NSFetchRequest<FyleMessageJoinWithStatus> {
            switch self {
            case .all: FyleMessageJoinWithStatus.getFetchRequestForAllFyleMessageJoinWithStatusDownloaded(for: ownCryptoId)
            case .sentByMe: FyleMessageJoinWithStatus.getFetchRequestForSentFyleMessageJoinWithStatusDownloaded(for: ownCryptoId)
            case .largestThan(count: let totalByteCount): FyleMessageJoinWithStatus.getFetchRequestForAllFyleMessageJoinWithStatusDownloaded(for: ownCryptoId, withMinimumThresholdOfTotalByteCount: totalByteCount)
            case .discussion(let discussionObjectID):
                FyleMessageJoinWithStatus.getFetchRequestForAllFyleMessageJoinWithStatusDownloaded(for: ownCryptoId, within: discussionObjectID)
            }
        }
        
        func publisher(for ownCryptoId: ObvCryptoId) -> AnyPublisher<[FyleMessageJoinWithStatus], Never> {
            let publisher = ObvStack.shared.viewContext.fetchRequestPublisher(for: fetchRequest(for: ownCryptoId))
                .catch { _ in Empty<NSFetchRequestPublisher<FyleMessageJoinWithStatus>.Output, Never>() }
                .eraseToAnyPublisher()
            return publisher
        }
        
        func fetchRequestStream(for ownCryptoId: ObvCryptoId) -> FetchRequestStream<FyleMessageJoinWithStatus> {
            ObvStack.shared.viewContext.fetchRequestStream(for: fetchRequest(for: ownCryptoId))
        }
    }
}

extension Sequence {
    func removingDuplicates<T: Hashable>(withSame keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { element in
            guard seen.insert(element[keyPath: keyPath]).inserted else { return false }
            return true
        }
    }
}
