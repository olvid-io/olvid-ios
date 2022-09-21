/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvTypes

public struct ObvConstants {
    public static let nonceLength = 32
    public static let broadcastDeviceUid = UID(uid: Data(repeating: 0xff, count: UID.length))!
    
    public static let standardDelay = 200 // In milliseconds
    public static let maximumDelay = 60 * 1000 // In milliseconds, 1 minute

    
    public static let AttachmentCiphertextChunkTypicalLength = 10_485_760 // 2_097_152 = 2MB, 10_485_760 = 10MB
    public static let AttachmentCiphertextMaximumNumberOfChunks = 200

    // Constants related to the oblivious channels
    public static let thresholdNumberOfDecryptedMessagesSinceLastFullRatchetSentMessage = 20
    public static let thresholdTimeIntervalSinceLastFullRatchetSentMessage = 7200.0 // In seconds, must be a Double
    public static let thresholdNumberOfEncryptedMessagesPerFullRatchet = 100
    public static let fullRatchetTimeIntervalValidity = 86400.0 * 7 // In seconds, must be a Double. 86400.0 * 7 means 7 days.
    public static let reprovisioningThreshold = 50 // Must be at least 3 to allow the full ratchet to finish
    public static let expirationTimeIntervalOfProvisionedKey = 86400.0 * 2 // 2 days
    
    public static let userDataRefreshInterval = 86400.0 * 7 // 7 days
    public static let getUserDataLocalFileLifespan = 86400.0 * 7 // 7 days
    
    // Constants related to protocols
    public static let defaultNumberOfDigitsForSAS = 4
    public static let mutualScanNonceLength = 16
    public static let trustEstablishmentWithMutualScanProtocolPrefix = "mutualScan".data(using: .utf8)!

    // Constants related to Trust Levels
    public static let autoAcceptTrustLevelTreshold = TrustLevel(major: 3, minor: 0)
    public static let userConfirmationTrustLevelTreshold = TrustLevel.zero
    
    // When receiving a remote silent push notification, we want to fail after a certain time
    public static let maxAllowedTimeForProcessingReceivedRemoteNotification = 15.0 // In seconds (must be a Double)
    
    // Backup related constants
    public static let maxTimeUntilBackupIsRequired: TimeInterval = 24 * 60 * 60 // In seconds, 24h
    
    // Keycloak revocation related constants
    public static let keycloakSignatureValidity: TimeInterval = 5_184_000 // In seconds, 60 days
}
