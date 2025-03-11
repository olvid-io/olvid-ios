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

import Foundation
import CoreData
import SwiftUI
import ObvUIObvCircledInitials
import ObvUI
import ObvTypes


/// Expected to be implemented by `PersistedUser` (and thus by `PersistedObvContactIdentity` and `PersistedGroupV2Member`)
protocol ManagedUserViewForVerticalUsersLayoutModelProtocol: Equatable, Hashable, SingleUserViewForVerticalUsersLayoutModelProtocol {
    var cryptoId: ObvCryptoId { get }
}


protocol SingleUserViewForVerticalUsersLayoutModelProtocol: ObservableObject, SpinnerViewForUserCellModelProtocol, UserTextViewModelProtocol, InitialCircleViewNewModelProtocol {
    var detailsStatus: UserCellViewTypes.UserDetailsStatus { get }
}


struct UserCellViewTypes {
    
    enum UserDetailsStatus {
        case wasNotRecentlyOnline
        case noNewPublishedDetails
        case unseenPublishedDetails
        case seenPublishedDetails
    }
    
}


struct SingleUserViewForVerticalUsersLayout<Model: SingleUserViewForVerticalUsersLayoutModelProtocol>: View {
    
    @ObservedObject var model: Model
    let state: State
    
    struct State {
    
        let chevronStyle: ChevronStyle
        let showDetailsStatus: Bool

        enum ChevronStyle {
            case hidden
            case shown(selected: Bool)
        }

    }
    

    var body: some View {
        HStack {
            HStack(alignment: .center, spacing: 16) {
                InitialCircleViewNew(model: model, state: .init(circleDiameter: 60))
                ContactTextView(model: model)
            }

            Spacer()
            
            SpinnerViewForContactCell(model: model)
            
            if state.showDetailsStatus {
                switch model.detailsStatus {
                case .noNewPublishedDetails:
                    EmptyView()
                case .wasNotRecentlyOnline:
                    Image(systemIcon: .zzz)
                        .foregroundColor(.secondary)
                case .unseenPublishedDetails:
                    Image(systemIcon: .personCropRectangle)
                        .foregroundColor(.red)
                case .seenPublishedDetails:
                    Image(systemIcon: .personCropRectangle)
                        .foregroundColor(.secondary)
                }
            }
                        
            switch state.chevronStyle {
            case .hidden:
                EmptyView()
            case .shown(selected: let selected):
                ObvChevron(selected: selected)
            }
            
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
    }
    
}


protocol UserTextViewModelProtocol: ObservableObject {
    
    var customDisplayName: String? { get }
    var firstName: String? { get }
    var lastName: String? { get }
    var displayedPosition: String? { get }
    var displayedCompany: String? { get }

}


fileprivate struct ContactTextView<Model: UserTextViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    
    var body: some View {
        TextView(model: .init(
            titlePart1: model.customDisplayName == nil ? model.firstName : nil,
            titlePart2: model.customDisplayName ?? model.lastName,
            subtitle: model.displayedPosition,
            subsubtitle: model.displayedCompany))
    }
    
}







struct ContactCellView_Previews: PreviewProvider {
    
    private final class Contact: SingleUserViewForVerticalUsersLayoutModelProtocol {
                
        let isActive: Bool
        let userHasNoDevice: Bool
        let atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool
        let detailsStatus: UserCellViewTypes.UserDetailsStatus
        let customDisplayName: String?
        let firstName: String?
        let lastName: String?
        let displayedPosition: String?
        let displayedCompany: String?
        let circledInitialsConfiguration: CircledInitialsConfiguration


        init(detailsStatus: UserCellViewTypes.UserDetailsStatus, contactIsActive: Bool, userHasNoDevice: Bool, atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool, customDisplayName: String?, firstName: String?, lastName: String?, displayedPosition: String?, displayedCompany: String?, circledInitialsConfiguration: CircledInitialsConfiguration) {
            self.detailsStatus = detailsStatus
            self.isActive = contactIsActive
            self.userHasNoDevice = userHasNoDevice
            self.atLeastOneDeviceAllowsThisUserToReceiveMessages = atLeastOneDeviceAllowsThisUserToReceiveMessages
            self.customDisplayName = customDisplayName
            self.firstName = firstName
            self.lastName = lastName
            self.displayedPosition = displayedPosition
            self.displayedCompany = displayedCompany
            self.circledInitialsConfiguration = circledInitialsConfiguration
        }
        
    }
        
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    private static let cryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId

    static var previews: some View {
        Group {
            SingleUserViewForVerticalUsersLayout(
                model: Contact(
                    detailsStatus: .noNewPublishedDetails,
                    contactIsActive: true,
                    userHasNoDevice: false,
                    atLeastOneDeviceAllowsThisUserToReceiveMessages: true,
                    customDisplayName: nil,
                    firstName: "Alice",
                    lastName: "Spring",
                    displayedPosition: "CEO",
                    displayedCompany: "MyCo",
                    circledInitialsConfiguration: .contact(
                        initial: "S",
                        photo: nil,
                        showGreenShield: false,
                        showRedShield: false,
                        cryptoId: cryptoId,
                        tintAdjustementMode: .normal)),
                state: .init(
                    chevronStyle: .hidden,
                    showDetailsStatus: true))
            .previewLayout(.sizeThatFits)
            .padding()
        }
    }
    
}
