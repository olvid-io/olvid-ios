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


/// Used for a transfer, on the destination device, to stream the progress of the transfer from the technical layer to the view.
public enum TransferImportState: Sendable, Hashable, Equatable {
    
    // States set by the TransferService, before the actual transfer is performed
    
    case initializing(InitializingStatusOnDestinationDevice)

    // States set by the DestinationTransferSteps
    
    case destinationTransferStepsState(DestinationTransferStepsState)

    // Canceling
    
    case canceling

}


public enum DestinationTransferStepsState: Sendable, Hashable, Equatable {
    case receivingDiscussionsList(status: ReceivingDiscussionsListStatus)
    case negotiatingWhatToReceive(status: NegotiatingWhatToReceiveStatus)
    case receivingMessages(status: ReceivingMessagesStatus)
    case receivingAttachment(status: ReceivingAttachmentstatus)
    case done(status: ReceivingDoneStatus)
}

public enum ReceivingAttachmentstatus: Sendable, Hashable, Equatable {
    case starting
    /// `bytesPerSecond` and `eta` are `nil` until enough time has elapsed to produce a meaningful rate.
    case inProgress(receivedFylesCount: Int, failedFylesCount: Int, byteCountReceived: UInt64, byteCountFailedToReceive: UInt64, numberOfFylesToReceive: Int, byteCountToReceive: UInt64, bytesPerSecond: Double?, eta: TimeInterval?)
}

public enum ReceivingMessagesStatus: Sendable, Hashable, Equatable {
    case starting
    case inProgress(receivedMessageCount: Int, missingMessageCount: Int, numberOfMessagesToReceive: Int, messagesPerSecond: Double?, eta: TimeInterval?)
}

public enum NegotiatingWhatToReceiveStatus: Sendable, Hashable, Equatable {
    case inProgress
    case done(numberOfMessagesToTransfer: Int, numberOfFylesToTransfer: Int, totalByteCountToTransfer: UInt64)
}


public enum ReceivingDiscussionsListStatus: Sendable, Hashable, Equatable {
    case inProgress
    case done(numberOfDiscussionsAvailableOnSource: Int, numberOfFylesAvailableOnSource: Int, totalByteCountAvailableOnSource: UInt64)
}


public enum InitializingStatusOnDestinationDevice: Sendable, Hashable, Equatable {
    case inProgress
    case connectingToSourceDeviceOrUnzippingFile(progress: Double) // progress only used when unzipping
    case connectedToSourceDeviceOrFileUnzipped
}


public enum ReceivingDoneStatus: Sendable, Hashable, Equatable {
    case exportWasSuccessful(failedFylesCount: Int)
    case exportWasCancelledByUser
    case exportFailed
    case exportFailedAsIdentitiesDidNotMatch
}


// MARK: - Helpers

extension ReceivingAttachmentstatus {
    
    var unitCount: (completed: Int64, total: Int64)? {
        switch self {
        case .starting:
            return nil
        case .inProgress(receivedFylesCount: _, failedFylesCount: _, byteCountReceived: let byteCountReceived, byteCountFailedToReceive: let byteCountFailedToReceive, numberOfFylesToReceive: _, byteCountToReceive: let byteCountToReceive, bytesPerSecond: _, eta: _):
            let total = Int64(byteCountToReceive)
            let completed = Int64(byteCountReceived) + Int64(byteCountFailedToReceive)
            return (completed, total)
        }
    }
    
    var progress: Double? {
        guard let unitCount else { return nil }
        guard unitCount.total > 0 else { return nil }
        return min(1, Double(unitCount.completed) / Double(unitCount.total))
    }

}
