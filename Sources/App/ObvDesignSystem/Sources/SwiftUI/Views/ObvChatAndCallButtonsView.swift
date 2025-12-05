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

public struct ObvChatAndCallButtonsView: View {
    
    let chatButtonLooksInactive: Bool
    let callButtonIsDisabled: Bool
    let userTappedTheChatButton: () -> Void
    let userTappedTheCallButton: () -> Void
    
    public init(chatButtonLooksInactive: Bool = false, callButtonIsDisabled: Bool, userTappedTheChatButton: @escaping () -> Void, userTappedTheCallButton: @escaping () -> Void) {
        self.chatButtonLooksInactive = chatButtonLooksInactive
        self.userTappedTheChatButton = userTappedTheChatButton
        self.userTappedTheCallButton = userTappedTheCallButton
        self.callButtonIsDisabled = callButtonIsDisabled
    }
    
    public var body: some View {
        if #available(iOS 26.0, *) {
            InternalView(chatButtonLooksInactive: chatButtonLooksInactive,
                         callButtonIsDisabled: callButtonIsDisabled,
                         userTappedTheChatButton: userTappedTheChatButton,
                         userTappedTheCallButton: userTappedTheCallButton)
            .buttonStyle(.glassProminent)
        } else {
            InternalView(chatButtonLooksInactive: chatButtonLooksInactive,
                         callButtonIsDisabled: callButtonIsDisabled,
                         userTappedTheChatButton: userTappedTheChatButton,
                         userTappedTheCallButton: userTappedTheCallButton)
            .buttonStyle(.borderedProminent)
        }
    }
    
}


extension ObvChatAndCallButtonsView {
    
    struct InternalView: View {
        
        let chatButtonLooksInactive: Bool
        let callButtonIsDisabled: Bool
        let userTappedTheChatButton: () -> Void
        let userTappedTheCallButton: () -> Void

        var body: some View {
            HStack {
                Button(action: userTappedTheChatButton) {
                    Label(title: {
                        Text("BUTTON_CHAT")
                            .foregroundStyle(chatButtonLooksInactive ? .secondary : .primary)
                    }, icon: {
                        Image(systemIcon: .textBubbleFill)
                            .foregroundStyle(chatButtonLooksInactive ? .secondary : .primary)
                    })
                    .frame(maxWidth: .infinity) // buttons have the same width
                    .padding(.vertical, 4)
                }
                Button(action: userTappedTheCallButton) {
                    Label(title: { Text("BUTTON_CALL") }, icon: { Image(systemIcon: .phoneFill) })
                        .frame(maxWidth: .infinity) // buttons have the same width
                        .padding(.vertical, 4)
                }
                .disabled(callButtonIsDisabled)
            }
        }

    }
    
}


#Preview {
    ObvChatAndCallButtonsView(callButtonIsDisabled: false, userTappedTheChatButton: {}, userTappedTheCallButton: {})
}
