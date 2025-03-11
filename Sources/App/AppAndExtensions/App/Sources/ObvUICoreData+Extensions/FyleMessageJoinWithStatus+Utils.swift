/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


// MARK: - Managing a progress object in the view context

extension FyleMessageJoinWithStatus {
    
    
    /// This method updates the progress object corresponding to the `FyleMessageJoinWithStatus` referenced by the objectID by updating its completed unit count.
    /// It also updates the transiant properties of the object, as these attributes are observed by the SwiftUI allowing to track the progress of the download/upload.
    @MainActor
    static func setProgressTo(_ newProgress: Float, forJoinWithObjectID joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) async {
        assert(Thread.isMainThread)
        guard let joinObject = try? FyleMessageJoinWithStatus.get(objectID: joinObjectID.objectID, within: ObvStack.shared.viewContext) else { return }
        let progressObject = joinObject.progressObject
        let newCompletedUnitCount = Int64(Double(newProgress) * Double(progressObject.totalUnitCount))
        guard newCompletedUnitCount > progressObject.completedUnitCount else { return }
        progressObject.completedUnitCount = newCompletedUnitCount
        // The following uses the progress we just updated to update the transient variables of the join object observed by SwiftUI views
        await updateTransientProgressAttributes(of: joinObject, using: progressObject)
    }
    
    
    @MainActor
    fileprivate static func updateTransientProgressAttributes(of joinObject: FyleMessageJoinWithStatus, using progressObject: ObvProgress) async {
        assert(Thread.isMainThread)
        assert(joinObject.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        if let sentJoin = joinObject as? SentFyleMessageJoinWithStatus {
            switch sentJoin.status {
            case .uploadable, .complete, .downloadable, .cancelledByServer:
                // No need to perform an update of the progress in this case
                return
            case .uploading, .downloading:
                break
            }
        }
        if let receivedJoin = joinObject as? ReceivedFyleMessageJoinWithStatus {
            switch receivedJoin.status {
            case .downloadable, .complete, .cancelledByServer:
                // No need to perform an update of the progress in this case
                return
            case .downloading:
                break
            }
        }
        let newFractionCompleted = progressObject.fractionCompleted
        if joinObject.fractionCompleted != newFractionCompleted {
            joinObject.fractionCompleted = newFractionCompleted
        }
        let newEstimatedTimeRemaining = progressObject.estimatedTimeRemaining ?? 0
        if joinObject.estimatedTimeRemaining != newEstimatedTimeRemaining {
            joinObject.estimatedTimeRemaining = newEstimatedTimeRemaining
        }
        let newThroughput = progressObject.throughput ?? 0
        if joinObject.throughput != newThroughput {
            joinObject.throughput = newThroughput
        }
    }


    /// The progress associated with this `FyleMessageJoinWithStatus` instance.
    ///
    /// If the progress already exists in the private static `progressForJoinWithObjectID` array, it is returned. Otherwise, a new progress is created, store in the array and returned.
    /// Note that we use an `ObvProgress` subclass of `Progress`, which is a custom sublcass that implements the logic allowing to compute the current throughput and estimated time remaining.
    @MainActor
    var progressObject: ObvProgress {
        assert(Thread.isMainThread)
        assert(self.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        if let progress = FyleMessageJoinWithStatus.progressForJoinWithObjectID[self.typedObjectID] {
            return progress
        } else {
            let progress = ObvProgress(totalUnitCount: self.totalByteCount)
            FyleMessageJoinWithStatus.progressForJoinWithObjectID[self.typedObjectID] = progress
            return progress
        }
    }
    
    
    /// As the progresses are only refreshed when their completed unit count is incremented, we implement this method to implement a way to force a refresh of all the progresses.
    /// This is used, in particular, when the download/upload of an attachment is stalled. In that case, we use this method to update the `ObvProgress` of the attachment, allowing to reflect the decrease of the throughput and the increase of the estimated remaining time.
    @MainActor
    static func refreshAllProgresses() async {
        let registeredFyleMessageJoinWithStatus = Set(ObvStack.shared.viewContext.registeredObjects
            .compactMap({ $0 as? FyleMessageJoinWithStatus }))
        for (joinObjectID, progressObject) in progressForJoinWithObjectID {
            guard let joinObject = registeredFyleMessageJoinWithStatus.first(where: { $0.objectID == joinObjectID.objectID }) else { continue }
            await progressObject.refreshThroughputAndEstimatedTimeRemaining()
            await updateTransientProgressAttributes(of: joinObject, using: progressObject)
        }
    }
}


extension FyleMessageJoinWithStatus {
    var fyleElement: FyleElement? {
        if let receivedJoin = self as? ReceivedFyleMessageJoinWithStatus {
            return receivedJoin.fyleElementOfReceivedJoin()
        } else if let sentJoin = self as? SentFyleMessageJoinWithStatus {
            return sentJoin.fyleElementOfSentJoin()
        } else {
            assertionFailure("Unexpected FyleMessageJoinWithStatus subclass")
            return nil
        }
    }
}
