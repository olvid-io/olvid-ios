/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvEncoder
import ObvCrypto


public struct ObvDialog: ObvFailableCodable, Equatable {
    
    // Allow to store the encodedElements
    public let uuid: UUID
    public let encodedElements: ObvEncoded
    public let ownedCryptoId: ObvCryptoId
    public let category: Category
    public private(set) var encodedResponse: ObvEncoded?
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    public static func == (lhs: ObvDialog, rhs: ObvDialog) -> Bool {
        guard lhs.uuid == rhs.uuid else { return false }
        guard lhs.ownedCryptoId == rhs.ownedCryptoId else { return false }
        guard lhs.category == rhs.category else { return false }
        return true
    }

    public init(uuid: UUID, encodedElements: ObvEncoded, ownedCryptoId: ObvCryptoId, category: Category) {
        self.uuid = uuid
        self.encodedElements = encodedElements
        self.ownedCryptoId = ownedCryptoId
        self.category = category
        self.encodedResponse = nil
    }
    
    public mutating func setResponseToAcceptInviteGeneric(acceptInvite: Bool) throws {

        switch self.category {

        case .inviteSent,
                .invitationAccepted,
                .sasExchange,
                .sasConfirmed,
                .mutualTrustConfirmed,
                .mediatorInviteAccepted,
                .oneToOneInvitationSent,
                .freezeGroupV2Invite,
                .syncRequestReceivedFromOtherOwnedDevice:
            throw Self.makeError(message: "Bad category")
            
        case .acceptInvite:
            try setResponseToAcceptInvite(acceptInvite: acceptInvite)
            
        case .acceptMediatorInvite:
            try setResponseToAcceptMediatorInvite(acceptInvite: acceptInvite)

        case .acceptGroupInvite:
            try setResponseToAcceptGroupInvite(acceptInvite: acceptInvite)

        case .oneToOneInvitationReceived:
            try setResponseToOneToOneInvitationReceived(invitationAccepted: acceptInvite)

        case .acceptGroupV2Invite:
            try setResponseToAcceptGroupV2Invite(acceptInvite: acceptInvite)
        }
        
    }
    
