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
import ObvEncoder
import ObvCrypto
import ObvTypes


public struct ObvDialog: ObvCodable, Equatable {
    
    // Allow to store the encodedElements
    public let uuid: UUID
    internal let encodedElements: ObvEncoded
    public let ownedCryptoId: ObvCryptoId
    public let category: Category
    internal var encodedResponse: ObvEncoded?
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    public static func == (lhs: ObvDialog, rhs: ObvDialog) -> Bool {
        guard lhs.uuid == rhs.uuid else { return false }
        guard lhs.ownedCryptoId == rhs.ownedCryptoId else { return false }
        guard lhs.category == rhs.category else { return false }
        return true
    }

    init(uuid: UUID, encodedElements: ObvEncoded, ownedCryptoId: ObvCryptoId, category: Category) {
        self.uuid = uuid
        self.encodedElements = encodedElements
        self.ownedCryptoId = ownedCryptoId
        self.category = category
        self.encodedResponse = nil
    }
    
    public mutating func setResponseToAcceptInvite(acceptInvite: Bool) throws {
        switch category {
        case .acceptInvite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    public mutating func setResponseToSasExchange(otherSas: Data) throws {
        switch category {
        case .sasExchange:
            encodedResponse = otherSas.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    public mutating func setResponseToAcceptMediatorInvite(acceptInvite: Bool) throws {
        switch category {
        case .acceptMediatorInvite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public mutating func setResponseToAcceptGroupInvite(acceptInvite: Bool) throws {
        switch category {
        case .acceptGroupInvite:
            encodedResponse = acceptInvite.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public mutating func rejectIncreaseGroupOwnerTrustLevelRequired() throws {
        switch category {
        case .increaseGroupOwnerTrustLevelRequired:
            encodedResponse = false.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public mutating func setResponseToOneToOneInvitationReceived(invitationAccepted: Bool) throws {
        switch category {
        case .oneToOneInvitationReceived:
            encodedResponse = invitationAccepted.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }
    
    
    public mutating func cancelOneToOneInvitationSent() throws {
        switch category {
        case .oneToOneInvitationSent:
            encodedResponse = true.obvEncode()
        default:
            throw Self.makeError(message: "Bad category")
        }
    }

    
    public var actionRequired: Bool {
        switch self.category {
        case .inviteSent,
             .invitationAccepted,
             .mutualTrustConfirmed,
             .mediatorInviteAccepted,
             .oneToOneInvitationSent,
             .autoconfirmedContactIntroduction:
            return false
        case .acceptInvite,
             .sasExchange,
             .sasConfirmed,
             .acceptMediatorInvite,
             .acceptGroupInvite,
             .increaseMediatorTrustLevelRequired,
             .oneToOneInvitationReceived,
             .increaseGroupOwnerTrustLevelRequired:
            return true
        }
    }
}

// MARK: ObvDialog Category
extension ObvDialog {
    
    public enum Category: ObvCodable, CustomStringConvertible, Equatable {
        
        case inviteSent(contactIdentity: ObvURLIdentity) // Used within the protocol allowing establish trust
        case acceptInvite(contactIdentity: ObvGenericIdentity) // Used within the protocol allowing establish trust
        case invitationAccepted(contactIdentity: ObvGenericIdentity)
        case sasExchange(contactIdentity: ObvGenericIdentity, sasToDisplay: Data, numberOfBadEnteredSas: Int)
        case sasConfirmed(contactIdentity: ObvGenericIdentity, sasToDisplay: Data, sasEntered: Data)
        case mutualTrustConfirmed(contactIdentity: ObvGenericIdentity)
        
        // Dialogs related to mediator invites
        case acceptMediatorInvite(contactIdentity: ObvGenericIdentity, mediatorIdentity: ObvGenericIdentity) // The mediatorIdentity corresponds to a ObvContactIdentity
        case increaseMediatorTrustLevelRequired(contactIdentity: ObvGenericIdentity, mediatorIdentity: ObvGenericIdentity) // The mediatorIdentity corresponds to a ObvContactIdentity
        case mediatorInviteAccepted(contactIdentity: ObvGenericIdentity, mediatorIdentity: ObvGenericIdentity) // The mediatorIdentity corresponds to a ObvContactIdentity
        case autoconfirmedContactIntroduction(contactIdentity: ObvGenericIdentity, mediatorIdentity: ObvGenericIdentity)
        
        // Dialogs related to contact groups
        case acceptGroupInvite(groupMembers: Set<ObvGenericIdentity>, groupOwner: ObvGenericIdentity)
        case increaseGroupOwnerTrustLevelRequired(groupOwner: ObvGenericIdentity)
        
        // Dialogs related to OneToOne invitations
        case oneToOneInvitationSent(contactIdentity: ObvGenericIdentity)
        case oneToOneInvitationReceived(contactIdentity: ObvGenericIdentity)

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
            case .increaseMediatorTrustLevelRequired: return 11
            case .increaseGroupOwnerTrustLevelRequired: return 12
            case .autoconfirmedContactIntroduction: return 13
            case .oneToOneInvitationSent: return 14
            case .oneToOneInvitationReceived: return 15
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
            case .increaseMediatorTrustLevelRequired(contactIdentity: let a1, mediatorIdentity: let b1):
                switch rhs {
                case .increaseMediatorTrustLevelRequired(contactIdentity: let a2, mediatorIdentity: let b2):
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
            case .increaseGroupOwnerTrustLevelRequired(groupOwner: let a1):
                switch rhs {
                case .increaseGroupOwnerTrustLevelRequired(groupOwner: let a2):
                    return a1 == a2
                default:
                    return false
                }
            case .autoconfirmedContactIntroduction(contactIdentity: let a1):
                switch rhs {
                case  .autoconfirmedContactIntroduction(contactIdentity: let a2):
                    return a1 == a2
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
            }
        }
        
        public func obvEncode() -> ObvEncoded {
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
            case .increaseMediatorTrustLevelRequired(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                encodedVars = [contactIdentity, mediatorIdentity].obvEncode()
            case .mediatorInviteAccepted(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                encodedVars = [contactIdentity, mediatorIdentity].obvEncode()
            case .autoconfirmedContactIntroduction(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                encodedVars = [contactIdentity, mediatorIdentity].obvEncode()
            case .acceptGroupInvite(groupMembers: let groupMembers, groupOwner: let groupOwner):
                let encodedGroupMembers = (groupMembers.map { $0.obvEncode() }).obvEncode()
                let encodedGroupOwner = groupOwner.obvEncode()
                encodedVars = [encodedGroupMembers, encodedGroupOwner].obvEncode()
            case .increaseGroupOwnerTrustLevelRequired(groupOwner: let groupOwner):
                encodedVars = [groupOwner].obvEncode()
            case .oneToOneInvitationSent(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
            case .oneToOneInvitationReceived(contactIdentity: let contactIdentity):
                encodedVars = [contactIdentity].obvEncode()
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
            case 11:
                /* increaseMediatorTrustLevelRequired */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity  else { return nil }
                guard let mediatorIdentity = try? encodedVars[1].obvDecode() as ObvGenericIdentity else { return nil }
                self = .increaseMediatorTrustLevelRequired(contactIdentity: contactIdentity, mediatorIdentity: mediatorIdentity)
            case 12:
                /* increaseGroupOwnerTrustLevelRequired */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 1) else { return nil }
                guard let groupOwner = try? encodedVars[0].obvDecode() as ObvGenericIdentity else { return nil }
                self = .increaseGroupOwnerTrustLevelRequired(groupOwner: groupOwner)
            case 13:
                /* autoconfirmedContactIntroduction */
                guard let encodedVars = [ObvEncoded](listOfEncoded[1], expectedCount: 2) else { return nil }
                guard let contactIdentity = try? encodedVars[0].obvDecode() as ObvGenericIdentity  else { return nil }
                guard let mediatorIdentity = try? encodedVars[1].obvDecode() as ObvGenericIdentity else { return nil }
                self = .autoconfirmedContactIntroduction(contactIdentity: contactIdentity, mediatorIdentity: mediatorIdentity)
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
            case .increaseMediatorTrustLevelRequired:
                return "increaseMediatorTrustLevelRequired"
            case .mediatorInviteAccepted:
                return "mediatorInviteAccepted"
            case .acceptGroupInvite:
                return "acceptGroupInvite"
            case .increaseGroupOwnerTrustLevelRequired:
                return "increaseGroupOwnerTrustLevelRequired"
            case .autoconfirmedContactIntroduction:
                return "autoconfirmedContactIntroduction"
            case .oneToOneInvitationSent:
                return "oneToOneInvitationSent"
            case .oneToOneInvitationReceived:
                return "oneToOneInvitationReceived"
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
            let ownedCryptoIdentity: ObvCryptoIdentity = try listOfEncoded[2].obvDecode()
            self.ownedCryptoId = ObvCryptoId.init(cryptoIdentity: ownedCryptoIdentity)
        } catch { return nil }
        do { category = try listOfEncoded[3].obvDecode() } catch { return nil }
    }
    
    public func obvEncode() -> ObvEncoded {
        return [uuid.obvEncode(), encodedElements, ownedCryptoId.cryptoIdentity.obvEncode(), category.obvEncode()].obvEncode()
    }
    
    public static func decode(_ rawData: Data) -> ObvDialog? {
        guard let obvEncoded = ObvEncoded.init(withRawData: rawData) else { return nil }
        return ObvDialog(obvEncoded)
    }
}
