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

struct MuteButtonView: View {

    var actionToggleAudio: () -> Void
    var isMuted: Bool

    var body: some View {
        RoundedButtonView(icon: isMuted ? .sf("mic.slash.fill") : .sf("mic.fill"),
                          text: nil, // "mute",
                          backgroundColor: Color(.systemFill),
                          backgroundColorWhenOn: Color.red,
                          isOn: isMuted,
                          action: actionToggleAudio)
            .buttonStyle(CallSettingButtonStyle())
    }

}


struct AudioButtonView: View {

    let audioInputs: [AudioInput]
    let showAudioAction: () -> Void
    let audioIcon: AudioInputIcon

    var body: some View {
        if audioInputs.count == 2 {
            RoundedButtonView(icon: .sf("speaker.3.fill"),
                              text: nil, // CommonString.Word.Speaker,
                              backgroundColor: Color(.systemFill),
                              backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                              isOn: audioInputs.first(where: { $0.isCurrent })?.isSpeaker ?? false,
                              action: { audioInputs.first(where: { !$0.isCurrent })?.activate() })
                .buttonStyle(CallSettingButtonStyle())
        } else if #available(iOS 14.0, *) {
            UIButtonWrapper(title: nil, actions: audioInputs.map { $0.toAction }) {
                RoundedButtonView(icon: audioIcon,
                                  text: nil, // "audio",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                                  isOn: false,
                                  action: { })
            }
            .frame(width: 60, height: 60)
            .buttonStyle(CallSettingButtonStyle())
        } else {
            RoundedButtonView(icon: audioIcon,
                              text: nil, // "audio",
                              backgroundColor: Color(.systemFill),
                              backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                              isOn: false,
                              action: showAudioAction)
                .buttonStyle(CallSettingButtonStyle())
        }

    }
}


struct DiscussionButtonView: View {

    var actionDiscussions: () -> Void
    var discussionsIsOn: Bool

    var body: some View {
        RoundedButtonView(icon: .sf("bubble.left.fill"),
                          text: nil, // "discussions",
                          backgroundColor: Color(.systemFill),
                          backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                          isOn: discussionsIsOn,
                          action: actionDiscussions)
            .buttonStyle(CallSettingButtonStyle())
    }
}


struct AddParticipantButtonView: View {

    var actionAddParticipant: () -> Void

    var body: some View {
        RoundedButtonView(icon: .sf("plus"),
                          text: nil, // "Add Participant",
                          backgroundColor: Color(.systemFill),
                          backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                          isOn: false,
                          action: actionAddParticipant)
            .transition(.opacity)

    }
}


struct HangupDeclineButtonView: View {

    var callIsInInitialState: Bool // True iff callState == .initial
    var actionReject: () -> Void

    var body: some View {
        if callIsInInitialState {
            RoundedButtonView(icon: .sf("xmark"),
                              text: nil, // "Decline",
                              backgroundColor: Color.red,
                              backgroundColorWhenOn: Color.red,
                              isOn: false,
                              action: actionReject)
        } else {
            RoundedButtonView(icon: .sf("phone.down.fill"),
                              text: nil, // "Hangup",
                              backgroundColor: Color.red,
                              backgroundColorWhenOn: Color.red,
                              isOn: false,
                              action: actionReject)
        }

    }

}


struct AcceptButtonView: View {

    var actionAccept: () -> Void

    var body: some View {
        RoundedButtonView(icon: .sf("checkmark"),
                          text: nil, // "Accept",
                          backgroundColor: Color(AppTheme.shared.colorScheme.olvidLight),
                          backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                          isOn: false,
                          action: actionAccept)
            .transition(.opacity)
    }
}


struct CallSettingsButtonsView: View {

    var actionToggleAudio: () -> Void
    var isMuted: Bool

    let audioInputs: [AudioInput]
    let showAudioAction: () -> Void
    let audioIcon: AudioInputIcon

    var actionDiscussions: () -> Void
    var discussionsIsOn: Bool

    var body: some View {
        HStack {
            MuteButtonView(actionToggleAudio: actionToggleAudio, isMuted: isMuted)
            AudioButtonView(audioInputs: audioInputs, showAudioAction: showAudioAction, audioIcon: audioIcon)
            DiscussionButtonView(actionDiscussions: actionDiscussions, discussionsIsOn: discussionsIsOn)
        }
    }

}



struct CallSettingsButtonsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CallSettingsButtonsView(actionToggleAudio: {},
                                    isMuted: true,
                                    audioInputs: [],
                                    showAudioAction: {},
                                    audioIcon: .sf("speaker.3.fill"),
                                    actionDiscussions: {},
                                    discussionsIsOn: false)
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Static example in light mode")
            CallSettingsButtonsView(actionToggleAudio: {},
                                    isMuted: true, audioInputs: [],
                                    showAudioAction: {},
                                    audioIcon: .sf("speaker.3.fill"),
                                    actionDiscussions: {},
                                    discussionsIsOn: false)
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Static example in dark mode")
            CallSettingsButtonsMockView(object: MockObject())
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Dynamic example in light mode")
            CallSettingsButtonsMockView(object: MockObject())
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dynamic example in dark mode")
        }
    }
}



fileprivate struct CallSettingsButtonsMockView: View {

    @ObservedObject var object: MockObject

    var body: some View {
        CallSettingsButtonsView(actionToggleAudio: object.actionToggleAudio,
                                isMuted: object.isMuted,
                                audioInputs: [],
                                showAudioAction: object.showAudioAction,
                                audioIcon: object.audioIcon,
                                actionDiscussions: object.actionDiscussions,
                                discussionsIsOn: object.discussionsIsOn)
    }

}



fileprivate class MockObject: ObservableObject {
    @Published private(set) var isMuted: Bool = true
    func actionToggleAudio() {
        isMuted.toggle()
    }
    func showAudioAction() {
    }
    @Published private(set) var discussionsIsOn: Bool = false
    func actionDiscussions() {
        discussionsIsOn.toggle()
    }
    @State var audioIcon: AudioInputIcon = .sf("speaker.3.fill")
}
