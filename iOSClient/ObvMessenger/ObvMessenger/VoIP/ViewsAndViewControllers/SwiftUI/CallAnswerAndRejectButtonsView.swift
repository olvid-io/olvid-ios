/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

@available(iOS 13.0, *)
struct CallAnswerAndRejectButtonsView: View {
    var callState: CallState
    var actionReject: () -> Void
    var actionAccept: () -> Void
    var actionAddParticipant: () -> Void
    var showAcceptButton: Bool
    var showAddParticipantButton: Bool
    var body: some View {
        HStack {
            if showAddParticipantButton {
                Spacer()
                AddParticipantButtonView(actionAddParticipant: actionAddParticipant)
            }
            Spacer()
            HangupDeclineButtonView(callState: callState, actionReject: actionReject)
            Spacer()
            if showAcceptButton {
                AcceptButtonView(actionAccept: actionAccept)
                Spacer()
            }
        }
    }
}



@available(iOS 13.0, *)
struct CallAnswerAndRejectButtonsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CallAnswerAndRejectButtonsView(callState: .initial, actionReject: {}, actionAccept: {}, actionAddParticipant: {}, showAcceptButton: true, showAddParticipantButton: false)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Static example in light mode")
            CallAnswerAndRejectButtonsView(callState: .initial, actionReject: {}, actionAccept: {}, actionAddParticipant: {}, showAcceptButton: true, showAddParticipantButton: false)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Static example in dark mode")
            CallAnswerAndRejectButtonsView(callState: .callInProgress, actionReject: {}, actionAccept: {}, actionAddParticipant: {}, showAcceptButton: false, showAddParticipantButton: false)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Static example in dark mode")
            CallAnswerAndRejectButtonsView(callState: .callInProgress, actionReject: {}, actionAccept: {}, actionAddParticipant: {}, showAcceptButton: false, showAddParticipantButton: true)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Static example in dark mode")
            CallAnswerAndRejectButtonsMockView(object: MockObject())
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dynamic example in dark mode")
        }
    }
}

@available(iOS 13.0, *)
fileprivate struct CallAnswerAndRejectButtonsMockView: View {
    @ObservedObject var object: MockObject
    var body: some View {
        CallAnswerAndRejectButtonsView(callState: object.state,
                                       actionReject: object.actionReject,
                                       actionAccept: object.actionAccept,
                                       actionAddParticipant: object.actionAddParticipant,
                                       showAcceptButton: object.showAcceptButton,
                                       showAddParticipantButton: object.showAddPartcipantButton)
    }
}


@available(iOS 13.0, *)
fileprivate class MockObject: ObservableObject {
    @Published private(set) var showAcceptButton = true
    @Published private(set) var showAddPartcipantButton = false
    @Published private(set) var state: CallState = .initial
    func actionReject() {
        withAnimation { state = .initial; showAcceptButton.toggle() }
    }
    func actionAccept() {
        withAnimation { state = .callInProgress; showAcceptButton.toggle() }
    }
    func actionAddParticipant() { }
}
