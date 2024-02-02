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
import SwiftUI
import ObvUICoreData
import ObvTypes
import UI_SystemIcon


extension PersistedInvitation: InvitationViewModelProtocol {
    
    var ownedCryptoId: ObvCryptoId? {
        self.ownedIdentity?.cryptoId
    }
    
    var invitationUUID: UUID {
        self.uuid
    }
    
    var showRedDot: Bool {
        if actionRequired {
            return true
        }
        switch status {
        case .old:
            return false
        case .updated, .new:
            return true
        }
    }
    
    var titleSystemIcon: SystemIcon? {
        guard let category = obvDialog?.category else { return nil }
        switch category {
        case .inviteSent, .acceptInvite, .invitationAccepted, .sasExchange, .sasConfirmed:
            return .person
        case .mutualTrustConfirmed:
            return .personBadgeShieldCheckmark
        case .acceptMediatorInvite, .mediatorInviteAccepted:
            return .personLineDottedPerson
        case .acceptGroupInvite, .acceptGroupV2Invite, .freezeGroupV2Invite:
            return .person3
        case .oneToOneInvitationSent, .oneToOneInvitationReceived:
            return .person
        case .syncRequestReceivedFromOtherOwnedDevice:
            return nil
        }
    }
    
    
    var titleSystemIconColor: Color {
        guard let category = obvDialog?.category else { return .primary }
        switch category {
        case .inviteSent, .acceptInvite, .invitationAccepted, .sasExchange, .sasConfirmed:
            return Color(UIColor.systemPink)
        case .mutualTrustConfirmed:
            return Color(UIColor.systemGreen)
        case .acceptMediatorInvite, .mediatorInviteAccepted:
            return Color(UIColor.systemOrange)
        case .acceptGroupInvite, .acceptGroupV2Invite, .freezeGroupV2Invite:
            return Color(UIColor.systemIndigo)
        case .oneToOneInvitationSent, .oneToOneInvitationReceived:
            return Color(UIColor.systemTeal)
        case .syncRequestReceivedFromOtherOwnedDevice:
            return .primary
        }
    }


    var title: String {
        switch obvDialog?.category {
            
        case .inviteSent(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_INVITE_SENT_%@", comment: ""), 
                          contactIdentity.fullDisplayName)
            
        case .acceptInvite(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_ACCEPT_INVITE_%@", comment: ""), 
                          contactIdentity.getDisplayNameWithStyle(.short))
            
        case .invitationAccepted(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_INVITATION_ACCEPTED_%@", comment: ""), 
                          contactIdentity.getDisplayNameWithStyle(.short))
            
        case .sasExchange(let contactIdentity, _, _):
            return String(format: NSLocalizedString("INVITATION_TITLE_SAS_EXCHANGE_%@", comment: ""), 
                          contactIdentity.getDisplayNameWithStyle(.short))
            
        case .sasConfirmed(let contactIdentity, _, _):
            return String(format: NSLocalizedString("INVITATION_TITLE_SAS_CONFIRMED_%@", comment: ""), 
                          contactIdentity.getDisplayNameWithStyle(.short))

        case .mutualTrustConfirmed(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_MUTUAL_TRUST_CONFIRMED_%@", comment: ""), 
                          contactIdentity.getDisplayNameWithStyle(.short))
            
        case .acceptMediatorInvite(let contactIdentity, let mediatorIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_ACCEPT_MEDIATOR_INVITE_%@_%@", comment: ""),
                          mediatorIdentity.getDisplayNameWithStyle(.short),
                          contactIdentity.getDisplayNameWithStyle(.firstNameThenLastName))
            
        case .mediatorInviteAccepted(let contactIdentity, let mediatorIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_MEDIATOR_INVITE_ACCEPTED_%@_%@", comment: ""),
                          mediatorIdentity.getDisplayNameWithStyle(.short),
                          contactIdentity.getDisplayNameWithStyle(.firstNameThenLastName))

        case .acceptGroupInvite(_, let groupOwner):
            return String(format: NSLocalizedString("INVITATION_TITLE_ACCEPT_GROUP_INVITE_%@", comment: ""),
                          groupOwner.getDisplayNameWithStyle(.short))

        case .acceptGroupV2Invite:
            return NSLocalizedString("INVITATION_TITLE_ACCEPT_GROUP_V2_INVITE", comment: "")

        case .freezeGroupV2Invite:
            return NSLocalizedString("INVITATION_TITLE_FREEZE_GROUP_V2_INVITE", comment: "")

        case .oneToOneInvitationSent(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_ONE_TO_ONE_INVITATION_SENT_%@", comment: ""),
                          contactIdentity.getDisplayNameWithStyle(.short))
            
        case .oneToOneInvitationReceived(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_TITLE_ONE_TO_ONE_INVITATION_RECEIVED_%@", comment: ""),
                          contactIdentity.getDisplayNameWithStyle(.short))

        case nil, .syncRequestReceivedFromOtherOwnedDevice:
            return NSLocalizedString("-", comment: "")
        }
    }
    
