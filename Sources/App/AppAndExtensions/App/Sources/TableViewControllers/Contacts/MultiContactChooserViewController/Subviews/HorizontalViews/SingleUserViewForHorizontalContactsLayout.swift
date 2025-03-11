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
import ObvUIObvCircledInitials
import ObvUI
import ObvTypes

protocol SingleUserViewForHorizontalUsersLayoutModelProtocol: ObservableObject, Hashable, InitialCircleViewNewModelProtocol, SingleContactTextViewModelProtocol {
    var cryptoId: ObvCryptoId { get }
}


protocol SingleUserViewForHorizontalUsersLayoutActionsProtocol {
    func userWantsToDeleteUser(cryptoId: ObvCryptoId) async
}

/// View shown during group creation. It is used in the horizontal scrolling list of selected users. It shows a circle with an initial, the name of the user, and, optionally, a button allowing to remove the user from the selection.
struct SingleUserViewForHorizontalContactsLayout<Model: SingleUserViewForHorizontalUsersLayoutModelProtocol>: View {
    
    @ObservedObject var model: Model
    
    var canEdit: Bool
    
    let actions: SingleUserViewForHorizontalUsersLayoutActionsProtocol?
    
    var body: some View {
        VStack(alignment: .center) {
            InitialCircleViewNew(model: model, state: .init(circleDiameter: 58))
                .overlay(alignment: .topTrailing) {
                    if let actions {
                        DeleteButton(model: model, actions: actions)
                            .offset(x: 16.0, y: -16.0)
                            .opacity(canEdit ? 1.0 : 0.0)
                    }
                }
            SingleContactTextView(model: model)
        }.frame(maxWidth: 80.0)
    }
}


private struct DeleteButton<Model: SingleUserViewForHorizontalUsersLayoutModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: SingleUserViewForHorizontalUsersLayoutActionsProtocol

    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(Color(.secondarySystemGroupedBackground))
                .frame(width: 20, height: 20)
            Image(systemIcon: .xmarkCircleFill)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white, Color(UIColor.systemGray))
        }
        .frame(width: 44, height: 44)
        .onTapGesture {
            Task {
                await actions.userWantsToDeleteUser(cryptoId: model.cryptoId)
            }
        }
    }
    
}


protocol SingleContactTextViewModelProtocol: ObservableObject {
    var firstName: String? { get }
    var lastName: String? { get }
}


private struct SingleContactTextView<Model: SingleContactTextViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    
    var body: some View {
        VStack(alignment: .center) {
            Text(model.firstName ?? " ")
                .lineLimit(1)
            Text(model.lastName ?? " ")
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}





// MARK: - Previews

struct SingleContactView_Previews: PreviewProvider {
    
    private final class User: SingleUserViewForHorizontalUsersLayoutModelProtocol {
        
        var cryptoId: ObvCryptoId
        
        
        let firstName: String?
        let lastName: String?
        let circledInitialsConfiguration: CircledInitialsConfiguration
        
        init(cryptoId: ObvCryptoId, firstName: String?, circledInitialsConfiguration: CircledInitialsConfiguration) {
            self.cryptoId = cryptoId
            self.firstName = firstName
            self.lastName = nil
            self.circledInitialsConfiguration = circledInitialsConfiguration
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(cryptoId)
        }
        
        static func == (lhs: SingleContactView_Previews.User, rhs: SingleContactView_Previews.User) -> Bool {
            lhs.cryptoId == rhs.cryptoId
        }

    }
    
    private final class Actions: SingleUserViewForHorizontalUsersLayoutActionsProtocol {
        func userWantsToDeleteUser(cryptoId: ObvTypes.ObvCryptoId) async {}
    }
    
    
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    
    private static let cryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId
    
    static var previews: some View {
        Group {
            SingleUserViewForHorizontalContactsLayout(
                model: User(cryptoId: cryptoId,
                            firstName: "Jean-Baptiste",
                            circledInitialsConfiguration: .contact(
                                initial: "M",
                                photo: nil,
                                showGreenShield: false,
                                showRedShield: false,
                                cryptoId: cryptoId,
                                tintAdjustementMode: .normal)
                           ),
                canEdit: true,
                actions: Actions())
            .previewLayout(.sizeThatFits)
            .padding()
        }
    }
}
