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
import OlvidUtils
import ObvMetaManager
import ObvTypes
import ObvCrypto


struct OwnedIdentityRestorationHelper {
    
    let identityNode: any ObvSyncSnapshotNode
    let currentDeviceName: String
    let rawAuthState: Data?
    let transferredIdentity: ObvCryptoIdentity
    
    let prng: any PRNGService
    
    let identityDelegate: any ObvIdentityDelegate
    let networkFetchDelegate: any ObvNetworkFetchDelegate
    let protocolStarterDelegate: any ProtocolStarterDelegate
    let channelDelegate: any ObvChannelDelegate
    
    
    init(identityNode: any ObvSyncSnapshotNode, currentDeviceName: String, rawAuthState: Data?, transferredIdentity: ObvCryptoIdentity, prng: any PRNGService, identityDelegate: any ObvIdentityDelegate, networkFetchDelegate: any ObvNetworkFetchDelegate, protocolStarterDelegate: any ProtocolStarterDelegate, channelDelegate: any ObvChannelDelegate) {
        self.identityNode = identityNode
        self.currentDeviceName = currentDeviceName
        self.rawAuthState = rawAuthState
        self.transferredIdentity = transferredIdentity
        self.prng = prng
        self.identityDelegate = identityDelegate
        self.networkFetchDelegate = networkFetchDelegate
        self.protocolStarterDelegate = protocolStarterDelegate
        self.channelDelegate = channelDelegate
    }

    enum ObvError: Error {
        case definitiveError(error: Error)
        case nonDefinitiveErrors(errors: [Error])
    }
    
    func performRestoration(within obvContext: ObvContext) throws(ObvError) {
        
        // Restore the identity part of the snapshot with the identity manager
        
        do {
            try identityDelegate.restoreObvSyncSnapshotNode(identityNode, customDeviceName: currentDeviceName, within: obvContext)
        } catch {
            throw .definitiveError(error: error)
        }
        
        // If there is a rawAuthState, save it.
        // This happens when performing a keycloak restricted profile transfer: in that case, we had to authenticate on this target device.
        // We kept the authentication state to prevent another authentication request right after the transfer.
        
        if let rawAuthState {
            do {
                try identityDelegate.saveKeycloakAuthState(ownedIdentity: transferredIdentity, rawAuthState: rawAuthState, within: obvContext)
            } catch {
                assertionFailure() // In production, continue anyway
            }
        }

        // At this point, we don't want the protocol to fail if something goes wrong,
        // We juste want the user to know about it.
        // So we create a set of errors that will post back to the user if not empty
        
        var nonDefinitiveErrors = [Error]()
        
        // Download all missing user data (typically, photos)

        do {
            try downloadAllUserData(within: obvContext)
        } catch {
            assertionFailure()
            nonDefinitiveErrors.append(error) // Continue anyway
        }
        
        // Re-download all groups V2
        
        do {
            try requestReDownloadOfAllNonKeycloakGroupV2(ownedCryptoIdentity: transferredIdentity, within: obvContext)
        } catch {
            assertionFailure()
            nonDefinitiveErrors.append(error) // Continue anyway
        }
        
        // Start an owned device discovery protocol

        do {
            try startOwnedDeviceDiscoveryProtocol(for: transferredIdentity, within: obvContext)
        } catch {
            assertionFailure()
            nonDefinitiveErrors.append(error) // Continue anyway
        }
        
        // Start contact discovery protocol for all contacts
        
        do {
            try startDeviceDiscoveryForAllContactsOfOwnedIdentity(transferredIdentity, within: obvContext)
        } catch {
            assertionFailure()
            nonDefinitiveErrors.append(error) // Continue anyway
        }
        
        // Inform the network fetch delegate about the new owned identity.
        // This will open a websocket for her, and update the well known cache.
        // We need to perform this after the context is saved, as the network needs to access the
        // identity manager's database

        do {
            let activeOwnedCryptoIdsAndCurrentDeviceUIDs = try identityDelegate.getActiveOwnedIdentitiesAndCurrentDeviceUids(within: obvContext)
            let flowId = obvContext.flowId
            let networkFetchDelegate = self.networkFetchDelegate
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                Task {
                    do {
                        try await networkFetchDelegate.updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: activeOwnedCryptoIdsAndCurrentDeviceUIDs, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            }
        } catch {
            assertionFailure()
            nonDefinitiveErrors.append(error) // Continue anyway
        }
        
        if !nonDefinitiveErrors.isEmpty {
            throw .nonDefinitiveErrors(errors: nonDefinitiveErrors)
        }
        
    }
    
    
    // MARK: Downloading user data
    
    private func downloadAllUserData(within obvContext: ObvContext) throws {
        
        var errorToThrowInTheEnd: Error?
        
        do {
            let items = try identityDelegate.getAllOwnedIdentityWithMissingPhotoUrl(within: obvContext)
            for (ownedIdentity, details) in items {
                do {
                    try startDownloadIdentityPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, contactIdentity: ownedIdentity, contactIdentityDetailsElements: details)
                } catch {
                    errorToThrowInTheEnd = error
                }
            }
        }

        do {
            let items = try identityDelegate.getAllContactsWithMissingPhotoUrl(within: obvContext)
            for (ownedIdentity, contactIdentity, details) in items {
                do {
                    try startDownloadIdentityPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactIdentityDetailsElements: details)
                } catch {
                    errorToThrowInTheEnd = error
                }
            }
        }

