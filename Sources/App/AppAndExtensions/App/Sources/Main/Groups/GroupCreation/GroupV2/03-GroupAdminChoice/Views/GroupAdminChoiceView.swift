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
import ObvUICoreData
import ObvDesignSystem
import ObvUIObvCircledInitials
import ObvUI


@MainActor
protocol GroupAdminChoiceViewModelProtocol: ObservableObject {
    associatedtype UserOrAdminCellViewModel: UserOrAdminCellViewModelProtocol
    var users: [UserOrAdminCellViewModel] { get }
}


protocol GroupAdminChoiceViewActionsProtocol: AnyObject {
    func userWantsToChangeUserAdminStatus(userCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool)
    func userConfirmedGroupAdminChoice() async
}


struct GroupAdminChoiceView<Model: GroupAdminChoiceViewModelProtocol>: View, UserOrAdminCellViewActionsProtocol {
    
    @ObservedObject var model: Model
    let actions: GroupAdminChoiceViewActionsProtocol
    let showButton: Bool
    @State private var everyoneIsAdmin: Bool
    
    init(model: Model, actions: GroupAdminChoiceViewActionsProtocol, showButton: Bool) {
        self.model = model
        self.actions = actions
        self.showButton = showButton
        self.everyoneIsAdmin = model.users.allSatisfy({ $0.isAdmin })
    }
    
    private func evaluateWhetherEveryoneIsAdmin() {
        self.everyoneIsAdmin = model.users.allSatisfy({ $0.isAdmin })
    }
    
    private func selectOrDeselectAll() {
        model.users.forEach { actions.userWantsToChangeUserAdminStatus(userCryptoId: $0.user.cryptoId, isAdmin: !everyoneIsAdmin) }
        evaluateWhetherEveryoneIsAdmin()
    }
    
    func userWantsToChangeUserAdminStatus(userCryptoId: ObvCryptoId, isAdmin: Bool) {
        actions.userWantsToChangeUserAdminStatus(userCryptoId: userCryptoId, isAdmin: isAdmin)
        evaluateWhetherEveryoneIsAdmin()
    }
    
    private func userConfirmedGroupAdminChoice() {
        Task { await actions.userConfirmedGroupAdminChoice() }
    }
        
    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {
            
            List {
                Section {
                    ForEach(model.users) { user in
                        UserOrAdminCellView(model: user, actions: self)
                    }
                } header: {
                    HStack {
                        Spacer(minLength: 0)
                        Button(everyoneIsAdmin ? "DESELECT_ALL" : "SELECT_ALL", action: selectOrDeselectAll)
                            .font(.footnote)
                    }
                }
            }
            
            if showButton {
                VStack {
                    OlvidButton(style: .blue, title: Text(CommonString.Word.Next), systemIcon: nil, action: userConfirmedGroupAdminChoice)
                        .padding()
                }.background(.ultraThinMaterial)
            }

        }
    }
}


protocol UserOrAdminCellViewModelProtocol: ObservableObject, Identifiable {
    associatedtype UserModel: UserWithCryptoIdCellViewModelProtocol
    var user: UserModel { get }
    var isAdmin: Bool { get }
}


@MainActor
protocol UserWithCryptoIdCellViewModelProtocol: SingleUserViewForVerticalUsersLayoutModelProtocol {
    var cryptoId: ObvCryptoId { get }
}


protocol UserOrAdminCellViewActionsProtocol {
    func userWantsToChangeUserAdminStatus(userCryptoId: ObvCryptoId, isAdmin: Bool)
}

private struct UserOrAdminCellView<Model: UserOrAdminCellViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: UserOrAdminCellViewActionsProtocol
    
    private var isAdmin: Binding<Bool>
  
    init(model: Model, actions: UserOrAdminCellViewActionsProtocol) {
        self.model = model
        self.actions = actions
        self.isAdmin = Binding<Bool>(get: { model.isAdmin }, set: { actions.userWantsToChangeUserAdminStatus(userCryptoId: model.user.cryptoId, isAdmin: $0) })
    }
    
    var body: some View {
        HStack {
            SingleUserViewForVerticalUsersLayout(model: model.user, state: .init(chevronStyle: .hidden, showDetailsStatus: false))
            Spacer()
            VStack(alignment: .trailing) {
                Toggle("", isOn: isAdmin)
                    .labelsHidden()
                Text(isAdmin.wrappedValue ? "IS_ADMIN" : "IS_NOT_ADMIN")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
    
}


// MARK: - PersistedUser implements UserWithCryptoIdCellViewModelProtocol

extension PersistedUser: UserWithCryptoIdCellViewModelProtocol {
    
    var userHasNoDevice: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.userHasNoDevice
        case .groupMember(groupMember: let groupMember):
            return groupMember.userHasNoDevice
        }
    }
    
    var atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.atLeastOneDeviceAllowsThisUserToReceiveMessages
        case .groupMember(groupMember: let groupMember):
            return groupMember.atLeastOneDeviceAllowsThisUserToReceiveMessages
        }
    }
}


extension PersistedObvContactIdentity: UserWithCryptoIdCellViewModelProtocol {
    
    var userHasNoDevice: Bool {
        self.contactHasNoDevice
    }
    
    var atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool {
        self.atLeastOneDeviceAllowsThisContactToReceiveMessages
    }
}

extension PersistedGroupV2Member: UserWithCryptoIdCellViewModelProtocol {

    var userHasNoDevice: Bool {
        return false
    }
    
    var atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool {
        return true
    }
    
}







// MARK: - Previews


struct GroupAdminChoiceView_Previews: PreviewProvider {
    