    var subtitle: String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return self.date.formatted(date: .abbreviated, time: .shortened)
    }
    
    
    var body: String? {
        guard let obvDialog else { return nil }
        switch obvDialog.category {
            
        case .invitationAccepted(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_INVITATION_ACCEPTED_%@", comment: ""), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.short))
            
        case .sasExchange(let contactIdentity, _, _):
            return String(format: NSLocalizedString("INVITATION_BODY_SAS_EXCHANGE_%@", comment: ""), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.short))

        case .sasConfirmed(contactIdentity: let contactIdentity, _, _):
            return String(format: NSLocalizedString("INVITATION_BODY_SAS_CONFIRMED_%@", comment: ""), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.short))

        case .mutualTrustConfirmed(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_MUTUAL_TRUST_CONFIRMED_%@", comment: ""), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.short))

        case .acceptMediatorInvite(let contactIdentity, let mediatorIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_ACCEPT_MEDIATOR_INVITE_%@_%@", comment: ""),
                          mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                          contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName))

        case .mediatorInviteAccepted(let contactIdentity, let mediatorIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_MEDIATOR_INVITE_ACCEPTED_%@_%@", comment: ""),
                          mediatorIdentity.getDisplayNameWithStyle(.short),
                          contactIdentity.getDisplayNameWithStyle(.firstNameThenLastName))

        case .acceptGroupInvite(groupMembers: _, groupOwner: let groupOwner):
            return String(format: NSLocalizedString("INVITATION_BODY_ACCEPT_GROUP_INVITE_%@", comment: ""),
                          groupOwner.getDisplayNameWithStyle(.firstNameThenLastName))

        case .acceptGroupV2Invite(_, let group):
            guard let coreDetails = try? GroupV2CoreDetails.jsonDecode(serializedGroupCoreDetails: group.trustedDetailsAndPhoto.serializedGroupCoreDetails),
                  let groupName = coreDetails.groupName else {
                return NSLocalizedString("INVITATION_BODY_ACCEPT_GROUP_V2_INVITE", comment: "")
            }
            return String(format: NSLocalizedString("INVITATION_BODY_ACCEPT_GROUP_V2_INVITE_%@", comment: ""), groupName)
            
        case .freezeGroupV2Invite:
            return NSLocalizedString("INVITATION_BODY_FREEZE_GROUP_V2_INVITE", comment: "")

        case .oneToOneInvitationSent(let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_ONE_TO_ONE_INVITATION_SENT_%@", comment: ""),
                          contactIdentity.getDisplayNameWithStyle(.short))

        case .oneToOneInvitationReceived(contactIdentity: let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_ONE_TO_ONE_INVITATION_RECEIVED_%@", comment: ""),
                          contactIdentity.getDisplayNameWithStyle(.full))

        case .inviteSent(contactIdentity: let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_INVITE_SENT_%@", comment: ""),
                          contactIdentity.fullDisplayName)

        case .acceptInvite(contactIdentity: let contactIdentity):
            return String(format: NSLocalizedString("INVITATION_BODY_ACCEPT_INVITE_%@", comment: ""),
                          contactIdentity.getDisplayNameWithStyle(.full))

        case .syncRequestReceivedFromOtherOwnedDevice:
            assertionFailure("This category should not end up here")
            return nil
            
        }
    }
    
    
    var buttons: [InvitationViewButtonKind] {
        guard let obvDialog else { return [] }
        switch obvDialog.category {
            
        case .acceptInvite(contactIdentity: _):
            guard let dialogForAccepting = try? obvDialog.settingResponseToAcceptInvite(acceptInvite: true),
                  let dialogForIgnoring = try? obvDialog.settingResponseToAcceptInvite(acceptInvite: false) else {
                      assertionFailure()
                      return []
                  }
            return [
                .plainForRespondingToDialog(obvDialog: dialogForIgnoring, 
                                            localizedTitle: NSLocalizedString("Ignore", comment: ""),
                                            confirmationTitle: "ARE_YOU_SURE_YOU_WANT_TO_IGNORE_THIS_INVITATION"),
                .blueForRespondingToDialog(obvDialog: dialogForAccepting,
                                           localizedTitle: NSLocalizedString("Accept", comment: "")),
            ]
            
        case .invitationAccepted:
            return [
                .plainForAbortingProtocol(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Abort", comment: "")),
            ]
            
        case .sasExchange(contactIdentity: _, sasToDisplay: _, numberOfBadEnteredSas: _):
            return [
                .plainForAbortingProtocol(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Abort", comment: "")),
                .spacer,
            ]
            
        case .sasConfirmed:
            return [
                .plainForAbortingProtocol(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Abort", comment: "")),
            ]
            
        case .inviteSent(contactIdentity: _):
            return [
                .plainForAbortingProtocol(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Abort", comment: "")),
            ]
            
        case .mutualTrustConfirmed(contactIdentity: let contactIdentity):
            return [
                .plainForDeletingDialog(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Dismiss", comment: "")),
                .discussWithContact(contact: contactIdentity),
            ]
            
        case .acceptMediatorInvite:
            guard let dialogForAccepting = try? obvDialog.settingResponseToAcceptMediatorInvite(acceptInvite: true),
                  let dialogForIgnoring = try? obvDialog.settingResponseToAcceptMediatorInvite(acceptInvite: false) else {
                assertionFailure()
                return []
            }
            return [
                .plainForRespondingToDialog(obvDialog: dialogForIgnoring,
                                            localizedTitle: NSLocalizedString("Ignore", comment: ""),
                                            confirmationTitle: "ARE_YOU_SURE_YOU_WANT_TO_IGNORE_THIS_INVITATION"),
                .blueForRespondingToDialog(obvDialog: dialogForAccepting,
                                           localizedTitle: NSLocalizedString("Accept", comment: "")),
            ]
            
        case .mediatorInviteAccepted:
            return [
                .plainForAbortingProtocol(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Abort", comment: "")),
            ]
            
        case .acceptGroupInvite:
            guard let dialogForAccepting = try? obvDialog.settingResponseToAcceptGroupInvite(acceptInvite: true),
                  let dialogForIgnoring = try? obvDialog.settingResponseToAcceptGroupInvite(acceptInvite: false) else {
                assertionFailure()
                return []
            }
            return [
                .plainForRespondingToDialog(obvDialog: dialogForIgnoring,
                                            localizedTitle: NSLocalizedString("Decline", comment: ""),
                                            confirmationTitle: "ARE_YOU_SURE_YOU_WANT_TO_DECLINE_THIS_INVITATION"),
                .blueForRespondingToDialog(obvDialog: dialogForAccepting,
                                           localizedTitle: NSLocalizedString("Accept", comment: "")),
            ]
            
        case .acceptGroupV2Invite:
            guard let dialogForAccepting = try? obvDialog.settingResponseToAcceptGroupV2Invite(acceptInvite: true),
                  let dialogForIgnoring = try? obvDialog.settingResponseToAcceptGroupV2Invite(acceptInvite: false) else {
                assertionFailure()
                return []
            }
            return [
                .plainForRespondingToDialog(obvDialog: dialogForIgnoring,
                                            localizedTitle: NSLocalizedString("Decline", comment: ""),
                                            confirmationTitle: "ARE_YOU_SURE_YOU_WANT_TO_DECLINE_THIS_INVITATION"),
                .blueForRespondingToDialog(obvDialog: dialogForAccepting,
                                           localizedTitle: NSLocalizedString("Accept", comment: "")),
            ]
            
        case .oneToOneInvitationSent:
            guard let dialogForAborting = try? obvDialog.cancellingOneToOneInvitationSent() else {
                assertionFailure()
                return []
            }
            return [
                .plainForRespondingToDialog(obvDialog: dialogForAborting,
                                            localizedTitle: NSLocalizedString("Abort", comment: ""),
                                            confirmationTitle: "ARE_YOU_SURE_YOU_WANT_TO_ABORT"),
            ]
            
        case .oneToOneInvitationReceived:
            guard let dialogForAccepting = try? obvDialog.settingResponseToOneToOneInvitationReceived(invitationAccepted: true),
                  let dialogForIgnoring = try? obvDialog.settingResponseToOneToOneInvitationReceived(invitationAccepted: false) else {
                assertionFailure()
                return []
            }
            return [
                .plainForRespondingToDialog(obvDialog: dialogForIgnoring, 
                                            localizedTitle: NSLocalizedString("Decline", comment: ""),
                                            confirmationTitle: "ARE_YOU_SURE_YOU_WANT_TO_DECLINE_THIS_INVITATION"),
                .blueForRespondingToDialog(obvDialog: dialogForAccepting,
                                           localizedTitle: NSLocalizedString("Accept", comment: "")),
            ]
            
        case .freezeGroupV2Invite:
            return [
                .plainForAbortingProtocol(obvDialog: obvDialog, localizedTitle: NSLocalizedString("Abort", comment: "")),
            ]
            
        case .syncRequestReceivedFromOtherOwnedDevice:
            assertionFailure("This category should never end up here")
            return []
            
        }
    }
    
    
    var groupMembers: [String] {
        assert(Thread.isMainThread)
        guard let obvDialog else { return [] }
        switch obvDialog.category {
        case .acceptGroupInvite(groupMembers: let groupMembers, groupOwner: _):
            return groupMembers
                .map({ $0.getDisplayNameWithStyle(.firstNameThenLastName) })
                .sorted()
        case .acceptGroupV2Invite(inviter: _, group: let group):
            guard let ownedCryptoId else { return [] }
            return group.otherMembers.map {
                if let memberContact = try? PersistedObvContactIdentity.get(contactCryptoId: $0.identity, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
                    return memberContact.customOrNormalDisplayName
                } else if let details = try? ObvIdentityCoreDetails($0.serializedIdentityCoreDetails) {
                    return details.getDisplayNameWithStyle(.firstNameThenLastName)
                } else {
                    assertionFailure()
                    return NSLocalizedString("UNKNOWN_GROUP_MEMBER_NAME", comment: "")
                }
            }
        default:
            return []
        }
    }
    
    
    var numberOfBadEnteredSas: Int {
        guard let obvDialog else { return 0 }
        switch obvDialog.category {
        case .sasExchange(contactIdentity: _, sasToDisplay: _, numberOfBadEnteredSas: let numberOfBadEnteredSas):
            return numberOfBadEnteredSas
        default:
            return 0
        }
    }


    var sasToExchange: (sasToShow: [Character], onSASInput: ((String) -> ObvDialog?)?)? {
        guard var obvDialog = self.obvDialog else { return nil }
        switch obvDialog.category {
        case .sasExchange(contactIdentity: _, sasToDisplay: let sasToDisplay, numberOfBadEnteredSas: _):
            guard let sasAsString = String(data: sasToDisplay, encoding: .utf8)?.trimmingWhitespacesAndNewlines(),
                  sasAsString.count == 4 else { assertionFailure(); return nil }
            let onSASInput: (String) -> ObvDialog? = { inputSAS in
                guard let data = inputSAS.data(using: .utf8) else { assertionFailure(); return nil }
                do {
                    try obvDialog.setResponseToSasExchange(otherSas: data)
                    return obvDialog
                } catch {
                    return nil
                }
            }
            return (sasAsString.map({ $0 }), onSASInput)
        case .sasConfirmed(contactIdentity: _, sasToDisplay: let sasToDisplay, sasEntered: _):
            guard let sasAsString = String(data: sasToDisplay, encoding: .utf8)?.trimmingWhitespacesAndNewlines(),
                  sasAsString.count == 4 else { assertionFailure(); return nil }
            return (sasAsString.map({ $0 }), nil)
        default:
            return nil
        }
    }
    
}
