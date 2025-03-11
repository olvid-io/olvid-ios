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
import ObvSystemIcon


protocol ProtectedTransferWarningViewActionsProtocol: AnyObject {
    func userTouchedOkButton() async
    func userTouchedBackButton() async
}


struct ProtectedTransferWarningView: View {
    
    let actions: ProtectedTransferWarningViewActionsProtocol
    @State private var isDisabled: Bool = false
    
    private func userTouchedOkButton() {
        isDisabled = true
        Task { await actions.userTouchedOkButton() }
    }

    private func userTouchedBackButton() {
        isDisabled = true
        Task { await actions.userTouchedBackButton() }
    }

    
    var body: some View {
        
        VStack {
                            
                NewOnboardingHeaderView(title: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_TITLE", subtitle: nil)

            ScrollView {

                InternalTextBlock(
                    systemIcon: .personBadgeShieldExclamationmark,
                    title: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_TITLE1",
                    explanation: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_BODY1")
                .padding(.top)
                .padding(.horizontal)

                InternalTextBlock(
                    systemIcon: .ellipsisRectangle,
                    title: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_TITLE2",
                    explanation: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_BODY2")
                .padding(.top)
                .padding(.horizontal)

                InternalTextBlock(
                    systemIcon: .questionmarkSquare,
                    title: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_TITLE3",
                    explanation: "YOUR_PROFILE_IS_TRANSFER_RESTRICTED_BODY3")
                .padding(.top)
                .padding(.horizontal)

            }
                
            Spacer(minLength: 0)
            
            // Buttons
            
            HStack {
                
                BackButton(action: userTouchedBackButton)
                OkButton(action: userTouchedOkButton)
                
            }
            .disabled(isDisabled)

        }
        .padding(.horizontal)
        .onAppear {
            self.isDisabled = false
        }
        
    }
}


// MARK: - Internal text block

private struct InternalTextBlock: View {
    
    let systemIcon: SystemIcon
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    
    var body: some View {
        
        HStack(alignment: .center) {
            
            Image(systemIcon: systemIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40)
                .foregroundColor(Color.blue01)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading)
            
            
        }

    }
}


// MARK: - Internal buttons

private struct OkButton: View {

    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        Button(action: action) {
            Label("OK", systemIcon: .checkmarkCircleFill)
                .lineLimit(0)
                .foregroundStyle(.white)
                .padding(.all)
                .frame(maxWidth: .infinity)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}


private struct BackButton: View {

    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        Button(action: action) {
            Label("Back", systemIcon: .arrowshapeTurnUpBackwardFill)
                .lineLimit(0)
                .foregroundStyle(.primary)
                .padding(.all)
                .frame(maxWidth: .infinity)
        }
        .background(Color(UIColor.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}





// MARK: - Previews


struct ProtectedTransferWarningView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: ProtectedTransferWarningViewActionsProtocol {
        
        func userTouchedOkButton() async {
        }
        
        func userTouchedBackButton() async {
        }
        
    }

    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        ProtectedTransferWarningView(actions: actions)
        ProtectedTransferWarningView(actions: actions)
            .environment(\.locale, .init(identifier: "fr"))
    }
    
}
