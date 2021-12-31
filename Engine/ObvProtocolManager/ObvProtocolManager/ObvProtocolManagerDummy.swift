/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import os.log
import CoreData
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils


public final class ObvProtocolManagerDummy: ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate {
    
    static let defaultLogSubsystem = "io.olvid.protocol"
    lazy public var logSubsystem: String = {
        return ObvProtocolManagerDummy.defaultLogSubsystem
    }()
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvProtocolManagerDummy")
    }
    
    public func applicationDidStartRunning(flowId: FlowIdentifier) {}
    public func applicationDidEnterBackground() {}

    private static let errorDomain = "ObvProtocolManagerDummy"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Instance variables
    
    private var log: OSLog
    
    // MARK: Initialiser
    
    public init() {
        self.log = OSLog(subsystem: ObvProtocolManagerDummy.defaultLogSubsystem, category: "ObvProtocolManagerDummy")
    }

    
    public func deleteProtocolMetadataRelatingToContact(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("deleteProtocolMetadataRelatingToContact does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func process(_: ObvProtocolReceivedMessage, within: ObvContext) throws {
        os_log("process(_: ObvProtocolReceivedMessage, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func process(_: ObvProtocolReceivedDialogResponse, within: ObvContext) throws {
        os_log("process(_: ObvProtocolReceivedDialogResponse, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func process(_: ObvProtocolReceivedServerResponse, within: ObvContext) throws {
        os_log("process(_: ObvProtocolReceivedServerResponse, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func abortProtocol(withProtocolInstanceUid: UID, forOwnedIdentity: ObvCryptoIdentity) throws {
        os_log("abortProtocol(withProtocolInstanceUid: UID, forOwnedIdentity: ObvCryptoIdentity) does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func getInitialMessageForTrustEstablishmentProtocol(of: ObvCryptoIdentity, withFullDisplayName: String, forOwnedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails: ObvIdentityCoreDetails, usingProtocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForTrustEstablishmentProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func getInitialMessageForContactMutualIntroductionProtocol(of: ObvCryptoIdentity, withContactIdentityCoreDetails: ObvIdentityCoreDetails, with: ObvCryptoIdentity, withOtherContactIdentityCoreDetails: ObvIdentityCoreDetails, byOwnedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForContactMutualIntroductionProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: ObvGroupCoreDetails, photoURL: URL?, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, ownedIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupCreationMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ObvCryptoIdentity, andTheDeviceUid: UID, ofTheContactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForChannelCreationWithContactDeviceProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func startFullRatchetProtocolForObliviousChannelBetween(currentDeviceUid: UID, andRemoteDeviceUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity) throws {
        os_log("startFullRatchetProtocolForObliviousChannelBetween does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoIdentity, publishedIdentityDetailsVersion: Int) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForIdentityDetailsPublicationProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func getAddGroupMembersMessageForAddingMembersToContactGroupOwned(groupUid: UID, ownedIdentity: ObvCryptoIdentity, newGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getAddGroupMembersMessageForAddingMembersToContactGroupOwned does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getRemoveGroupMembersMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getLeaveGroupJoinedMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func getInitiateContactDeletionMessageForObliviousChannelManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateContactDeletionMessageForObliviousChannelManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func getInitiateAddKeycloakContactMessageForObliviousChannelManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd contactIdentity: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateAddKeycloakContactMessageForObliviousChannelManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }

    public func getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupMembersQueryMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw NSError()
    }
    
    public func getTriggerReinviteMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, memberIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getTriggerReinviteMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getTriggerReinviteMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDeviceDiscoveryForContactIdentityProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getInitialMessageForDeviceDiscoveryForContactIdentityProtocol does nothing in this dummy implementation")
    }
    
    public func getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        os_log("getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances does nothing in this dummy implementation")
    }

    public func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDownloadIdentityPhotoChildProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getInitialMessageForDownloadIdentityPhotoChildProtocol does nothing in this dummy implementation")
    }

    public func getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDownloadGroupPhotoChildProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getInitialMessageForDownloadGroupPhotoChildProtocol does nothing in this dummy implementation")
    }

    public func getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, signature: Data) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForTrustEstablishmentWithMutualScanProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getInitialMessageForTrustEstablishmentWithMutualScanProtocol does nothing in this dummy implementation")
    }


    // MARK: - Implementing ObvManager
    
    public let requiredDelegates = [ObvEngineDelegateType]()
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}

}
