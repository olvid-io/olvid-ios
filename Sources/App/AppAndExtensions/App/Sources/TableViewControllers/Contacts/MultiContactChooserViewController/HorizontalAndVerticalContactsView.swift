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

import SwiftUI
import ObvTypes
import ObvSystemIcon
import ObvUI
import ObvDesignSystem


protocol HorizontalAndVerticalUsersViewModelProtocol: ObservableObject, HorizontalUsersViewModelProtocol, VerticalUsersViewModelProtocol {
    
}


protocol HorizontalAndVerticalUsersViewActionsProtocol: SingleUserViewForHorizontalUsersLayoutActionsProtocol, VerticalUsersViewActionsProtocol {}


protocol HorizontalAndVerticalUsersViewConfigurationProtocol {
    var horizontalConfiguration: HorizontalUsersViewConfigurationProtocol? { get }
    var verticalConfiguration: VerticalUsersViewConfigurationProtocol { get }
    var buttonConfiguration: HorizontalAndVerticalUsersViewButtonConfigurationProtocol? { get }
}


protocol HorizontalAndVerticalUsersViewButtonConfigurationProtocol {
    var title: String { get }
    var systemIcon: SystemIcon { get }
    var action: (Set<ObvCryptoId>) -> Void { get }
    var allowEmptySetOfContacts: Bool { get }
}

struct HorizontalAndVerticalUsersView<Model: HorizontalAndVerticalUsersViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: HorizontalAndVerticalUsersViewActionsProtocol
    let configuration: HorizontalAndVerticalUsersViewConfigurationProtocol
    
    @State private var buttonTapped = false
    
    private func buttonAction() {
        guard let buttonConfiguration = configuration.buttonConfiguration else { assertionFailure(); return }
        buttonTapped = true
        let cryptoIdsOfSelectedUsers = Set(model.selectedUsers.map({ $0.cryptoId }))
        buttonConfiguration.action(cryptoIdsOfSelectedUsers)
    }
    
    private var disableButtonOnEmptySetOfContacts: Bool {
        guard let buttonConfiguration = configuration.buttonConfiguration else { return true }
        if buttonConfiguration.allowEmptySetOfContacts {
            return false
        } else {
            return model.selectedUsers.isEmpty
        }
    }
    
    var body: some View {
        
        VStack(spacing: 0) {
            
            if let horizontalConfiguration = configuration.horizontalConfiguration {
                
                HorizontalUsersView(model: model, configuration: horizontalConfiguration, actions: actions)
                    .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 0.0, trailing: 20.0))
                    .padding(.bottom)
                    .background(Color(UIColor.systemGroupedBackground))
                
            }
            
            VerticalUsersView(model: model,
                              actions: actions,
                              configuration: configuration.verticalConfiguration)
            
            if let buttonConfiguration = configuration.buttonConfiguration {
                OlvidButton(style: .blue,
                            title: Text(buttonConfiguration.title),
                            systemIcon: buttonConfiguration.systemIcon,
                            action: buttonAction)
                .disabled(buttonTapped || disableButtonOnEmptySetOfContacts)
                .padding()
                .background(.ultraThinMaterial)
            }

        }
        // The following line breaks the whole UI (the navigation and the tabbar become transparent)
        //.background(Color(UIColor.systemGroupedBackground), ignoresSafeAreaEdges: .all)
        .onAppear {
            buttonTapped = false
        }
    }

}
