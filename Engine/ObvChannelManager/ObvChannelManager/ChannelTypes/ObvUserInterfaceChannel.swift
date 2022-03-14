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
import os.log
import CoreData
import OlvidUtils
import ObvCrypto
import ObvMetaManager
import ObvTypes

final class ObvUserInterfaceChannel: ObvChannel {
    
    private static let logCategory = "ObvUserInterfaceChannel"
    
    let cryptoSuiteVersion: SuiteVersion = 0
    let toOwnedIdentity: ObvCryptoIdentity
    
    private static let errorDomain = "ObvUserInterfaceChannel"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    init(toOwnedIdentity: ObvCryptoIdentity) {
        self.toOwnedIdentity = toOwnedIdentity
    }
    
    private func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> MessageIdentifier {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvUserInterfaceChannel.logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The notification delegate is not set")
        }

        switch message.messageType {
        case .DialogMessage:

            os_log("Posting a dialog message on a user interface channel", log: log, type: .debug)
            
            guard let message = message as? ObvChannelDialogMessageToSend else {
                os_log("Could not cast to dialog message", log: log, type: .fault)
                throw Self.makeError(message: "Could not cast to dialog message")
            }
            
            let NotificationType = ObvChannelNotification.NewUserDialogToPresent.self
            let userInfo = [NotificationType.Key.obvChannelDialogMessageToSend: message,
                            NotificationType.Key.obvContext: obvContext] as [String: Any]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                        
            let randomUid = UID.gen(with: prng)
            let messageId = MessageIdentifier(ownedCryptoIdentity: toOwnedIdentity, uid: randomUid)

            return messageId

        default:
            os_log("Inappropriate message type posted on a user interface channel", log: log, type: .fault)
            throw Self.makeError(message: "Inappropriate message type posted on a user interface channel")
        }
        
    }
}

// MARK: Implementing ObvChannel
extension ObvUserInterfaceChannel {

    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvUserInterfaceChannel.logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw ObvUserInterfaceChannel.makeError(message: "The identity delegate is not set")
        }

        let acceptableChannels: [ObvChannel]
        
        switch message.channelType {
        case .UserInterface(uuid: _, ownedIdentity: let ownedIdentity, dialogType: _):
            
            // Only dialog messages can be sent to the user interface
            guard message.messageType == .DialogMessage else {
                throw ObvUserInterfaceChannel.makeError(message: "Only dialog messages can be sent to the user interface")
            }
            
            guard try identityDelegate.isOwned(ownedIdentity, within: obvContext) else {
                os_log("The identity is not owned", log: log, type: .error)
                assertionFailure()
                throw ObvUserInterfaceChannel.makeError(message: "The identity is not owned")
            }
            
            acceptableChannels = [ObvUserInterfaceChannel(toOwnedIdentity: ownedIdentity)]
            
        default:
            
            os_log("Wrong message channel type", log: log, type: .fault)
            assertionFailure()
            throw ObvUserInterfaceChannel.makeError(message: "Wrong message channel type")

        }
        
        return acceptableChannels
        
    }
    
    static func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [MessageIdentifier: Set<ObvCryptoIdentity>] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvUserInterfaceChannel.logCategory)

        guard let acceptableChannels = try acceptableChannelsForPosting(message, delegateManager: delegateManager, within: obvContext) as? [ObvUserInterfaceChannel] else {
            assertionFailure()
            throw ObvUserInterfaceChannel.makeError(message: "Could not cast ObvChannel to ObvUserInterfaceChannel")
        }

        guard acceptableChannels.count == 1, let acceptableUserInterfaceChannel = acceptableChannels.first else {
            os_log("Unexpected number of user interface channels found. Expecting 1, go %d", log: log, type: .error, acceptableChannels.count)
            throw Self.makeError(message: "Unexpected number of user interface channels found")
        }

        let messageId = try acceptableUserInterfaceChannel.post(message, randomizedWith: prng, delegateManager: delegateManager, within: obvContext)
        let ownedIdentity = acceptableUserInterfaceChannel.toOwnedIdentity

        return [messageId: Set([ownedIdentity])]
        
    }

}
