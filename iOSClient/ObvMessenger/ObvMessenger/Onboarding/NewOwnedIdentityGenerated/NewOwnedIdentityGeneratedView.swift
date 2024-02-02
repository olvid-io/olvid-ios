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

import SwiftUI


protocol NewOwnedIdentityGeneratedViewActionsProtocol: AnyObject {
    func startUsingOlvidAction() async
}


struct NewOwnedIdentityGeneratedView: View {
    
    let actions: NewOwnedIdentityGeneratedViewActionsProtocol
    
    private func startUsingOlvidAction() {
        Task {
            await actions.startUsingOlvidAction()
        }
    }
    
    var body: some View {
        
        VStack {
            
            Image("badge", bundle: nil)
                .resizable()
                .frame(width: 60, height: 60, alignment: .center)
                .padding()
            Text("Congratulations!")
                .font(.title)
                .multilineTextAlignment(.center)
            
            ScrollView {
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

            // Show a "skip" button bellow the scroll view
            
            Spacer()
            
            Button(action: startUsingOlvidAction) {
                Text("START_USING_OLVID")
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .background(Color("Blue01"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        
        
    }
    
}


// MARK: - Previews

struct NewOwnedIdentityGeneratedView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: NewOwnedIdentityGeneratedViewActionsProtocol {
        func startUsingOlvidAction() async {}
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        Group {
            NewOwnedIdentityGeneratedView(actions: actions)
            NewOwnedIdentityGeneratedView(actions: actions)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}

