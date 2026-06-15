/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import CoreData
import ObvTypes
import ObvHistoryTransfer

@MainActor
final class ZipExportViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private let historyTransferDataSourceHelper: HistoryTransferDataSourceHelper
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.historyTransferDataSourceHelper = .init(backgroundContext: backgroundContext)
    }
    
}


// MARK: - Implementing ZipExportViewDataSource


extension ZipExportViewAppDataSource: ZipExportViewDataSource {
    
    func evaluateZipFileContentToExpect(_ view: ObvHistoryTransfer.ComputingExportZipFileSizeView, ownedCryptoId: ObvTypes.ObvCryptoId, scope: ObvHistoryTransfer.TransferScope) async throws -> ObvHistoryTransfer.ComputingExportZipFileSizeView.ZipFileContentToExpect {
        return try await self.evaluateZipFileContentToExpect(ownedCryptoId: ownedCryptoId, scope: scope)
    }
    
}


// MARK: - Private methods

extension ZipExportViewAppDataSource {
    
    func evaluateZipFileContentToExpect(ownedCryptoId: ObvTypes.ObvCryptoId, scope: ObvHistoryTransfer.TransferScope) async throws -> ObvHistoryTransfer.ComputingExportZipFileSizeView.ZipFileContentToExpect {
        
        var numberOfMessages = 0
        let discussionIdentifiers = try await self.historyTransferDataSourceHelper.getAllDiscussionIdentifiers(ownedCryptoId: ownedCryptoId)
        for discussionIdentifier in discussionIdentifiers {
            let (_, messageIdentifiers) = try await historyTransferDataSourceHelper.getTitleAndAllMessageIdentifiersOfDiscussion(discussionIdentifier: discussionIdentifier)
            numberOfMessages += messageIdentifiers.count
        }
        
        let numberOfDiscussions = discussionIdentifiers.count

        let numberOfFiles: Int
        let fileSizeInBytes: UInt64
        switch scope {
        case .messagesOnly:
            numberOfFiles = 0
            fileSizeInBytes = 0
        case .messagesAndAttachments:
            let fileSizeForSha256 = try await self.historyTransferDataSourceHelper.getAllHashAndSizesOfFyles(ownedCryptoId: ownedCryptoId)
            numberOfFiles = fileSizeForSha256.count
            fileSizeInBytes = fileSizeForSha256.reduce(0) { $0 + $1.value } as UInt64
        }
        
        return .init(numberOfMessages: numberOfMessages,
                     numberOfDiscussions: numberOfDiscussions,
                     numberOfFiles: numberOfFiles,
                     fileSizeInBytes: fileSizeInBytes)
    }
    
}
