/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvDesignSystem

@MainActor
public protocol OwnedIdentityChooserViewActions {
    func userDidConfirmOwnedCryptoIdSelection(_ view: OwnedIdentityChooserView, selectedOwnedCryptoId: ObvCryptoId)
}


/// View allowing to choose a profile. It is intended to be used in an existing SwiftUI navigation stack.
public struct OwnedIdentityChooserView: View {
    
    private let currentOwnedCryptoId: ObvCryptoId
    private let configuration: Configuration
    private let dataSources: DataSources
    private let actions: OwnedIdentityChooserViewActions

    public init(currentOwnedCryptoId: ObvCryptoId,
                configuration: Configuration,
                dataSources: DataSources,
                actions: OwnedIdentityChooserViewActions) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.configuration = configuration
        self.dataSources = dataSources
        self.actions = actions
    }
    
    public struct Configuration {
        let explanation: String?
        let title: String
        public init(explanation: String?, title: String) {
            self.explanation = explanation
            self.title = title
        }
    }
    
    public struct DataSources {
        let ownedIdentityChooserViewDataSource: any OwnedIdentityChooserViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        public init(ownedIdentityChooserViewDataSource: any OwnedIdentityChooserViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.ownedIdentityChooserViewDataSource = ownedIdentityChooserViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }
    
    @State private var ownedCryptoIdTappedByUser: ObvCryptoId?

    public var body: some View {
        OwnedIdentityChooserInnerView(
            currentOwnedCryptoId: currentOwnedCryptoId,
            actions: self,
            configuration: .init(mode: .selectProfile,
                                 explanation: configuration.explanation,
                                 title: configuration.title),
            dataSource: dataSources.ownedIdentityChooserViewDataSource,
            avatarViewDataSource: dataSources.avatarViewDataSource,
            ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
}


extension OwnedIdentityChooserView: OwnedIdentityChooserInnerViewActionsProtocol {
    
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        assertionFailure("Unexpected call in the .selectProfile mode")
    }
    
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserInnerView) async {
        assertionFailure("Unexpected call in the .selectProfile mode")
    }
    
    func userDidConfirmOwnedCryptoIdSelection(_ view: OwnedIdentityChooserInnerView, selectedOwnedCryptoId: ObvTypes.ObvCryptoId) {
        actions.userDidConfirmOwnedCryptoIdSelection(self, selectedOwnedCryptoId: selectedOwnedCryptoId)
    }
    
}
