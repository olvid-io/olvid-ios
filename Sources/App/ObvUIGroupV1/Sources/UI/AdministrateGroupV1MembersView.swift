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
import ObvDesignSystem
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes

@MainActor
protocol AdministrateGroupV1MembersViewDataSource {
    func getAsyncSequenceOfAdministrateGroupV1MembersViewModel(_ view: AdministrateGroupV1MembersView) throws -> (streamUUID: UUID, stream: AsyncStream<AdministrateGroupV1MembersView.Model>)
    func finishAsyncSequenceOfAdministrateGroupV1MembersViewModel(streamUUID: UUID)
}


public struct AdministrateGroupV1MembersView: View {

    let groupIdentifier: ObvGroupV1Identifier
    let dataSource: any AdministrateGroupV1MembersViewDataSource
    
    public struct Model: Sendable, Equatable {
        let updateInProgressDuringGroupEdition: Bool
    }

    @State private var streamedModel: Model?
    
    @State private var hudCategory: HUDView.Category? = nil
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try dataSource.getAsyncSequenceOfAdministrateGroupV1MembersViewModel(self)
            for await model in stream {
                if self.streamedModel == nil {
                    self.streamedModel = model
                } else {
                    withAnimation {
                        self.streamedModel = model
                    }
                }
            }
            dataSource.finishAsyncSequenceOfAdministrateGroupV1MembersViewModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    public var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            if let streamedModel {
                InternalView(groupIdentifier: groupIdentifier,
                             model: streamedModel)
            } else {
                ObvCenteredProgressView()
            }
            if let hudCategory = self.hudCategory {
                HUDView(category: hudCategory)
            }
        }
        .navigationTitle(String(localizedInThisBundle: "TITLE_MANAGE_GROUP_MEMBERS"))
        .navigationBarTitleDisplayMode(.inline)
        .task(onTask)
    }
    
}


extension AdministrateGroupV1MembersView {
    struct InternalView: View {
        
        let groupIdentifier: ObvGroupV1Identifier
        let model: Model
        
        private var showAddAndRemoveMembersButtonsView: Bool {
            switch groupIdentifier.groupType {
            case .owned:
                return true
            case .joined:
                return false
            }
        }
        
        var body: some View {
            ScrollView {
                LazyVStack {
                    
                    if model.updateInProgressDuringGroupEdition {
                        UpdateInProgressView()
                    }

                    ObvCardView {
                     
                        
                        
                    }
                }
            }
        }
    }
}
