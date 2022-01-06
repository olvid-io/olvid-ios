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
import AVKit
import ObvEngine
import CoreData
import os.log

@available(iOS 13.0, *)
final class ObservableCallWrapper: ObservableObject {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObservableCallWrapper.self))

    let call: Call
    private var tokens: [NSObjectProtocol] = []

    var isOutgoingCall: Bool { call is OutgoingCall }

    @Published var callParticipantDatas: [CallParticipantData] = []
    @Published var isCallIsAnswered: Bool = false
    @Published var initialParticipantCount: Int?
    @Published var startTimestamp: Date?
    @Published var isMuted = false
    @Published var state: CallState = .initial
    @Published var audioIcon: AudioInputIcon = .sf("iphone")
    @Published var audioInputs: [AudioInput] = ObvAudioSessionUtils.shared.getAllInputs()

    private var selectedGroupMembers = Set<PersistedObvContactIdentity>()

    func actionReject() {
        call.endCall()
    }

    func actionAccept() {
        guard let incomingCall = call as? IncomingCall else { return }
        switch incomingCall.state {
        case .initial, .ringing:
            incomingCall.answerCall()
        default:
            return
        }
    }

    func actionAddParticipant(_ selectedContacts: Set<PersistedObvContactIdentity>) {
        let contactIDs = selectedContacts.map { $0.typedObjectID }
        ObvMessengerInternalNotification.userWantsToAddParticipants(call: call, contactIDs: contactIDs).postOnDispatchQueue()
    }

    func actionKick(_ callParticipant: CallParticipant) {
        ObvMessengerInternalNotification.userWantsToKickParticipant(call: call, callParticipant: callParticipant).postOnDispatchQueue()
    }

    func actionToggleAudio() {
        if call.isMuted {
            call.unmute()
        } else {
            call.mute()
        }
    }

    func actionDiscussions() {
        ObvMessengerInternalNotification.toggleCallView.postOnDispatchQueue()
    }

    init(call: Call) {
        self.call = call
        let callUuid = call.uuid
        self.tokens += [ObvMessengerInternalNotification.observeCallHasBeenUpdated(queue: OperationQueue.main) { [weak self] (updatedCall, updateKind) in
            guard updatedCall.uuid == callUuid else { return }
            switch updateKind {
            case .state, .mute:
                break
            case .callParticipantChange:
                self?.updateCallParticipants()
            }
            self?.update()
        }]
        self.tokens += [ObvMessengerInternalNotification.observeCallParticipantHasBeenUpdated(queue: OperationQueue.main) { [weak self] (updatedParticipant, updateKind) in
            if let callParticipant = self?.callParticipantDatas.first(where: { $0.id == updatedParticipant.uuid}) {
                callParticipant.update()
            }
        }]
        self.tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: OperationQueue.main, using: { [weak self] notification in
            guard let _self = self else { return }
            _self.update()
        }))
        updateCallParticipants()
        update()
    }

    private func updateCallParticipants() {
        let currentParticipantsId = self.callParticipantDatas
        let newParticipantsId = call.callParticipants.map {
            CallParticipantData(callParticipant: $0, startTimestamp: self.startTimestamp)
        }

        let changes = newParticipantsId.difference(from: currentParticipantsId)

        for change in changes {
            guard case let .insert(_, element: newParticipant, associatedWith: _) = change else { continue }
            self.callParticipantDatas += [newParticipant]
        }

        // We wait some seconds to show the new participants list
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            for change in changes {
                guard case let .remove(_, element: removedParticipant, associatedWith: _) = change else { continue }
                self.callParticipantDatas.removeAll(where: { $0 == removedParticipant})
            }
        }
    }

    private func update() {
        // Update isCallIsAnswered
        if let incomingCall = call as? IncomingWebrtcCall {
            switch incomingCall.state {
            case .initial, .ringing:
                /// We never show the answerCallButton when we use call kit
                isCallIsAnswered = incomingCall.usesCallKit
                initialParticipantCount = incomingCall.initialParticipantCount

            default:
                isCallIsAnswered = true
            }
        } else {
            isCallIsAnswered = true
        }
        // Update the startTimestamp

        if self.startTimestamp == nil, let start = self.call.stateDate[.callInProgress] {
            self.startTimestamp = start
            for participant in callParticipantDatas {
                participant.startTimestamp = start
            }
        }
        // Update muteIsOn
        isMuted = call.isMuted
        // Update state
        state = call.state

        audioInputs = ObvAudioSessionUtils.shared.getAllInputs()

        // Update current route
        if let currentInput = ObvAudioSessionUtils.shared.getCurrentAudioInput() {
            self.audioIcon = currentInput.icon
        } else {
            self.audioIcon = .sf("iphone")
        }
    }

}

