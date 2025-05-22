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
import ObvTypes
import ObvCrypto

public struct ObvConstants {
    public static let serverSessionNonceLength = 32
    public static let broadcastDeviceUid = UID(uid: Data(repeating: 0xff, count: UID.length))!
    
    public static let standardDelay = 200 // In milliseconds
    public static let maximumDelay = 30 * 1000 // In milliseconds, 30 seconds

    
    public static let AttachmentCiphertextChunkTypicalLength = 10_485_760 // 2_097_152 = 2MB, 10_485_760 = 10MB
    public static let AttachmentCiphertextMaximumNumberOfChunks = 200

    public static let ServerQueryExpirationDelay = TimeInterval(days: 15)
    
    public static let relistDelay: TimeInterval = 5
    
    // Constants related to the oblivious channels
    public static let thresholdNumberOfDecryptedMessagesSinceLastFullRatchetSentMessage = 20
    public static let thresholdTimeIntervalSinceLastFullRatchetSentMessage = TimeInterval(hours: 24) // restart the full ratchet after 24 hours without response
    public static let thresholdNumberOfEncryptedMessagesPerFullRatchet = 500 // do a full ratchet after 500 messages
    public static let fullRatchetTimeIntervalValidity = TimeInterval(months: 1) // do a full ratchet every month
    public static let reprovisioningThreshold = 50 // Must be at least 3 to allow the full ratchet to finish
    public static let expirationTimeIntervalOfProvisionedKey = 86400.0 * 2 // 2 days
    
    public static let userDataRefreshInterval = 86400.0 * 7 // 7 days
    public static let getUserDataLocalFileLifespan = 86400.0 * 7 // 7 days
    
    // Constants related to protocols
    public static let defaultNumberOfDigitsForSAS = 4

    // Constants related to Trust Levels
    public static let autoAcceptTrustLevelTreshold = TrustLevel(major: 3, minor: 0)
    public static let userConfirmationTrustLevelTreshold = TrustLevel.zero
    
    // When receiving a remote silent push notification, we want to fail after a certain time
    public static let maxAllowedTimeForProcessingReceivedRemoteNotification = 15.0 // In seconds (must be a Double)
    
    // Backup related constants
    public static let maxTimeUntilBackupIsRequired: TimeInterval = 24 * 60 * 60 // In seconds, 24h
    
    // Keycloak revocation related constants
    public static let keycloakSignatureValidity: TimeInterval = 5_184_000 // In seconds, 60 days

    // Group V2 invitation nonce
    public static let groupInvitationNonceLength = 16
    public static let groupLockNonceLength = 32
    
    // Fake server used during the owned identity transfer protocol on a target device, when generating an ephemeral owned identity
    public static let ephemeralIdentityServerURL = URL(string: "ephemeral_fake_server")!
    
    public static let transferWSServerURL = URL(string: "wss://transfer.olvid.io")!


    // When a protocol requires to generate a "deterministic" seed, it must pass the appropriate enum value to the ``getDeterministicSeed(diversifiedUsing:secretMACKey:forProtocol:)`` method of the identity manager.
    public enum SeedProtocol {
        case trustEstablishmentWithSAS
        case ownedIdentityTransfer
        public var fixedByte: UInt8 {
            switch self {
            case .trustEstablishmentWithSAS:
                return 0x55
            case .ownedIdentityTransfer:
                return 0x56
            }
        }
    }
    
    
    public struct BackupSeedForLegacyIdentity {
        public static let macPayload: UInt8 = 0xcc
        public static let hashPadding = "backupKey".data(using: .utf8)!
    }
    

    public static let transferMaxPayloadSize = 10_000 // in Bytes
    
    // PreKeys related constants
    
    public static let preKeyValidityTimeInterval = TimeInterval(days: 60)
    public static let preKeyForCurrentDeviceRenewTimeInterval = TimeInterval(days: 7)
    public static let preKeyForCurrentDeviceConservationGracePeriod = TimeInterval(days: 60)
    public static let inboxMessageRetentionWhenContactIsExpected = TimeInterval(days: 14)

    // Performing a contact device discovery regularly
    
    public static let contactDeviceDiscoveryTimeInterval = TimeInterval(days: 7)
    
    // Channel creation ping interval for remote devices without channel

    public static let channelCreationPingInterval = TimeInterval(days: 3)

}
