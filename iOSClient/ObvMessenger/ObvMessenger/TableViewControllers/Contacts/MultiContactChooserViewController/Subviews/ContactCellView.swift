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
import UI_ObvCircledInitials
import ObvUI
import ObvTypes


protocol ContactCellViewModelProtocol: ObservableObject, SpinnerViewForContactCellModelProtocol, ContactTextViewModelProtocol, InitialCircleViewNewModelProtocol {
    
    var detailsStatus: ContactCellViewTypes.ContactDetailsStatus { get }
    
}


struct ContactCellViewTypes {
    
    enum ContactDetailsStatus {
        case wasNotRecentlyOnline
        case noNewPublishedDetails
        case unseenPublishedDetails
        case seenPublishedDetails
    }
    
}


struct ContactCellView<Model: ContactCellViewModelProtocol>: View {
    
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


protocol ContactTextViewModelProtocol: ObservableObject {
    
    var customDisplayName: String? { get }
    var firstName: String? { get }
    var lastName: String? { get }
    var displayedPosition: String? { get }
    var displayedCompany: String? { get }

}


fileprivate struct ContactTextView<Model: ContactTextViewModelProtocol>: View {
    
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
    
    private final class Contact: ContactCellViewModelProtocol {
                
        let isActive: Bool
        let contactHasNoDevice: Bool
        let atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool
        let detailsStatus: ContactCellViewTypes.ContactDetailsStatus
        let customDisplayName: String?
        let firstName: String?
        let lastName: String?
        let displayedPosition: String?
        let displayedCompany: String?
        let circledInitialsConfiguration: CircledInitialsConfiguration


        init(detailsStatus: ContactCellViewTypes.ContactDetailsStatus, contactIsActive: Bool, contactHasNoDevice: Bool, atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool, customDisplayName: String?, firstName: String?, lastName: String?, displayedPosition: String?, displayedCompany: String?, circledInitialsConfiguration: CircledInitialsConfiguration) {
            self.detailsStatus = detailsStatus
            self.isActive = contactIsActive
            self.contactHasNoDevice = contactHasNoDevice
            self.atLeastOneDeviceAllowsThisContactToReceiveMessages = atLeastOneDeviceAllowsThisContactToReceiveMessages
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
            ContactCellView(
                model: Contact(
                    detailsStatus: .noNewPublishedDetails,
                    contactIsActive: true,
                    contactHasNoDevice: false,
                    atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
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