    @MainActor
    private final class ContactModelForPreviews: UserWithCryptoIdCellViewModelProtocol {

        let detailsStatus = UserCellViewTypes.UserDetailsStatus.noNewPublishedDetails
        let userHasNoDevice = false
        let isActive = true
        let atLeastOneDeviceAllowsThisUserToReceiveMessages = true
        let cryptoId: ObvCryptoId
        
        let customDisplayName: String?
        let firstName: String?
        let lastName: String?
        let displayedPosition: String?
        let displayedCompany: String?
        let circledInitialsConfiguration: ObvUIObvCircledInitials.CircledInitialsConfiguration
        
        init(customDisplayName: String?, firstName: String?, lastName: String?, displayedPosition: String?, displayedCompany: String?, circledInitialsConfiguration: ObvUIObvCircledInitials.CircledInitialsConfiguration, cryptoId: ObvCryptoId) {
            self.customDisplayName = customDisplayName
            self.firstName = firstName
            self.lastName = lastName
            self.displayedPosition = displayedPosition
            self.displayedCompany = displayedCompany
            self.circledInitialsConfiguration = circledInitialsConfiguration
            self.cryptoId = cryptoId
        }
        
    }
    
    
    private final class UserOrAdminCellViewModelForPreviews: UserOrAdminCellViewModelProtocol {

        let user: GroupAdminChoiceView_Previews.ContactModelForPreviews
        @Published var isAdmin: Bool

        init(user: GroupAdminChoiceView_Previews.ContactModelForPreviews, isAdmin: Bool) {
            self.user = user
            self.isAdmin = isAdmin
        }
        
    }
    
    
    private final class ModelForPreviews: GroupAdminChoiceViewModelProtocol, GroupAdminChoiceViewActionsProtocol {
                        
        let users: [UserOrAdminCellViewModelForPreviews]
        
        init(users: [UserOrAdminCellViewModelForPreviews]) {
            self.users = users
        }
        
        func userWantsToChangeUserAdminStatus(userCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) {
            guard let contact = users.first(where: { $0.user.cryptoId == userCryptoId }) else { return }
            contact.isAdmin = isAdmin
        }

        func userConfirmedGroupAdminChoice() async {}

    }
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHYAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAD5GDHskL0wOdRjeL9jqjk9VujoQz40aoF6ZQbemkUN8Bej7FwmFAf-Kxss1psnCavjIa6kpOHoeqQKID2SiQXckAAAAADkJlbnZlbnV0byAgKEAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHQAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAApiJHxXH73fq_IwsjQzNaAVqz-cUFq1Jt4FrLTMXihKIBP-dXlPyBZAib67ynX3vJOS5OepS3c0H_vBdIisycS8kAAAAADENoYXJsaWUgIChAKQ==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAH4AAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAF8M9oXsYUtToB6_DKjdSLb8xp149impOaE3Z_HoMJoMBTUZA4jgEiwg85Vd2kW8JxZe105_snQmZjMJyiGIDqH4AAAAAFkpvc2UgIChKYXZhIEFyY2hpdGVjdCk=")!
    ]
    
    private static let ownedCryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })
    
    private static let ownedCircledInitialsConfigurations = [
        CircledInitialsConfiguration.contact(initial: "A", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[0], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "B", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[1], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "C", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[2], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "D", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[3], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "E", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[4], tintAdjustementMode: .normal)
    ]

    private static let contactModelsForPreviews: [ContactModelForPreviews] = [
        .init(customDisplayName: nil,
              firstName: "Amaury",
              lastName: "Lanoy",
              displayedPosition: nil,
              displayedCompany: nil,
              circledInitialsConfiguration: ownedCircledInitialsConfigurations[0], 
              cryptoId: ownedCryptoIds[0]),
        .init(customDisplayName: "Bertrand Bechard",
              firstName: "Bertrand",
              lastName: nil,
              displayedPosition: "Head Developer",
              displayedCompany: nil,
              circledInitialsConfiguration: ownedCircledInitialsConfigurations[1],
              cryptoId: ownedCryptoIds[1]),
        .init(customDisplayName: "Christophe Chevron",
              firstName: "Christophe",
              lastName: "Chevron",
              displayedPosition: nil,
              displayedCompany: "Olvid",
              circledInitialsConfiguration: ownedCircledInitialsConfigurations[2],
              cryptoId: ownedCryptoIds[2]),
        .init(customDisplayName: nil,
              firstName: nil,
              lastName: "Danich",
              displayedPosition: "Head of Marketing",
              displayedCompany: "Olvid",
              circledInitialsConfiguration: ownedCircledInitialsConfigurations[3],
              cryptoId: ownedCryptoIds[3]),
        .init(customDisplayName: nil,
              firstName: "Éléonore",
              lastName: nil,
              displayedPosition: nil,
              displayedCompany: nil,
              circledInitialsConfiguration: ownedCircledInitialsConfigurations[4],
              cryptoId: ownedCryptoIds[4]),
    ]
    
    private static let userOrAdminCellViewModelsForPreviews: [UserOrAdminCellViewModelForPreviews] = [
        .init(user: contactModelsForPreviews[0], isAdmin: false),
        .init(user: contactModelsForPreviews[1], isAdmin: false),
        .init(user: contactModelsForPreviews[2], isAdmin: false),
        .init(user: contactModelsForPreviews[3], isAdmin: false),
        .init(user: contactModelsForPreviews[4], isAdmin: false),
    ]
    
    private static let modelForPreviews = ModelForPreviews(users: userOrAdminCellViewModelsForPreviews)

    static var previews: some View {
        GroupAdminChoiceView(model: modelForPreviews, actions: modelForPreviews, showButton: true)
    }
    
}