@available(iOS 13.0, *)
struct CallView: View {

    @ObservedObject var wrappedCall: ObservableCallWrapper

    var body: some View {
        InnerCallView(callParticipantDatas: wrappedCall.callParticipantDatas,
                      isOutgoingCall: wrappedCall.isOutgoingCall,
                      startTimestamp: wrappedCall.startTimestamp,
                      isMuted: wrappedCall.isMuted,
                      audioIcon: wrappedCall.audioIcon,
                      audioInputs: wrappedCall.audioInputs,
                      discussionsIsOn: false,
                      isCallIsAnswered: wrappedCall.isCallIsAnswered,
                      initialParticipantCount: wrappedCall.initialParticipantCount,
                      callState: wrappedCall.state,

                      actionToggleAudio: wrappedCall.actionToggleAudio,
                      actionDiscussions: wrappedCall.actionDiscussions,
                      actionReject: wrappedCall.actionReject,
                      actionAccept: wrappedCall.actionAccept,
                      actionAddParticipant: wrappedCall.actionAddParticipant,
                      actionKick: wrappedCall.actionKick)
    }

}

@available(iOS 13.0, *)
struct CounterView: View {

    let startTimestamp: Date?

    init(startTimestamp: Date?) {
        self.startTimestamp = startTimestamp
        refreshCounter()
    }

    @State private var counter: TimeInterval?
    private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func refreshCounter() {
        if let st = self.startTimestamp {
            self.counter = Date().timeIntervalSince(st)
        }
    }

    private let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated // Or .short or .abbreviated
        f.allowedUnits = [.second, .minute, .hour]
        return f
    }()

    private func makeCounterString() -> String {
        var res = "Olvid Audio"
        if let counter = self.counter,
           let formattedCounter = formatter.string(from: counter) {
            res = [res, formattedCounter].joined(separator: " - ")
        }
        return res
    }

    var body: some View {
        HStack {
            Image("badge")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
            Text(makeCounterString())
                .onReceive(timer) { (_) in
                    refreshCounter()
                }
                .font(.callout)
                .foregroundColor(Color(.secondaryLabel))
        }
    }
}

