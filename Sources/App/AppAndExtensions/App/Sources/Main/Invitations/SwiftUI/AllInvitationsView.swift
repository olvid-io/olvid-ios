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

import SwiftUI
import ObvTypes
import ObvSystemIcon
import ObvUI


/// Is expected to be implemented by ``PersistedObvOwnedIdentity``.
protocol AllInvitationsViewModelProtocol: ObservableObject {

    associatedtype InvitationViewModel: InvitationViewModelProtocol

    var sortedInvitations: [InvitationViewModel] { get }
    
}


protocol AllInvitationsViewActionsProtocol: AnyObject, InvitationViewActionsProtocol {}

struct AllInvitationsView<Model: AllInvitationsViewModelProtocol>: View {
    
    let actions: AllInvitationsViewActionsProtocol
    @ObservedObject var model: Model
    
    var contentView: some View {
        ScrollView {
            VStack {
                ForEach(model.sortedInvitations, id: \.invitationUUID) { invitation in
                    ObvCardView {
                        InvitationView(actions: actions, model: invitation)
                    }
                    .padding(.bottom)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    var contentViewWithContentMargin: some View {
        if #available(iOS 17.0, *) {
            contentView
                .contentMargins(.bottom, ObvMessengerConstants.contentInsetBottomWithFloatingButton)
        } else {
            contentView
        }
    }
    
    var body: some View {
        if !model.sortedInvitations.isEmpty {
            contentViewWithContentMargin
                .apply {
                    if #available(iOS 16.0, *) {
                        $0.scrollDismissesKeyboard(.interactively)
                    } else {
                        $0
                    }
                }
        } else {
            ObvContentUnavailableView("CONTENT_UNAVAILABLE_INVITATIONS_TEXT", systemIcon: .tray, description: Text("CONTENT_UNAVAILABLE_INVITATIONS_DESCRIPTION"))
        }
    }
}


// MARK: - Previews

struct AllInvitationsView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private static let otherCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private final class InvitationModelForPreviews: InvitationViewModelProtocol {
        
        private static let someDialog = ObvDialog(
            uuid: UUID(),
            encodedElements: 0.obvEncode(),
            ownedCryptoId: AllInvitationsView_Previews.ownedCryptoId,
            category: .acceptInvite(contactIdentity: .init(
                cryptoId: otherCryptoId,
                currentIdentityDetails: .init(coreDetails: try! .init(firstName: "Steve",
                                                                      lastName: "Jobs",
                                                                      company: nil,
                                                                      position: nil,
                                                                      signedUserDetails: nil),
                                              photoURL: nil))))
        
        let ownedCryptoId: ObvCryptoId? = AllInvitationsView_Previews.ownedCryptoId
        let title = "Invitation title"
        let subtitle = "Invitation subtitle"
        let body: String? = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam placerat dignissim nulla. Nullam sed felis nec purus maximus ultricies vitae non mauris. Maecenas quis volutpat lectus."
        let invitationUUID = UUID()
        var dismissDialog: ObvDialog? { Self.someDialog }
        var sasToExchange: (sasToShow: [Character], onSASInput: ((String) -> ObvTypes.ObvDialog?)?)? {
            return nil
        }

        var buttons: [InvitationViewButtonKind] {
            return []
        }
        
        var numberOfBadEnteredSas = 0
        
        var groupMembers: [String] {
            ["Steve Jobs"]
        }

        var showRedDot: Bool { true }

        var titleSystemIcon: SystemIcon? { return .person }

        var titleSystemIconColor: Color { Color(UIColor.systemPink) }

    }

    
    private final class ModelForPreviews: AllInvitationsViewModelProtocol {
        let sortedInvitations: [InvitationModelForPreviews] = [
            InvitationModelForPreviews(),
            InvitationModelForPreviews(),
        ]
    }
    
    private static let model = ModelForPreviews()
    
    final class ActionsForPreviews: AllInvitationsViewActionsProtocol {
        func userWantsToRespondToDialog(_ obvDialog: ObvDialog) {}
        func userWantsToAbortProtocol(associatedTo obvDialog: ObvDialog) async throws {}
        func userWantsToDeleteDialog(_ obvDialog: ObvDialog) async throws {}
        func userWantsToDiscussWithContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {}
    }

    private static let actions = ActionsForPreviews()

    static var previews: some View {
        AllInvitationsView(actions: actions, model: model)
    }
    
}
