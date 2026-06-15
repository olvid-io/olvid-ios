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


/// Used for a transfer, on the source device, to stream the progress of the transfer from the technical layer to the view.
public enum TransferExportState: Sendable, Hashable, Equatable {
    
    // States set by the TransferService, before the actual transfer is performed
    
    case initializing(InitializingStatusOnSourceDevice)
    
    // States set by the SourceTransferSteps
    
    case sourceTransferStepsState(SourceTransferStepsState)
    
    // Canceling
    
    case canceling
    
    // WebRTC data channel failed and cannot be used anymore
    
    case failed
    
}


public enum SourceTransferStepsState: Sendable, Hashable, Equatable {
    case fetchingDiscussionsList(status: FetchingDiscussionsListStatus)
    case fetchingAllHashAndSizesOfFyles(status: FetchingAllHashAndSizesOfFylesStatus)
    case negotiatingWhatToSend(status: NegotiatingWhatToSendStatus)
    case sendingMessages(status: SendingMessagesStatus)
    case sendingAttachments(status: SendingAttachmentsStatus)
    case computingZipFile(status: ComputingZipFileStatus) // Only used when creating a zip (not used if the user chose WebRTC)
    case done(status: SendingDoneStatus)
}


public enum InitializingStatusOnSourceDevice: Sendable, Hashable, Equatable {
    case inProgress
    case connectingToDestinationDevice
    case connectedToDestinationDevice
}

public enum FetchingDiscussionsListStatus: Sendable, Hashable, Equatable {
    case inProgress
    case done(numberOfDiscussionsFound: Int)
}

public enum FetchingAllHashAndSizesOfFylesStatus: Sendable, Hashable, Equatable {
    case inProgress
    case done(numberOfFylesFound: Int, totalByteCount: UInt64)
}

public enum NegotiatingWhatToSendStatus: Sendable, Hashable, Equatable {
    case inProgress
    case done(numberOfMessagesToSend: Int, numberOfFylesToSend: Int, byteCountToSend: UInt64)
}

public enum SendingMessagesStatus: Sendable, Hashable, Equatable {
    case starting
    /// `messagesPerSecond` and `eta` are `nil` until enough time has elapsed to produce a meaningful rate.
    /// `eta` is expressed in seconds and represents the estimated time until all messages are sent.
    case inProgress(sentMessageCount: Int, missingMessageCount: Int, numberOfMessagesToSend: Int, messagesPerSecond: Double?, eta: TimeInterval?)
}

public enum SendingAttachmentsStatus: Sendable, Hashable, Equatable {
    case starting
    /// `bytesPerSecond` and `eta` are `nil` until enough time has elapsed to produce a meaningful rate.
    /// `eta` is expressed in seconds and represents the estimated time until all attachment bytes are sent.
    /// At completion: `sentFylesCount + failedFylesCount == numberOfFylesToSend`
    /// and `byteCountSent + byteCountFailedToSend == byteCountToSend`.
    case inProgress(sentFylesCount: Int, failedFylesCount: Int, byteCountSent: UInt64, byteCountFailedToSend: UInt64, numberOfFylesToSend: Int, byteCountToSend: UInt64, bytesPerSecond: Double?, eta: TimeInterval?)
}

public enum ComputingZipFileStatus: Sendable, Hashable, Equatable {
    case inProgress(entryNumber: UInt, total: UInt)
    case done(zipFileURL: URL)
}

public enum SendingDoneStatus: Sendable, Hashable, Equatable {
    case exportWasSuccessful(failedFylesCount: Int)
    case exportWasCancelledByUser
    case exportFailed
}


extension SendingAttachmentsStatus {
    
    var unitCount: (completed: Int64, total: Int64)? {
        switch self {
        case .starting:
            return nil
        case .inProgress(sentFylesCount: _, failedFylesCount: _, byteCountSent: let byteCountSent, byteCountFailedToSend: let byteCountFailedToSend, numberOfFylesToSend: _, byteCountToSend: let byteCountToSend, bytesPerSecond: _, eta: _):
            let total = Int64(byteCountToSend)
            let completed = Int64(byteCountSent) + Int64(byteCountFailedToSend)
            return (completed, total)
        }
    }
    
}


extension ComputingZipFileStatus {
    
    var progress: Double {
        switch self {
        case .inProgress(let entryNumber, let total):
            guard total > 0, entryNumber < total else { return 1.0 }
            return Double(entryNumber) / Double(total)
        case .done:
            return 1.0
        }
    }
    
    var progressPercentage: String {
        return "\(Int(round(100 * progress)))%"
    }

}