    private mutating func setResponseToAcceptInvite(acceptInvite: Bool) throws {
        switch category {
        case .acceptInvite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    public func settingResponseToAcceptInvite(acceptInvite: Bool) throws -> Self {
        var localCopy = self
        try localCopy.setResponseToAcceptInvite(acceptInvite: acceptInvite)
        return localCopy
    }
    
    public mutating func setResponseToSasExchange(otherSas: Data) throws {
        switch category {
        case .sasExchange:
            encodedResponse = otherSas.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    private mutating func setResponseToAcceptMediatorInvite(acceptInvite: Bool) throws {
        switch category {
        case .acceptMediatorInvite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public func settingResponseToAcceptMediatorInvite(acceptInvite: Bool) throws -> Self {
        var localCopy = self
        try localCopy.setResponseToAcceptMediatorInvite(acceptInvite: acceptInvite)
        return localCopy
    }
    
    
    private mutating func setResponseToAcceptGroupInvite(acceptInvite: Bool) throws {
        switch category {
        case .acceptGroupInvite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }

    
    public func settingResponseToAcceptGroupInvite(acceptInvite: Bool) throws -> Self {
        var localCopy = self
        try localCopy.setResponseToAcceptGroupInvite(acceptInvite: acceptInvite)
        return localCopy
    }

    
    private mutating func setResponseToOneToOneInvitationReceived(invitationAccepted: Bool) throws {
        switch category {
        case .oneToOneInvitationReceived:
            encodedResponse = invitationAccepted.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public func settingResponseToOneToOneInvitationReceived(invitationAccepted: Bool) throws -> Self {
        var localCopy = self
        try localCopy.setResponseToOneToOneInvitationReceived(invitationAccepted: invitationAccepted)
        return localCopy
    }
    
    
    public mutating func cancelOneToOneInvitationSent() throws {
        switch category {
        case .oneToOneInvitationSent:
            encodedResponse = true.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public func cancellingOneToOneInvitationSent() throws -> Self {
        var localCopy = self
        try localCopy.cancelOneToOneInvitationSent()
        return localCopy
    }

    
    private mutating func setResponseToAcceptGroupV2Invite(acceptInvite: Bool) throws {
        switch category {
        case .acceptGroupV2Invite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public func settingResponseToAcceptGroupV2Invite(acceptInvite: Bool) throws -> Self {
        var localCopy = self
        try localCopy.setResponseToAcceptGroupV2Invite(acceptInvite: acceptInvite)
        return localCopy
    }
    
    
    public var actionRequired: Bool {
        switch self.category {
        case .inviteSent,
             .invitationAccepted,
             .mutualTrustConfirmed,
             .mediatorInviteAccepted,
             .oneToOneInvitationSent,
             .freezeGroupV2Invite,
             .syncRequestReceivedFromOtherOwnedDevice:
            return false
        case .acceptInvite,
             .sasExchange,
             .sasConfirmed,
             .acceptMediatorInvite,
             .acceptGroupInvite,
             .oneToOneInvitationReceived,
             .acceptGroupV2Invite:
            return true
        }
    }
}

// MARK: ObvDialog Category
extension ObvDialog {
    
    public enum Category: ObvFailableCodable, CustomStringConvertible, Equatable {
        
        case inviteSent(contactIdentity: ObvURLIdentity) // Used within the protocol allowing establish trust
        case acceptInvite(contactIdentity: ObvGenericIdentity) // Used within the protocol allowing establish trust
        case invitationAccepted(contactIdentity: ObvGenericIdentity)
        case sasExchange(contactIdentity: ObvGenericIdentity, sasToDisplay: Data, numberOfBadEnteredSas: Int)
        case sasConfirmed(contactIdentity: ObvGenericIdentity, sasToDisplay: Data, sasEntered: Data)
        case mutualTrustConfirmed(contactIdentity: ObvGenericIdentity)
        
        // Dialogs related to mediator invites
        case acceptMediatorInvite(contactIdentity: ObvGenericIdentity, mediatorIdentity: ObvGenericIdentity) // The mediatorIdentity corresponds to a ObvContactIdentity
        case mediatorInviteAccepted(contactIdentity: ObvGenericIdentity, mediatorIdentity: ObvGenericIdentity) // The mediatorIdentity corresponds to a ObvContactIdentity
        
        // Dialogs related to contact groups
        case acceptGroupInvite(groupMembers: Set<ObvGenericIdentity>, groupOwner: ObvGenericIdentity)
        
        // Dialogs related to OneToOne invitations
        case oneToOneInvitationSent(contactIdentity: ObvGenericIdentity)
        case oneToOneInvitationReceived(contactIdentity: ObvGenericIdentity)
        
        // Dialogs related to Groups V2
        case acceptGroupV2Invite(inviter: ObvCryptoId, group: ObvGroupV2)
        case freezeGroupV2Invite(inviter: ObvCryptoId, group: ObvGroupV2)

        // Dialogs related to the synchronization between owned devices
        case syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: Data, syncAtom: ObvSyncAtom)

        private var raw: Int {
            switch self {
            case .inviteSent: return 0
            case .acceptInvite: return 1
            case .invitationAccepted: return 2
            case .sasExchange: return 3
            case .sasConfirmed: return 4
            case .mutualTrustConfirmed: return 5
            case .acceptMediatorInvite: return 6
            case .mediatorInviteAccepted: return 7
            case .acceptGroupInvite: return 8
            // case .increaseMediatorTrustLevelRequired: return 11
            // case .increaseGroupOwnerTrustLevelRequired: return 12
            // case .autoconfirmedContactIntroduction: return 13
            case .oneToOneInvitationSent: return 14
            case .oneToOneInvitationReceived: return 15
            case .acceptGroupV2Invite: return 16
            case .freezeGroupV2Invite: return 17
            case .syncRequestReceivedFromOtherOwnedDevice: return 18
            }
        }
        
        public static func == (lhs: Category, rhs: Category) -> Bool {
            switch lhs {
            case .inviteSent(contactIdentity: let c1):
                switch rhs {
                case .inviteSent(contactIdentity: let c2):
                    return c1 == c2
                default:
                    return false
                }
            case .acceptInvite(contactIdentity: let c1):
                switch rhs {
                case .acceptInvite(contactIdentity: let c2):
                    return c1 == c2
                default:
                    return false
                }
            case .invitationAccepted(contactIdentity: let c1):
                switch rhs {
                case .invitationAccepted(contactIdentity: let c2):
                    return c1 == c2
                default:
                    return false
                }
            case .sasExchange(contactIdentity: let c1, sasToDisplay: let s1, numberOfBadEnteredSas: let n1):
                switch rhs {
                case .sasExchange(contactIdentity: let c2, sasToDisplay: let s2, numberOfBadEnteredSas: let n2):
                    return c1 == c2 && s1 == s2 && n1 == n2
                default:
                    return false
                }
            case .sasConfirmed(contactIdentity: let c1, sasToDisplay: let s1, sasEntered: let e1):
                switch rhs {
                case .sasConfirmed(contactIdentity: let c2, sasToDisplay: let s2, sasEntered: let e2):
                    return c1 == c2 && s1 == s2 && e1 == e2
                default:
                    return false
                }
            case .mutualTrustConfirmed(contactIdentity: let c1):
                switch rhs {
                case .mutualTrustConfirmed(contactIdentity: let c2):
                    return c1 == c2
                default:
                    return false
                }
            case .acceptMediatorInvite(contactIdentity: let a1, mediatorIdentity: let b1):
                switch rhs {
                case .acceptMediatorInvite(contactIdentity: let a2, mediatorIdentity: let b2):
                    return a1 == a2 && b1 == b2
                default:
                    return false
                }
            case .mediatorInviteAccepted(contactIdentity: let a1, mediatorIdentity: let b1):
                switch rhs {
                case .mediatorInviteAccepted(contactIdentity: let a2, mediatorIdentity: let b2):
                    return a1 == a2 && b1 == b2
                default:
                    return false
                }
            case .acceptGroupInvite(groupMembers: let a1, groupOwner: let b1):
                switch rhs {
                case .acceptGroupInvite(groupMembers: let a2, groupOwner: let b2):
                    return a1 == a2 && b1 == b2
                default:
                    return false
                }
            case .oneToOneInvitationSent(contactIdentity: let a1):
                switch rhs {
                case .oneToOneInvitationSent(contactIdentity: let a2):
                    return a1 == a2
                default:
                    return false
                }
            case .oneToOneInvitationReceived(contactIdentity: let a1):
                switch rhs {
                case .oneToOneInvitationReceived(contactIdentity: let a2):
                    return a1 == a2
                default:
                    return false
                }
            case .acceptGroupV2Invite(inviter: let a1, group: let b1):
                switch rhs {
                case .acceptGroupV2Invite(inviter: let a2, group: let b2):
                    return a1 == a2 && b1 == b2
                default:
                    return false
                }
            case .freezeGroupV2Invite(inviter: let a1, group: let b1):
                switch rhs {
                case .freezeGroupV2Invite(inviter: let a2, group: let b2):
                    return a1 == a2 && b1 == b2
                default:
                    return false
                }
            case .syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: let a1, syncAtom: let b1):
                switch rhs {
                case .syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: let a2, syncAtom: let b2):
                    return a1 == a2 && b1 == b2
                default:
                    return false
                }
            }
        }
        
        public func obvEncode() throws -> ObvEncoded {
            let encodedVars: ObvEncoded
            switch self {
            case .inviteSent(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .acceptInvite(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .invitationAccepted(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .sasExchange(contactIdentity: let contactIdentity, sasToDisplay: let sasToDisplay, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                encodedVars = [contactIdentity, sasToDisplay, numberOfBadEnteredSas].obvEncode()
            case .sasConfirmed(contactIdentity: let contactIdentity, sasToDisplay: let sasToDisplay, sasEntered: let sasEntered):
                encodedVars = [contactIdentity, sasToDisplay, sasEntered].obvEncode()
            case .mutualTrustConfirmed(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .acceptMediatorInvite(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                encodedVars = [contactIdentity, mediatorIdentity].obvEncode()
            case .mediatorInviteAccepted(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                encodedVars = [contactIdentity, mediatorIdentity].obvEncode()
            case .acceptGroupInvite(groupMembers: let groupMembers, groupOwner: let groupOwner):
                let encodedGroupMembers = (groupMembers.map { $0.obvEncode() }).obvEncode()
                let encodedGroupOwner = groupOwner.obvEncode()
                encodedVars = [encodedGroupMembers, encodedGroupOwner].obvEncode()
            case .oneToOneInvitationSent(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .oneToOneInvitationReceived(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .acceptGroupV2Invite(inviter: let inviter, group: let group):
                encodedVars = [inviter.obvEncode(), try group.obvEncode()].obvEncode()
            case .freezeGroupV2Invite(inviter: let inviter, group: let group):
                encodedVars = [inviter.obvEncode(), try group.obvEncode()].obvEncode()
            case .syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: let otherOwnedDeviceIdentifier, syncAtom: let syncAtom):
                encodedVars = [otherOwnedDeviceIdentifier, syncAtom].obvEncode()
            }
            let encodedObvDialog = [raw.obvEncode(), encodedVars].obvEncode()
            return encodedObvDialog
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 2) else { return nil }
            guard let raw: Int = try? listOfEncoded[0].obvDecode() else { return nil }
            switch raw {
            case 0:
                /* inviteSent */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvURLIdentity else { return nil }
                self = .inviteSent(contactIdentity: contactIdentity)
            case 1:
                /* acceptInvite */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity else { return nil }
                self = .acceptInvite(contactIdentity: contactIdentity)
            case 2:
                /* invitationAccepted */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity else { return nil }
                self = .invitationAccepted(contactIdentity: contactIdentity)
            case 3:
                /* sasExchange */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 3) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity  else { return nil }
                guard let sasToDisplay = try? encodedVars[1].obvDecode() as Data else { return nil }
                guard let numberOfBadEnteredSas = try? encodedVars[2].obvDecode() as Int else { return nil }
                self = .sasExchange(contactIdentity: contactIdentity, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: numberOfBadEnteredSas)
            case 4:
                /* sasConfirmed */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 3) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity  else { return nil }
                guard let sasToDisplay = try? encodedVars[1].obvDecode() as Data else { return nil }
                guard let sasEntered = try? encodedVars[2].obvDecode() as Data else { return nil }
                self = .sasConfirmed(contactIdentity: contactIdentity, sasToDisplay: sasToDisplay, sasEntered: sasEntered)
            case 5:
                /* mutualTrustConfirmed */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity else { return nil }
                self = .mutualTrustConfirmed(contactIdentity: contactIdentity)
            case 6:
                /* acceptMediatorInvite */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity  else { return nil }
                guard let mediatorIdentity = try? encodedVars[1].obvDecode() as ObvGenericIdentity else { return nil }
                self = .acceptMediatorInvite(contactIdentity: contactIdentity, mediatorIdentity: mediatorIdentity)
            case 7:
                /* mediatorInviteAccepted */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity  else { return nil }
                guard let mediatorIdentity = try? encodedVars[1].obvDecode() as ObvGenericIdentity else { return nil }
                self = .mediatorInviteAccepted(contactIdentity: contactIdentity, mediatorIdentity: mediatorIdentity)
            case 8:
                /* acceptGroupInvite */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { return nil }
                let groupMembers: Set<ObvGenericIdentity>
                do {
                    guard let listOfEncoded = [ObvEncoded](encodedVars[0]) else { return nil }
                    groupMembers = try Set(listOfEncoded.map { try $0.obvDecode() as ObvGenericIdentity })
                } catch {
                    return nil
                }
                guard let groupOwner = try? encodedVars[1].obvDecode() as ObvGenericIdentity else { return nil }
                self = .acceptGroupInvite(groupMembers: groupMembers, groupOwner: groupOwner)
//            case 11:
//                /* Was increaseMediatorTrustLevelRequired */
//            case 12:
//                /* Was increaseGroupOwnerTrustLevelRequired */
//            case 13:
//                /* Was autoconfirmedContactIntroduction */
            case 14:
                /* oneToOneInvitationSent */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity else { return nil }
                self = .oneToOneInvitationSent(contactIdentity: contactIdentity)
            case 15:
                /* oneToOneInvitationReceived */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity else { return nil }
                self = .oneToOneInvitationReceived(contactIdentity: contactIdentity)
            case 16:
                /* acceptGroupV2Invite */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { assertionFailure(); return nil }
                guard let inviter = try? encodedVars[0].obvDecode() as ObvCryptoId else { assertionFailure(); return nil }
                guard let group = try? encodedVars[1].obvDecode() as ObvGroupV2 else { assertionFailure(); return nil }
                self = .acceptGroupV2Invite(inviter: inviter, group: group)
            case 17:
                /* freezeGroupV2Invite */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { assertionFailure(); return nil }
                guard let inviter = try? encodedVars[0].obvDecode() as ObvCryptoId else { assertionFailure(); return nil }
                guard let group = try? encodedVars[1].obvDecode() as ObvGroupV2 else { assertionFailure(); return nil }
                self = .freezeGroupV2Invite(inviter: inviter, group: group)
            case 18:
                /* syncRequestReceivedFromOtherOwnedDevice */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { assertionFailure(); return nil }
                guard let otherOwnedDeviceIdentifier = try? encodedVars[0].obvDecode() as Data else { assertionFailure(); return nil }
                guard let syncAtom = try? encodedVars[1].obvDecode() as ObvSyncAtom else { assertionFailure(); return nil }
                self = .syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier, syncAtom: syncAtom)
            default:
                return nil
            }
        }
        
        public var description: String {
            switch self {
            case .acceptInvite:
                return "acceptInvite"
            case .inviteSent:
                return "inviteSent"
            case .invitationAccepted:
                return "invitationAccepted"
            case .sasConfirmed:
                return "sasConfirmed"
            case .sasExchange:
                return "sasExchange"
            case .mutualTrustConfirmed:
                return "mutualTrustConfirmed"
            case .acceptMediatorInvite:
                return "acceptMediatorInvite"
            case .mediatorInviteAccepted:
                return "mediatorInviteAccepted"
            case .acceptGroupInvite:
                return "acceptGroupInvite"
            case .oneToOneInvitationSent:
                return "oneToOneInvitationSent"
            case .oneToOneInvitationReceived:
                return "oneToOneInvitationReceived"
            case .acceptGroupV2Invite:
                return "acceptGroupV2Invite"
            case .freezeGroupV2Invite:
                return "freezeGroupV2Invite"
            case .syncRequestReceivedFromOtherOwnedDevice:
                return "syncRequestReceivedFromOtherOwnedDevice"
            }
        }

    }
}

// MARK: Implementing ObvCodable
extension ObvDialog {
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 4) else { return nil }
        do { uuid = try listOfEncoded[0].obvDecode() } catch { return nil }
        encodedElements = listOfEncoded[1]
        do {
            self.ownedCryptoId = try listOfEncoded[2].obvDecode()
        } catch { return nil }
        do { category = try listOfEncoded[3].obvDecode() } catch { return nil }
    }
    
    public func obvEncode() throws -> ObvEncoded {
        return [uuid.obvEncode(), encodedElements, ownedCryptoId.obvEncode(), try category.obvEncode()].obvEncode()
    }
    
    public static func decode(_ rawData: Data) -> ObvDialog? {
        guard let obvEncoded = ObvEncoded.init(withRawData: rawData) else { return nil }
        return ObvDialog(obvEncoded)
    }
}
