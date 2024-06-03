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
import UI_ObvCircledInitials


protocol GroupAdminChoiceViewModelProtocol: ObservableObject {
    associatedtype ContactOrAdminCellViewModel: ContactOrAdminCellViewModelProtocol
    var contacts: [ContactOrAdminCellViewModel] { get }
}


protocol GroupAdminChoiceViewActionsProtocol: AnyObject {
    func userWantsToChangeContactAdminStatus(contactCryptoId: ObvCryptoId, isAdmin: Bool)
    func userConfirmedGroupAdminChoice() async
}


struct GroupAdminChoiceView<Model: GroupAdminChoiceViewModelProtocol>: View, ContactOrAdminCellViewActionsProtocol {
    
    @ObservedObject var model: Model
    let actions: GroupAdminChoiceViewActionsProtocol
    let showButton: Bool
    @State private var everyoneIsAdmin: Bool
    
    init(model: Model, actions: GroupAdminChoiceViewActionsProtocol, showButton: Bool) {
        self.model = model
        self.actions = actions
        self.showButton = showButton
        self.everyoneIsAdmin = model.contacts.allSatisfy({ $0.isAdmin })
    }
    
    private func evaluateWhetherEveryoneIsAdmin() {
        self.everyoneIsAdmin = model.contacts.allSatisfy({ $0.isAdmin })
    }
    
    private func selectOrDeselectAll() {
        model.contacts.forEach { actions.userWantsToChangeContactAdminStatus(contactCryptoId: $0.contact.cryptoId, isAdmin: !everyoneIsAdmin) }
        evaluateWhetherEveryoneIsAdmin()
    }
    
    func userWantsToChangeContactAdminStatus(contactCryptoId: ObvCryptoId, isAdmin: Bool) {
        actions.userWantsToChangeContactAdminStatus(contactCryptoId: contactCryptoId, isAdmin: isAdmin)
        evaluateWhetherEveryoneIsAdmin()
    }
    
    private func userConfirmedGroupAdminChoice() {
        Task { await actions.userConfirmedGroupAdminChoice() }
    }
        
    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {
            
            List {
                Section {
                    ForEach(model.contacts) { contact in
                        ContactOrAdminCellView(model: contact, actions: self)
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


protocol ContactOrAdminCellViewModelProtocol: ObservableObject, Identifiable {
    associatedtype ContactModel: ContactWithCryptoIdCellViewModelProtocol
    var contact: ContactModel { get }
    var isAdmin: Bool { get }
}


protocol ContactWithCryptoIdCellViewModelProtocol: ContactCellViewModelProtocol {
    var cryptoId: ObvCryptoId { get }
}


protocol ContactOrAdminCellViewActionsProtocol {
    func userWantsToChangeContactAdminStatus(contactCryptoId: ObvCryptoId, isAdmin: Bool)
}

private struct ContactOrAdminCellView<Model: ContactOrAdminCellViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: ContactOrAdminCellViewActionsProtocol
    
    private var isAdmin: Binding<Bool>
  
    init(model: Model, actions: ContactOrAdminCellViewActionsProtocol) {
        self.model = model
        self.actions = actions
        self.isAdmin = Binding<Bool>(get: { model.isAdmin }, set: { actions.userWantsToChangeContactAdminStatus(contactCryptoId: model.contact.cryptoId, isAdmin: $0) })
    }
    
    var body: some View {
        HStack {
            ContactCellView(model: model.contact, state: .init(chevronStyle: .hidden, showDetailsStatus: false))
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


extension PersistedObvContactIdentity: ContactWithCryptoIdCellViewModelProtocol {}









// MARK: - Previews


struct GroupAdminChoiceView_Previews: PreviewProvider {
    
    private final class ContactModelForPreviews: ContactWithCryptoIdCellViewModelProtocol {

        let detailsStatus = ContactCellViewTypes.ContactDetailsStatus.noNewPublishedDetails
        let contactHasNoDevice = false
        let isActive = true
        let atLeastOneDeviceAllowsThisContactToReceiveMessages = true
        let cryptoId: ObvCryptoId
        
        let customDisplayName: String?
        let firstName: String?
        let lastName: String?
        let displayedPosition: String?
        let displayedCompany: String?
        let circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration
        
        init(customDisplayName: String?, firstName: String?, lastName: String?, displayedPosition: String?, displayedCompany: String?, circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration, cryptoId: ObvCryptoId) {
            self.customDisplayName = customDisplayName
            self.firstName = firstName
            self.lastName = lastName
            self.displayedPosition = displayedPosition
            self.displayedCompany = displayedCompany
            self.circledInitialsConfiguration = circledInitialsConfiguration
            self.cryptoId = cryptoId
        }
        
    }
    
    
    private final class ContactOrAdminCellViewModelForPreviews: ContactOrAdminCellViewModelProtocol {

        let contact: GroupAdminChoiceView_Previews.ContactModelForPreviews
        @Published var isAdmin: Bool

        init(contact: GroupAdminChoiceView_Previews.ContactModelForPreviews, isAdmin: Bool) {
            self.contact = contact
            self.isAdmin = isAdmin
        }
        
    }
    
    
    private final class ModelForPreviews: GroupAdminChoiceViewModelProtocol, GroupAdminChoiceViewActionsProtocol {
                        
        let contacts: [ContactOrAdminCellViewModelForPreviews]
        
        init(contacts: [ContactOrAdminCellViewModelForPreviews]) {
            self.contacts = contacts
        }
        
        func userWantsToChangeContactAdminStatus(contactCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) {
            guard let contact = contacts.first(where: { $0.contact.cryptoId == contactCryptoId }) else { return }
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
    
    private static let contactOrAdminCellViewModelsForPreviews: [ContactOrAdminCellViewModelForPreviews] = [
        .init(contact: contactModelsForPreviews[0], isAdmin: false),
        .init(contact: contactModelsForPreviews[1], isAdmin: false),
        .init(contact: contactModelsForPreviews[2], isAdmin: false),
        .init(contact: contactModelsForPreviews[3], isAdmin: false),
        .init(contact: contactModelsForPreviews[4], isAdmin: false),
    ]
    
    private static let modelForPreviews = ModelForPreviews(contacts: contactOrAdminCellViewModelsForPreviews)

    static var previews: some View {
        GroupAdminChoiceView(model: modelForPreviews, actions: modelForPreviews, showButton: true)
    }
    
}
