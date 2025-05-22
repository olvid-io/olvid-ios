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
import ObvTypes
import ObvCrypto
import ObvCircleAndTitlesView


struct PreviewsHelper {
    
    static let cryptoIds: [ObvCryptoId] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]
    
    static let coreDetails: [ObvIdentityCoreDetails] = [
        try! ObvIdentityCoreDetails(firstName: "Giggles",
                                    lastName: "McFluffernut",
                                    company: "Fluff Inc.",
                                    position: "Chief Plush Development Officer",
                                    signedUserDetails: nil),
        try! ObvIdentityCoreDetails(firstName: "Bubbles",
                                    lastName: "Snicklefritz",
                                    company: "Splashy SeaWorld",
                                    position: "Marine Animal Communications Manager with a long title",
                                    signedUserDetails: nil),
        try! ObvIdentityCoreDetails(firstName: "Lollipop",
                                    lastName: "Wigglesworth",
                                    company: "Sweet Tooth Candy Co.",
                                    position: "Colorful Dessert Specialist",
                                    signedUserDetails: nil),
        try! ObvIdentityCoreDetails(firstName: "Tickles",
                                    lastName: "McBubbles With a very long last name",
                                    company: nil,
                                    position: nil,
                                    signedUserDetails: nil),
    ]

    static let serverURL = URL(string: "https://dev.olvid.io")!
    
    static let obvGroupV2Identifiers: [ObvGroupV2Identifier] = [
        ObvGroupV2Identifier(ownedCryptoId: cryptoIds[0], identifier: ObvGroupV2.Identifier(groupUID: UID.zero, serverURL: serverURL, category: .server))
    ]
    
    static let contactIdentifiers: [ObvContactIdentifier] = [
        .init(contactCryptoId: cryptoIds[1],
              ownedCryptoId: cryptoIds[0]),
        .init(contactCryptoId: cryptoIds[2],
              ownedCryptoId: cryptoIds[0]),
        .init(contactCryptoId: cryptoIds[3],
              ownedCryptoId: cryptoIds[0]),
    ]
    
    @MainActor
    static var profilePictureForURL: [URL: UIImage] = [
        photoURL[0]: UIImage(named: "avatar00", in: ObvUIGroupV2Resources.bundle, compatibleWith: nil)!,
        photoURL[1]: UIImage(named: "avatar01", in: ObvUIGroupV2Resources.bundle, compatibleWith: nil)!,
        photoURL[2]: UIImage(named: "avatar02", in: ObvUIGroupV2Resources.bundle, compatibleWith: nil)!,
    ]
    
    @MainActor
    static var groupPictureForURL: [URL: UIImage] = [
        photoURL[0]: UIImage(named: "group00", in: ObvUIGroupV2Resources.bundle, compatibleWith: nil)!,
        photoURL[1]: UIImage(named: "group01", in: ObvUIGroupV2Resources.bundle, compatibleWith: nil)!,
        photoURL[2]: UIImage(named: "group02", in: ObvUIGroupV2Resources.bundle, compatibleWith: nil)!,
    ]

    @MainActor static let photoURL: [URL] = [
        URL(string: "https://dev.olvid.io/avatar00")!,
        URL(string: "https://dev.olvid.io/avatar01")!,
        URL(string: "https://dev.olvid.io/avatar02")!,
    ]
    
    fileprivate static let allPermissions = Set(ObvGroupV2.Permission.allCases)
    private static let allPermissionsButAdmin = {
        var allPermissions = Set(ObvGroupV2.Permission.allCases)
        allPermissions.remove(.groupAdmin)
        return allPermissions
    }()
    
    @MainActor
    static let groupMembers: [SingleGroupMemberViewModel] = [
        .init(contactIdentifier: contactIdentifiers[0],
              permissions: allPermissions,
              isKeycloakManaged: false,
              profilePictureInitial: "A",
              circleColors: .init(background: .blue, foreground: .red),
              identityDetails: .init(coreDetails: coreDetails[0], photoURL: photoURL[0]),
              isOneToOneContact: .yes,
              isRevokedAsCompromised: false,
              isPending: false,
              detailedProfileCanBeShown: true,
              customDisplayName: "CustomDisplayName",
              customPhotoURL: nil),
        .init(contactIdentifier: contactIdentifiers[1],
              permissions: allPermissionsButAdmin,
              isKeycloakManaged: true,
              profilePictureInitial: "B",
              circleColors: .init(background: .green, foreground: .cyan),
              identityDetails: .init(coreDetails: coreDetails[1], photoURL: photoURL[1]),
              isOneToOneContact: .yes,
              isRevokedAsCompromised: false,
              isPending: false,
              detailedProfileCanBeShown: true,
              customDisplayName: nil,
              customPhotoURL: nil),
        .init(contactIdentifier: contactIdentifiers[2],
              permissions: allPermissions,
              isKeycloakManaged: false,
              profilePictureInitial: "C",
              circleColors: .init(background: .yellow, foreground: .systemPink),
              identityDetails: .init(coreDetails: coreDetails[2], photoURL: photoURL[2]),
              isOneToOneContact: .no(canSendOneToOneInvitation: true),
              isRevokedAsCompromised: false,
              isPending: true,
              detailedProfileCanBeShown: false,
              customDisplayName: nil,
              customPhotoURL: nil),

    ]
 
    
    @MainActor
    static let singleGroupV2MainViewModels: [SingleGroupV2MainViewModel] = [
        .init(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
              trustedName: "The group trusted name",
              trustedDescription: "The group trusted description",
              trustedPhotoURL: PreviewsHelper.photoURL[0],
              customPhotoURL: nil,
              nickname: nil,
              isKeycloakManaged: false,
              circleColors: InitialCircleView.Model.Colors(background: .red, foreground: .blue),
              updateInProgress: false,
              ownedIdentityIsAdmin: true,
              ownedIdentityCanLeaveGroup: .canLeaveGroup,
              publishedDetailsForValidation: .init(
                groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                publishedName: "The published name",
                publishedDescription: "The published description",
                publishedPhotoURL: PreviewsHelper.photoURL[1],
                circleColors: InitialCircleView.Model.Colors(background: .cyan, foreground: .systemPink),
                differences: [.name, .description, .photo],
                isKeycloakManaged: false),
              personalNote: "A personal note",
              groupType: .advanced(isReadOnly: true, remoteDeleteAnythingPolicy: .everyone))
    ]

    
    @MainActor
    static let allUserIdentifiers: [SelectUsersToAddViewModel.User.Identifier] = {
        contactIdentifiers.map({ .contactIdentifier(contactIdentifier: $0) })
    }()
    
    
    @MainActor
    static let selectUsersToAddViewModel: SelectUsersToAddViewModel = {
        .init(textOnEmptySetOfUsers: "Please choose who to add to this group.",
              allUserIdentifiers: allUserIdentifiers)
    }()
    
    @MainActor
    static let selectUsersToAddViewModelUser: [SelectUsersToAddViewModel.User] = [
        SelectUsersToAddViewModel.User(identifier: .contactIdentifier(contactIdentifier: contactIdentifiers[0]),
                                       isKeycloakManaged: false,
                                       profilePictureInitial: "A",
                                       circleColors: .init(background: .blue, foreground: .red),
                                       identityDetails: .init(coreDetails: coreDetails[0], photoURL: photoURL[0]),
                                       isRevokedAsCompromised: false,
                                       customDisplayName: "CustomDisplayName",
                                       customPhotoURL: nil),
        SelectUsersToAddViewModel.User(identifier: .contactIdentifier(contactIdentifier: contactIdentifiers[1]),
                                       isKeycloakManaged: true,
                                       profilePictureInitial: "B",
                                       circleColors: .init(background: .green, foreground: .cyan),
                                       identityDetails: .init(coreDetails: coreDetails[1], photoURL: photoURL[1]),
                                       isRevokedAsCompromised: false,
                                       customDisplayName: nil,
                                       customPhotoURL: nil),
        SelectUsersToAddViewModel.User(identifier: .contactIdentifier(contactIdentifier: contactIdentifiers[2]),
                                       isKeycloakManaged: false,
                                       profilePictureInitial: "C",
                                       circleColors: .init(background: .yellow, foreground: .systemPink),
                                       identityDetails: .init(coreDetails: coreDetails[2], photoURL: photoURL[2]),
                                       isRevokedAsCompromised: false,
                                       customDisplayName: nil,
                                       customPhotoURL: nil),
    ]

    @MainActor
    static let onetoOneInvitableGroupMembersViewModelIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier] = [
        .contactIdentifier(contactIdentifier: contactIdentifiers[0]),
        .contactIdentifier(contactIdentifier: contactIdentifiers[1]),
        .contactIdentifier(contactIdentifier: contactIdentifiers[2]),
    ]
    
    @MainActor
    static let onetoOneInvitableGroupMembersViewModels: [OnetoOneInvitableGroupMembersViewModel] = [
        OnetoOneInvitableGroupMembersViewModel(
            invitableGroupMembers: [onetoOneInvitableGroupMembersViewModelIdentifiers[0]],
            notInvitableGroupMembers: [onetoOneInvitableGroupMembersViewModelIdentifiers[1]],
            oneToOneContactsAmongMembers: [onetoOneInvitableGroupMembersViewModelIdentifiers[2]]),
        OnetoOneInvitableGroupMembersViewModel(
            invitableGroupMembers: [onetoOneInvitableGroupMembersViewModelIdentifiers[0],
                                    onetoOneInvitableGroupMembersViewModelIdentifiers[1]],
            notInvitableGroupMembers: [],
            oneToOneContactsAmongMembers: [onetoOneInvitableGroupMembersViewModelIdentifiers[2]]),
    ]
    
    @MainActor
    static let onetoOneInvitableGroupMembersViewCellModel: [ObvContactIdentifier : OnetoOneInvitableGroupMembersViewCellModel] = [
        contactIdentifiers[0]: .init(contactIdentifier: contactIdentifiers[0],
                                     isKeycloakManaged: false,
                                     profilePictureInitial: "A",
                                     circleColors: .init(background: .blue, foreground: .red),
                                     identityDetails: .init(coreDetails: coreDetails[0], photoURL: photoURL[0]),
                                     kind: .invitableGroupMembers(invitationSentAlready: false),
                                     isRevokedAsCompromised: false,
                                     detailedProfileCanBeShown: true,
                                     customDisplayName: nil,
                                     customPhotoURL: nil),
        contactIdentifiers[1]: .init(contactIdentifier: contactIdentifiers[1],
                                     isKeycloakManaged: false,
                                     profilePictureInitial: "B",
                                     circleColors: .init(background: .green, foreground: .cyan),
                                     identityDetails: .init(coreDetails: coreDetails[1], photoURL: photoURL[1]),
                                     kind: .invitableGroupMembers(invitationSentAlready: true),
                                     isRevokedAsCompromised: false,
                                     detailedProfileCanBeShown: true,
                                     customDisplayName: nil,
                                     customPhotoURL: nil),
        contactIdentifiers[2]: .init(contactIdentifier: contactIdentifiers[2],
                                     isKeycloakManaged: false,
                                     profilePictureInitial: "C",
                                     circleColors: .init(background: .yellow, foreground: .systemPink),
                                     identityDetails: .init(coreDetails: coreDetails[2], photoURL: photoURL[2]),
                                     kind: .notInvitableGroupMembers,
                                     isRevokedAsCompromised: false,
                                     detailedProfileCanBeShown: true,
                                     customDisplayName: nil,
                                     customPhotoURL: nil),
    ]
    
}


extension OwnedIdentityAsGroupMemberViewModel {
    
    @MainActor
    static var sampleData: OwnedIdentityAsGroupMemberViewModel {
        .init(ownedCryptoId: PreviewsHelper.cryptoIds[0],
              isKeycloakManaged: false,
              profilePictureInitial: "A",
              circleColors: .init(background: .blue, foreground: .red),
              identityDetails: .init(coreDetails: PreviewsHelper.coreDetails[0], photoURL: PreviewsHelper.photoURL[0]),
              permissions: PreviewsHelper.allPermissions,
              customDisplayName: nil,
              customPhotoURL: nil)
    }
    
}