        do {
            let items = try identityDelegate.getAllGroupsWithMissingPhotoUrl(within: obvContext)
            for (ownedIdentity, groupInformation) in items {
                do {
                    try startDownloadGroupPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, groupInformation: groupInformation)
                } catch {
                    errorToThrowInTheEnd = error
                }
            }
        }
        
        if let errorToThrowInTheEnd {
            assertionFailure()
            throw errorToThrowInTheEnd
        }

    }
    
    
    private func startDownloadIdentityPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws {
        let message = try protocolStarterDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(
            ownedIdentity: ownedIdentity,
            contactIdentity: contactIdentity,
            contactIdentityDetailsElements: contactIdentityDetailsElements)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
    }

    
    private func startDownloadGroupPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws {
        let message = try protocolStarterDelegate.getInitialMessageForDownloadGroupPhotoChildProtocol(
            ownedIdentity: ownedIdentity,
            groupInformation: groupInformation)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
    }

    
    // MARK: Re-download of Groups V2
            
    /// After a successful restore within the engine, we need to re-download all groups v2
    private func requestReDownloadOfAllNonKeycloakGroupV2(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        var errorToThrowInTheEnd: Error?

        let allNonKeycloakGroups = try identityDelegate.getAllObvGroupV2(of: ownedCryptoIdentity, within: obvContext)
            .filter({ !$0.keycloakManaged })
        for group in allNonKeycloakGroups {
            do {
                try requestReDownloadOfGroup(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    group: group,
                    within: obvContext)
            } catch {
                errorToThrowInTheEnd = error
            }
        }
        
        if let errorToThrowInTheEnd {
            assertionFailure()
            throw errorToThrowInTheEnd
        }
        
    }
    
    
    private func requestReDownloadOfGroup(ownedCryptoIdentity: ObvCryptoIdentity, group: ObvGroupV2, within obvContext: ObvContext) throws {
        guard let groupIdentifier = GroupV2.Identifier(appGroupIdentifier: group.appGroupIdentifier) else {
            assertionFailure(); return
        }
        let message = try protocolStarterDelegate.getInitiateGroupReDownloadMessageForGroupV2Protocol(
            ownedIdentity: ownedCryptoIdentity,
            groupIdentifier: groupIdentifier)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
    }
    
    
    // MARK: Start Owned device discovery protocol
    
    private func startOwnedDeviceDiscoveryProtocol(for ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        let message = try protocolStarterDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedCryptoIdentity)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        
    }
    
    
    // MARK: Start contact discovery protocol for all contacts
    
    private func startDeviceDiscoveryForAllContactsOfOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        var errorToThrowInTheEnd: Error?

        let contacts = try identityDelegate.getContactsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
        for contact in contacts {
            do {
                let message = try protocolStarterDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(
                    ownedIdentity: ownedCryptoIdentity,
                    contactIdentity: contact)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            } catch {
                errorToThrowInTheEnd = error
            }
        }
        
        if let errorToThrowInTheEnd {
            assertionFailure()
            throw errorToThrowInTheEnd
        }

    }

}