@available(iOS 13.0, *)
fileprivate struct InnerCallView: View {

    let callParticipantDatas: [CallParticipantData]
    let isOutgoingCall: Bool
    let startTimestamp: Date?
    let isMuted: Bool
    let audioIcon: AudioInputIcon
    let audioInputs: [AudioInput]
    let discussionsIsOn: Bool
    let isCallIsAnswered: Bool
    let initialParticipantCount: Int?
    let callState: CallState

    let actionToggleAudio: () -> Void
    let actionDiscussions: () -> Void
    let actionReject: () -> Void
    let actionAccept: () -> Void
    let actionAddParticipant: (_ selectedContacts: Set<PersistedObvContactIdentity>) -> Void
    let actionKick: (_ callParticipant: CallParticipant) -> Void

    var isGroupCall: Bool { callParticipantDatas.count > 1 }
    var showAddParticipantButton: Bool { isOutgoingCall }
    var showAcceptButton: Bool { !isCallIsAnswered }
    var ownedIdentity: ObvCryptoId? {
        let ids = callParticipantDatas.compactMap { $0.callParticipant?.ownedIdentity }
        return ids.first
    }
    var imagesOnTheLeft: Bool {
        isGroupCall || verticalSizeClass == .compact
    }

    @State private var showAddParticipantView = false
    @State private var showAudioActionSheet = false

    @Environment(\.verticalSizeClass) var verticalSizeClass

    private func getSpeakerActionSheetButtons() -> [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = audioInputs.map({
            let label = $0.label + ($0.isCurrent ? " ✔︎" : "")
            return Alert.Button.default(Text(label), action: $0.activate)
        })
        buttons.append(Alert.Button.cancel({ showAudioActionSheet = false }))
        return buttons
    }

    func participantView(_ data: CallParticipantData) -> ParticipantView {
        ParticipantView(
            callParticipantData: data,
            isOutgoingCall: isOutgoingCall,
            isGroupCall: isGroupCall,
            isCallIsAnswered: isCallIsAnswered,
            imagesOnTheLeft: imagesOnTheLeft,
            initialParticipantCount: initialParticipantCount,
            actionKick: actionKick)
    }

    struct CallButton: Identifiable {
        var id = UUID()
        var view: AnyView
        var bottom: Bool

        init(_ view: AnyView, bottom: Bool) {
            self.view = view
            self.bottom = bottom
        }
    }

    var buttons: [CallButton] {
        var result = [CallButton]()

        if !showAcceptButton {
            if showAddParticipantButton {
                result += [CallButton(AnyView(AddParticipantButtonView(actionAddParticipant: {
                                                                        showAddParticipantView.toggle() })),
                                      bottom: false)]
            }

            result += [CallButton(AnyView(MuteButtonView(actionToggleAudio: actionToggleAudio,
                                                         isMuted: isMuted)),
                                  bottom: true)]

            result += [CallButton(AnyView(AudioButtonView(audioInputs: audioInputs,
                                                          showAudioAction: {
                                                            showAudioActionSheet.toggle()
                                                          },
                                                          audioIcon: audioIcon)
                                            .actionSheet(isPresented: $showAudioActionSheet, content: {
                                                ActionSheet(title: Text("CHOOSE_PREFERRED_AUDIO_SOURCE"), message: nil, buttons: getSpeakerActionSheetButtons())
                                            })),
                                  bottom: true)]

            result += [CallButton(AnyView(DiscussionButtonView(actionDiscussions: actionDiscussions,
                                                               discussionsIsOn: discussionsIsOn)),
                                  bottom: true)]

        }

        result += [CallButton(AnyView(HangupDeclineButtonView(callState: callState, actionReject: actionReject)),
                              bottom: true)]

        if showAcceptButton {
            result += [CallButton(AnyView(AcceptButtonView(actionAccept: actionAccept)),
                                  bottom: true)]
        }

        return result
    }



    var body: some View {
        ZStack {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading) {
                if callParticipantDatas.count == 1,
                   let participantData = callParticipantDatas.first {
                    participantView(participantData)
                    if !imagesOnTheLeft {
                        Spacer()
                        HStack {
                            Spacer()
                            participantData.profilePictureView(customCircleDiameter: 150.0)
                            Spacer()
                        }
                    }
                } else {
                    ScrollView {
                        ForEach(callParticipantDatas) { participantData in
                            participantView(participantData)
                        }
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        if isGroupCall {
                            CounterView(startTimestamp: startTimestamp)
                        }
                        if !isGroupCall || callState != .callInProgress {
                            Text(callState.localizedString)
                                .font(Font.headline.smallCaps())
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    Spacer()
                }
                Spacer()
                if verticalSizeClass != .compact && showAddParticipantButton {
                    HStack(alignment: .center) {
                        Spacer()
                        ForEach(buttons.filter({ !$0.bottom })) { button in
                            button.view
                                .padding([.bottom])
                            Spacer()
                        }
                    }
                }
                HStack(alignment: .center) {
                    Spacer()
                    ForEach(buttons.filter({ $0.bottom || verticalSizeClass == .compact })) { button in
                        button.view
                            .padding([.bottom])
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showAddParticipantView) {
            MultipleContactsView(ownedCryptoId: ownedIdentity, mode: .excluded(from: Set(callParticipantDatas.compactMap { $0.callParticipant?.contactIdentity })), button: .floating(title: CommonString.Word.Call, systemIcon: .phoneFill), disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false) { selectedContacts in
                actionAddParticipant(selectedContacts)
                showAddParticipantView = false
            } dismissAction: {
                showAddParticipantView = false
            }
        }
    }

}

@available(iOS 13.0, *)
class CallParticipantData: ObservableObject, Identifiable, Equatable {

    static func == (lhs: CallParticipantData, rhs: CallParticipantData) -> Bool {
        return lhs.callParticipant?.uuid == rhs.callParticipant?.uuid
    }

    var callParticipant: CallParticipant?
    var id: UUID
    @Published var name: String?
    @Published var photoURL: URL?
    @Published var isMuted = false
    @Published var status: String = ""
    @Published var startTimestamp: Date?

    /// For preview purpose
    fileprivate init(name: String?, isMuted: Bool, state: PeerState) {
        self.callParticipant = nil
        self.id = UUID()
        self.name = name
        self.isMuted = isMuted
        self.status = state.localizedString
        self.startTimestamp = Date()
    }

    init(callParticipant: CallParticipant, startTimestamp: Date?) {
        self.callParticipant = callParticipant
        self.id = callParticipant.uuid
        self.startTimestamp = startTimestamp
        update()
    }

    func update() {
        self.name = callParticipant?.displayName
        self.isMuted = callParticipant?.contactIsMuted ?? false
        self.status = callParticipant?.state.localizedString ?? ""
        self.photoURL = callParticipant?.photoURL
    }

    var circledTextView: Text? {
        if let cdn = name, let char = cdn.first {
            return Text(String(char))
        } else {
            return nil
        }
    }

    var uiImage: UIImage? {
        guard let photoURL = photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }


    func profilePictureView(customCircleDiameter: CGFloat? = nil) -> ProfilePictureView {
        ProfilePictureView(profilePicture: uiImage,
                           circleBackgroundColor: callParticipant?.identityColors?.background,
                           circleTextColor: callParticipant?.identityColors?.text,
                           circledTextView: circledTextView,
                           imageSystemName: "person",
                           showGreenShield: false,
                           showRedShield: false,
                           customCircleDiameter: customCircleDiameter)
    }

}

@available(iOS 13.0, *)
struct ParticipantView: View {

    @ObservedObject var callParticipantData: CallParticipantData

    var isOutgoingCall: Bool
    var isGroupCall: Bool
    var isCallIsAnswered: Bool
    var imagesOnTheLeft: Bool
    var initialParticipantCount: Int?
    var actionKick: (_ callParticipant: CallParticipant) -> Void

    @State private var showingKickConfirmationActionSheet: Bool = false

    var participantName: String {
        var result = callParticipantData.name ?? "..."
        if !isCallIsAnswered,
           let initialParticipantCount = initialParticipantCount,
           initialParticipantCount > 1 {
            result += " + \(initialParticipantCount - 1)"
        }
        return result
    }

    var body: some View {
        HStack {
            if imagesOnTheLeft {
                Button(action: {
                    guard case .known(let contactID) = callParticipantData.callParticipant?.contactIdentificationStatus else { return }
                    ObvStack.shared.viewContext.perform {
                        guard let persistedContact = try? PersistedObvContactIdentity.get(objectID: contactID, within: ObvStack.shared.viewContext) else { return }
                        let discussionObjectURI = persistedContact.oneToOneDiscussion.objectID.uriRepresentation()
                        let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: discussionObjectURI)
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                            .postOnDispatchQueue()
                        return
                    }
                }) {
                    callParticipantData.profilePictureView()
                }
            }
            VStack(alignment: .leading) {
                Text(participantName)
                    .font(imagesOnTheLeft ? .title : .largeTitle)
                    .fontWeight(.heavy)
                    .padding(.bottom, -4.0)
                    .lineLimit(1)
                    .foregroundColor(Color(.label))
                    .overlay(callParticipantData.isMuted ? AnyView(MutedBadgeView().offset(x: MutedBadgeView.size / 2, y: -0)) : AnyView(EmptyView()), alignment: Alignment(horizontal: .trailing, vertical: .top))
                if isGroupCall {
                    Text(callParticipantData.status)
                        .font(.callout)
                        .foregroundColor(Color(.tertiaryLabel))
                } else {
                    CounterView(startTimestamp: callParticipantData.startTimestamp)
                }
            }
            Spacer()
            if isOutgoingCall && isGroupCall {
                RoundedButtonView(size: 30,
                                  icon: .sf("minus"),
                                  text: nil,
                                  backgroundColor: Color(.red),
                                  backgroundColorWhenOn: Color(.red),
                                  isOn: false,
                                  action: {
                                    showingKickConfirmationActionSheet = true
                                  })
            }
        }
        .padding(.top, 16)
        .padding([.leading, .trailing], 24)
        .actionSheet(isPresented: $showingKickConfirmationActionSheet) {
            ActionSheet(title: Text("ALERT_TITLE_KICK_PARTICIPANT"),
                        message: Text("ALERT_MESSAGE_KICK_PARTICIPANT_\(participantName)"),
                        buttons: [
                            .default(Text( CommonString.Word.Exclude)) {
                                if let callParticipant = callParticipantData.callParticipant {
                                    actionKick(callParticipant)
                                }
                            },
                            .cancel()
                        ])
        }
    }
}



// MARK: - Previews


@available(iOS 13.0, *)
struct InnerCallView_Previews: PreviewProvider {

    static var logiciansNames = ["Alan Turing", "Kurt Gödel", "David Hilbert", "Stephen Cole Kleene", "Haskell Curry", "Georg Cantor", "Willard Van Orman Quine", "Aristote", "Giuseppe Peano"]

    static var logicians = logiciansNames.map { CallParticipantData(name: $0, isMuted: $0.count % 2 == 0, state: .connected) }

    private static let fakeAudioInputs = [
        AudioInput(label: "Nice speaker", isCurrent: true, icon: .sf("speaker.1.fill"), isSpeaker: true),
        AudioInput(label: "Great handset", isCurrent: false, icon: .sf("headphones"), isSpeaker: false),
    ]
    static var audioIcon: AudioInputIcon = fakeAudioInputs.first!.icon

    static var previews: some View {
        Group {
            InnerCallView(callParticipantDatas: [CallParticipantData(name: "Alan Turing", isMuted: true, state: .connected)],
                          isOutgoingCall: true,
                          startTimestamp: Date(),
                          isMuted: true,
                          audioIcon: audioIcon,
                          audioInputs: fakeAudioInputs,
                          discussionsIsOn: false,
                          isCallIsAnswered: true,
                          initialParticipantCount: nil,
                          callState: .callInProgress,

                          actionToggleAudio: {},
                          actionDiscussions: {},
                          actionReject: {},
                          actionAccept: {},
                          actionAddParticipant: {_ in},
                          actionKick: { _ in })
                .environment(\.colorScheme, .dark)

            InnerCallView(callParticipantDatas: logicians,
                          isOutgoingCall: true,
                          startTimestamp: Date(),
                          isMuted: true,
                          audioIcon: audioIcon,
                          audioInputs: fakeAudioInputs,
                          discussionsIsOn: false,
                          isCallIsAnswered: true,
                          initialParticipantCount: nil,
                          callState: .callInProgress,

                          actionToggleAudio: {},
                          actionDiscussions: {},
                          actionReject: {},
                          actionAccept: {},
                          actionAddParticipant: {_ in},
                          actionKick: { _ in })
                .environment(\.colorScheme, .light)

            InnerCallView(callParticipantDatas: logicians,
                          isOutgoingCall: false,
                          startTimestamp: Date(),
                          isMuted: true,
                          audioIcon: audioIcon,
                          audioInputs: fakeAudioInputs,
                          discussionsIsOn: false,
                          isCallIsAnswered: true,
                          initialParticipantCount: nil,
                          callState: .callInProgress,

                          actionToggleAudio: {},
                          actionDiscussions: {},
                          actionReject: {},
                          actionAccept: {},
                          actionAddParticipant: {_ in},
                          actionKick: { _ in })
                .environment(\.colorScheme, .light)
        }
    }
}
