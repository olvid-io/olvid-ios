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
import UniformTypeIdentifiers
import os.log
import ObvAppCoreConstants

@available(iOS 17.0, *)
@Observable
class StorageManagementInlineFilesViewModel: StorageManagementInlineFilesViewModelProtocol {
    
    private let MAX_DISPLAYED_FILES: Int = 30
    
    typealias StorageFileRepresentation = FyleMessageJoinWithStatus
    
    private(set) var storageFiles: [FyleMessageJoinWithStatus]
    
    private(set) var storageFilesMediaViewModels = [StorageManagementMediaCellViewModel]()
    
    var displayableStorageFiles: [FyleMessageJoinWithStatus] {
        storageFiles.count < MAX_DISPLAYED_FILES ? storageFiles : Array(storageFiles[0..<MAX_DISPLAYED_FILES])
    }
    
    let cacheManager: DiscussionCacheManager
    
    init(files: [FyleMessageJoinWithStatus], cacheManager: DiscussionCacheManager) {
        self.storageFiles = files
        self.cacheManager = cacheManager
        
        createCellViewModels()
    }
    
    private func createCellViewModels() {
        self.storageFilesMediaViewModels = storageFiles.compactMap({ attachment in
            StorageManagementMediaCellViewModel(attachment: attachment, cacheManager: cacheManager)
        })
    }
    
    @ViewBuilder
    func cellForSizing() -> some View {
        StorageManagementMediaCellView(model: EmptyStorageManagementMediaCellViewModel(), style: .small)
    }
    
    @ViewBuilder
    func cellForStorageFile(_ storageFile: FyleMessageJoinWithStatus) -> some View {
        if let viewModel = storageFilesMediaViewModels.first(where: { $0.attachment == storageFile }) {
            StorageManagementMediaCellView(model: viewModel, style: .small)
        } else {
            EmptyView()
        }
    }
    
    func onTask() async throws {}
}
