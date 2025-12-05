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
import ObvUI


protocol NewOwnedIdentityGeneratedViewActionsProtocol: AnyObject {
    func startUsingOlvidAction() async
}


struct NewOwnedIdentityGeneratedView: View {
    
    let actions: NewOwnedIdentityGeneratedViewActionsProtocol
    
    @State private var isBadgeVisible = false
    @State private var triggerConfettiCanon = 0

    private func startUsingOlvidAction() {
        Task {
            await actions.startUsingOlvidAction()
        }
    }
    
    private func onAppear() {
        Task {
            if #available(iOS 17, *) {
                try? await Task.sleep(seconds: 0.3)
                withAnimation {
                    isBadgeVisible = true
                } completion: {
                    triggerConfettiCanon += 1
                }
            } else {
                withAnimation {
                    isBadgeVisible = true
                    triggerConfettiCanon += 1
                }
            }
        }
    }

    var body: some View {
        
        ZStack {
            
            Color(ObvDesignSystem.AppTheme.shared.colorScheme.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                ScrollView {
                    VStack {
                        
                        VStack {
                            
                            ObvHeaderView(
                                title: "Congratulations!".localizedInThisBundle,
                                subtitle: nil,
                                isBadgeVisible: $isBadgeVisible)
                            .onAppear(perform: onAppear)
                            .padding(.bottom, 35)
                            .confettiCannon(trigger: $triggerConfettiCanon,
                                            num: 100,
                                            openingAngle: Angle(degrees: 0),
                                            closingAngle: Angle(degrees: 360),
                                            radius: 200)
                            
                            ObvCardView(shadow: false) {
                                
                                Text("OWNED_IDENTITY_GENERATED_EXPLANATION")
                                    .frame(minWidth: .none,
                                           maxWidth: .infinity,
                                           minHeight: .none,
                                           idealHeight: .none,
                                           maxHeight: .none,
                                           alignment: .center)
                                    .font(.body)
                                    .padding()
                                
                            }
                            
                        }.padding(.horizontal)
                        
                    }
                }
                
                // Show a "skip" button bellow the scroll view
                
                Spacer()
                
                if #available(iOS 26, *) {
                    Button(action: startUsingOlvidAction) {
                        Text("START_USING_OLVID")
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonSizing(.flexible)
                    .padding()
                } else {
                    Button(action: startUsingOlvidAction) {
                        HStack {
                            Spacer(minLength: 0)
                            Text("START_USING_OLVID")
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }

            }
            
        }
            
    }
    
}


// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: NewOwnedIdentityGeneratedViewActionsProtocol {
    func startUsingOlvidAction() async {}
}

private let actions = ActionsForPreviews()

#Preview("en") {
    NewOwnedIdentityGeneratedView(actions: actions)
}

#Preview("fr") {
    NewOwnedIdentityGeneratedView(actions: actions)
        .environment(\.locale, .init(identifier: "fr"))
}

#endif
