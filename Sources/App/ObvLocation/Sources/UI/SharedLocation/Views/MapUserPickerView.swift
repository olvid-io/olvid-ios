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
import ObvUICoreData
import Combine
import ObvUI
import ObvSettings
import ObvSystemIcon

struct MapUserPickerView: View {

    @ObservedObject var viewModel: MapUserPickerViewModel

    private let userAvatarSize: CGFloat = 22.0
    
    init(viewModel: MapUserPickerViewModel) {
        self.viewModel = viewModel
    }
    
    private var cornerRadius: CGFloat {
        viewModel.displayableUserContents.count > 1 ? 8.0 : 30.0
    }
    
    private func userPositionContent(for userContent: MapUserPositionContentViewModel) -> some View {
        ZStack {
            Circle()
                .foregroundColor(.white)
                .frame(width: userAvatarSize + 4.0, height: userAvatarSize + 4.0)
            
            CircledInitialsView(configuration: userContent.userInitialConfiguraton,
                                size: .custom(sizeLength: userAvatarSize),
                                style: ObvMessengerSettings.Interface.identityColorStyle)
        }
        .tag(userContent.contactCryptoId)
    }
    
    var body: some View {
        
        if !viewModel.displayableUserContents.isEmpty {
            ScrollView {
                VStack(alignment: .leading) {
                    // Menu
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.togglePicker()
                        }
                    }) {
                        HStack(spacing: 4.0) {
                            if let selectedUserContent = viewModel.centeredUserContent {
                                userPositionContent(for: selectedUserContent)
                            } else {
                                Image(symbolIcon: SystemIcon.locationCircle)
                                    .imageScale(.large)
                            }
                            
                            if viewModel.displayableUserContents.count > 1 {
                                Image(symbolIcon: SystemIcon.chevronRight)
                                    .imageScale(.small)
                                    .rotationEffect(.degrees(viewModel.pickerIsOpened ? 90 : 0))
                                    .animation(.spring(), value: viewModel.pickerIsOpened)
                            }
                        }
                        .foregroundStyle(Color(UIColor.label))
                        .padding(8.0)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    
                    // Opened Picker
                    if viewModel.pickerIsOpened {
                        VStack {
                            ForEach(viewModel.displayableUserContents, id: \.contactCryptoId) { userContent in
                                Button(action: { viewModel.userContentHasBeenSelected(userContent: userContent) }) {
                                    userPositionContent(for: userContent)
                                }
                            }
                        }
                        .padding(8.0)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 8.0, style: .continuous))
                        .transition(.moveAndScale)
                    }
                }
            }
        }
    }
    
}

extension AnyTransition {
    static var moveAndScale: AnyTransition {
        AnyTransition.move(edge: .top)
            .combined(with: .scale)
            .combined(with: opacity)
    }
}
