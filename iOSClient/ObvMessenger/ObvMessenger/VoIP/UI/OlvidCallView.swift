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

import Foundation
import SwiftUI
import ObvTypes
import UI_ObvCircledInitials
import UI_SystemIcon


protocol OlvidCallViewModelProtocol: ObservableObject, OngoingCallButtonsViewModelProtocol, AcceptOrRejectButtonsViewModelProtocol {
    associatedtype OlvidCallParticipantViewModel: OlvidCallParticipantViewModelProtocol
    var ownedCryptoId: ObvCryptoId { get }
    var otherParticipants: [OlvidCallParticipantViewModel] { get }
    var localUserStillNeedsToAcceptOrRejectIncomingCall: Bool { get }
    var uuidForCallKit: UUID { get }
    var direction: OlvidCall.Direction { get }
    var dateWhenCallSwitchedToInProgress: Date? { get }
}


protocol OlvidCallViewActionsProtocol: AcceptOrRejectButtonsViewActionsProtocol, OngoingCallButtonsViewActionsProtocol {
    func userWantsToAddParticipantsToExistingCall(uuidForCallKit: UUID, participantsToAdd: Set<ObvCryptoId>) async throws
    func userWantsToRemoveParticipant(uuidForCallKit: UUID, participantToRemove: ObvCryptoId) async throws
}


protocol OlvidCallViewNavigationActionsProtocol: AnyObject {
    func userWantsToAddParticipantToCall(ownedCryptoId: ObvCryptoId, currentOtherParticipants: Set<ObvCryptoId>) async -> Set<ObvCryptoId>
}


fileprivate enum Orientation {
    case vertical
    case horizontal
}

/// Main view used when displaying a call to the user.
struct OlvidCallView<Model: OlvidCallViewModelProtocol>: View, OlvidCallParticipantViewActionsProtocol {
    
    @ObservedObject var model: Model
    let actions: OlvidCallViewActionsProtocol
    let navigationActions: OlvidCallViewNavigationActionsProtocol

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var callDuration: String?
        
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    private var orientation: Orientation {
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.compact, .compact), (.regular, .compact):
            return .horizontal
        default:
            return .vertical
        }
    }
    
    /// State common to all `OlvidCallParticipantView` instances displayed by this view
    private var callParticipantViewState: OlvidCallParticipantViewState {
        let showRemoveParticipantButton: Bool
        switch model.direction {
        case .incoming:
            showRemoveParticipantButton = false
        case .outgoing:
            showRemoveParticipantButton = model.otherParticipants.count != 1
        }
        return .init(showRemoveParticipantButton: showRemoveParticipantButton)
    }
    
    
    private func userWantsToAddParticipantToCall() {
        Task {
            let currentOtherParticipants = Set(model.otherParticipants.map({ $0.cryptoId }))
            let participantsToAdd = await navigationActions.userWantsToAddParticipantToCall(ownedCryptoId: model.ownedCryptoId, currentOtherParticipants: currentOtherParticipants)
            do {
                try await actions.userWantsToAddParticipantsToExistingCall(uuidForCallKit: model.uuidForCallKit, participantsToAdd: participantsToAdd)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    func userWantsToRemoveParticipant(cryptoId: ObvCryptoId) async throws {
        do {
            try await actions.userWantsToRemoveParticipant(uuidForCallKit: model.uuidForCallKit, participantToRemove: cryptoId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    private let dateFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated // Or .short or .abbreviated
        f.allowedUnits = [.second, .minute, .hour]
        return f
    }()

    
    private func refreshCallDuration() {
        guard let date = model.dateWhenCallSwitchedToInProgress else { return }
        let newCallDuration = dateFormatter.string(from: abs(date.timeIntervalSinceNow))
        if callDuration == nil {
            withAnimation(.bouncy) {
                callDuration = newCallDuration
            }
        } else {
            callDuration = newCallDuration
        }
    }

    
    var body: some View {
        VHStack(orientation: orientation) {
                    
            if orientation == .horizontal {
                
                VStack {
                    
                    if model.localUserStillNeedsToAcceptOrRejectIncomingCall {
                        AcceptOrRejectButtonsView(model: model, actions: actions)
                    } else {
                        OngoingCallButtonsView(globalOrientation: orientation, model: model, actions: actions)
                    }
                }
                .padding(.trailing)
                
                Divider()
                    .padding(.trailing)
                
            }
                        
            VStack {
                
                // If the call is an outgoing call, show a button allowing the caller to add participants to the call
                
                if model.direction == .outgoing {
                    HStack {
                        Spacer()
                        Button(action: userWantsToAddParticipantToCall) {
                            Image(systemIcon: .personCropCircleBadgePlus)
                                .font(.system(size: 26))
                        }
                    }
                }
                
                // Show a list of all participants
                
                ScrollView {
                    ForEach(model.otherParticipants) { participant in
                        OlvidCallParticipantView(model: participant, state: callParticipantViewState, actions: self)
                    }
                }
                
                Spacer()
                    
                CallDurationAndTitle(orientation: orientation, callDuration: callDuration)

            }
                    
            if orientation == .vertical {
                VStack {
                    
                    if model.localUserStillNeedsToAcceptOrRejectIncomingCall {
                        AcceptOrRejectButtonsView(model: model, actions: actions)
                    } else {
                        OngoingCallButtonsView(globalOrientation: orientation, model: model, actions: actions)
                    }
                    
                }
            }
                
        }
        .padding()
        .onReceive(timer) { (_) in
            refreshCallDuration()
        }
        
    }
}


// MARK: Call duration and title

private struct CallDurationAndTitle: View {

    let orientation: Orientation
    let callDuration: String?

    var body: some View {
        
        switch orientation {
        case .vertical:
            VStack {
                BadgeAndTextView()
                if let callDuration {
                    Text(verbatim: callDuration)
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(Color(UIColor.secondaryLabel))
        case .horizontal:
            HStack {
                BadgeAndTextView()
                if let callDuration {
                    Text(verbatim: "-")
                    Text(verbatim: callDuration)
                }
                Spacer()
            }
            .font(.system(size: 16))
            .foregroundStyle(Color(UIColor.secondaryLabel))
            .padding(.leading, 82)
        }

    }
    
}


// MARK: - BadgeAndTextView

private struct BadgeAndTextView: View {
    var body: some View {
        HStack {
            Image("badge")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
            Text("OLVID_AUDIO")
        }
    }
}


// MARK: - VHStack view

private struct VHStack<Content: View>: View {

    let orientation: Orientation
    let spacing: CGFloat?
    
    let content: Content

    init(orientation: Orientation, spacing: CGFloat? = nil, @ViewBuilder _ content: () -> Content) {
        self.orientation = orientation
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        switch orientation {
        case .vertical:
            VStack(spacing: spacing) {
                content
            }
        case .horizontal:
            HStack(spacing: spacing) {
                content
            }
        }
    }
}


// MARK: - Buttons shown when the local user needs to accept/reject incoming call

protocol AcceptOrRejectButtonsViewActionsProtocol {
    func userAcceptedIncomingCall(uuidForCallKit: UUID) async throws
    func userRejectedIncomingCall(uuidForCallKit: UUID) async throws
}


protocol AcceptOrRejectButtonsViewModelProtocol: ObservableObject {
    var uuidForCallKit: UUID { get }
}


private struct AcceptOrRejectButtonsView<Model: AcceptOrRejectButtonsViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: AcceptOrRejectButtonsViewActionsProtocol
    
    private let buttonImageFontSize: CGFloat = 20

    private func userRejectedIncomingCall() {
        Task {
            do {
                try await actions.userRejectedIncomingCall(uuidForCallKit: model.uuidForCallKit)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    private func userAcceptedIncomingCall() {
        Task {
            do {
                try await actions.userAcceptedIncomingCall(uuidForCallKit: model.uuidForCallKit)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 24) {
            
            CallButton(action: userRejectedIncomingCall,
                       systemIcon: .xmark,
                       background: .systemRed,
                       text: nil)
            
            CallButton(action: userAcceptedIncomingCall,
                       systemIcon: .checkmark,
                       background: .systemGreen,
                       text: nil)
            
        }
    }
}


// MARK: - Stack of buttons shown during an ongoing call

protocol OngoingCallButtonsViewModelProtocol: ObservableObject, AudioMenuButtonModelProtocol {
    var selfIsMuted: Bool { get }
    var uuidForCallKit: UUID { get }
}


protocol OngoingCallButtonsViewActionsProtocol: AudioMenuButtonActionsProtocol {
    func userWantsToEndOngoingCall(uuidForCallKit: UUID) async throws
    func userWantsToSetMuteSelf(uuidForCallKit: UUID, muted: Bool) async throws
}


private struct OngoingCallButtonsView<Model: OngoingCallButtonsViewModelProtocol>: View {
    
    let globalOrientation: Orientation
    @ObservedObject var model: Model
    let actions: OngoingCallButtonsViewActionsProtocol
    
    private let buttonImageFontSize: CGFloat = 20

    private func userWantsToToggleMuteSelf() {
        Task {
            do {
                try await actions.userWantsToSetMuteSelf(uuidForCallKit: model.uuidForCallKit, muted: !model.selfIsMuted)
            } catch {
                assertionFailure()
            }
        }
    }

    
    private func userWantsToEndOngoingCall() {
        Task {
            do {
                try await actions.userWantsToEndOngoingCall(uuidForCallKit: model.uuidForCallKit)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    private func userWantsToChat() {
        VoIPNotification.hideCallView.postOnDispatchQueue()
    }
    
    
    private var buttonStackOrientation: Orientation {
        switch globalOrientation {
        case .horizontal: return .vertical
        case .vertical: return .horizontal
        }
    }
    
    var body: some View {
        
        VHStack(orientation: buttonStackOrientation, spacing: 24) {
            
            HStack(alignment: .top, spacing: 24) {
                
                CallButton(action: userWantsToToggleMuteSelf,
                           systemIcon: .micSlashFill,
                           background: model.selfIsMuted ? .systemRed : .systemFill,
                           text: model.selfIsMuted ? "Unmute" : "Mute")
                
                AudioMenuButton(model: model, actions: actions)
                
            }
            
            HStack(alignment: .top, spacing: 24) {
                
                CallButton(action: userWantsToChat,
                           systemIcon: .bubbleLeftAndBubbleRightFill,
                           background: .systemFill,
                           text: "Chat")
                
                CallButton(action: userWantsToEndOngoingCall,
                           systemIcon: .phoneDownFill,
                           background: .systemRed,
                           text: "End")
                
            }
        }

    }
}


// MARK: - Generic view for most buttons shown during a call

private struct CallButton: View {
    
    let action: () -> Void
    let systemIcon: SystemIcon
    let background: UIColor
    let text: LocalizedStringKey?
    
    var body: some View {
        VStack {
            Button(action: action, label: {
                ZStack {
                    Circle()
                        .foregroundStyle(Color(background))
                    Image(systemIcon: systemIcon)
                        .font(Constants.inCallImageFont)
                        .foregroundStyle(.white)
                }
            })
            .frame(width: Constants.inCallButtonFrameWidth, height: Constants.inCallButtonFrameWidth)
            if let text {
                VStack {
                    Text(text)
                        .font(.system(size: Constants.inCallButtonTextSize))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                    Spacer(minLength: 0)
                }
                .frame(height: Constants.inCallButtonTextFrameHeight)
            }
        }
        .frame(width: Constants.inCallButtonFrameWidth)
    }
    
}


// MARK: - Button for choosing Audio input

protocol AudioMenuButtonModelProtocol: ObservableObject, AudioMenuButtonLabelViewModelProtocol {
    var availableAudioOptions: [OlvidCallAudioOption]? { get } // Nil if the available options cannot be determined yet
    func userWantsToActivateAudioOption(_ audioOption: OlvidCallAudioOption) async throws
    func userWantsToChangeSpeaker(to isSpeakerEnabled: Bool) async throws
}


protocol AudioMenuButtonActionsProtocol {
}


private struct AudioMenuButton<Model: AudioMenuButtonModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: AudioMenuButtonActionsProtocol
    
    /// Called when the user chooses a particular audio input from the menu displayed when tapping the audio button
    private func userTappedOnAudioOption(_ audioOption: OlvidCallAudioOption) {
        Task {
            do {
                try await model.userWantsToActivateAudioOption(audioOption)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    /// The button is available only if the user can only toggle between the built-in speaker in the internal mic.
    private func userTappedOnAudioButton() {
        Task {
            do {
                try await model.userWantsToChangeSpeaker(to: !model.isSpeakerEnabled)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    /// Type of the input shown on screen.
    ///
    /// On macOS, the input can only be chosen in the menu bar, so tapping the button shows an alert.
    /// On iOS/iPadOS :
    /// - if the only alternative choice would be to activate the speaker, we show a button that toggle the speaker;
    /// - if more choices are available, we show a menu allowing to choose among the inputs.
    private enum InputType {
        case button
        case menu(availableAudioOptions: [OlvidCallAudioOption])
        case alertOnMac
    }
    
    
    private var inputType: InputType {
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            return .alertOnMac
        }
        guard let availableAudioOptions = model.availableAudioOptions else {
            return .button
        }
        switch availableAudioOptions.count {
        case let nbrAvailableAudioOptions where nbrAvailableAudioOptions > 2:
            return .menu(availableAudioOptions: availableAudioOptions)
        default:
            return .button
        }
    }
    
    private var subtitleLocalizedStringKey: LocalizedStringKey {
        if model.isSpeakerEnabled {
            return "SPEAKER"
        } else {
            return "AUDIO"
        }
    }
    
    
    var body: some View {

        VStack {
            
            // Show a Menu or a simple button, depending on the number of options to choose from
            
            switch inputType {
                
            case .alertOnMac:

                Menu {
                    Text("THE_CALL_AUDIO_CONFIG_FOR_MAC_IS_AVAILABLE_IN_MENU_BAR")
                        .foregroundStyle(.primary)
                } label: {
                    AudioMenuButtonLabelView(model: model)
                }
                .frame(width: Constants.inCallButtonFrameWidth, height: Constants.inCallButtonFrameWidth)
                
            case .button:

                Button(action: userTappedOnAudioButton) {
                    AudioMenuButtonLabelView(model: model)
                }
                .frame(width: Constants.inCallButtonFrameWidth, height: Constants.inCallButtonFrameWidth)

            case .menu(availableAudioOptions: let availableAudioOptions):
                
                Menu {
                    ForEach(availableAudioOptions) { audioOption in
                        Button(action: { userTappedOnAudioOption(audioOption) }) {
                            Label {
                                Text(verbatim: audioOption.portName)
                            } icon: {
                                switch audioOption.icon {
                                case .sf(let systemIcon):
                                    Image(systemIcon: systemIcon)
                                        .font(Constants.inCallImageFont)
                                case .png(let filename):
                                    Image(filename)
                                        .renderingMode(.template)
                                        .resizable()
                                        .foregroundColor(.white)
                                        .frame(width: Constants.inCallImagePngSize, height: Constants.inCallImagePngSize)

                                }
                            }
                        }
                    }
                } label: {
                    AudioMenuButtonLabelView(model: model)
                }
                .frame(width: Constants.inCallButtonFrameWidth, height: Constants.inCallButtonFrameWidth)
            }
            
            // In all cases, show text bellow the menu or button
            
            VStack {
                Text(subtitleLocalizedStringKey)
                    .font(.system(size: Constants.inCallButtonTextSize))
                    .foregroundStyle(Color(UIColor.tertiaryLabel))
                Spacer(minLength: 0)
            }
            .frame(height: Constants.inCallButtonTextFrameHeight)

        }
        .frame(width: Constants.inCallButtonFrameWidth)

    }
    
}

// MARK: - The view used for the audio button, both when using a menu or a button

protocol AudioMenuButtonLabelViewModelProtocol: ObservableObject {
    var isSpeakerEnabled: Bool { get }
    var currentAudioOptions: [OlvidCallAudioOption] { get } // Empty if the current option cannot be determined yet
}


private struct AudioMenuButtonLabelView<Model: AudioMenuButtonLabelViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    
    private var displayedAudioOption: OlvidCallAudioOption? {
        model.currentAudioOptions.first
    }
    
    private var displayedIcon: OlvidCallAudioOption.IconKind {
        if model.isSpeakerEnabled {
            return .sf(.speakerWave3Fill)
        } else {
            return displayedAudioOption?.icon ?? .sf(.speakerWave3Fill)
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(model.isSpeakerEnabled ? Color(UIColor.systemRed) : Color(UIColor.systemFill))
            switch displayedIcon {
            case .sf(let systemIcon):
                Image(systemIcon: systemIcon)
                    .font(Constants.inCallImageFont)
                    .foregroundStyle(.white)
            case .png(let filename):
                Image(filename)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundColor(.white)
                    .frame(width: Constants.inCallImagePngSize, height: Constants.inCallImagePngSize)
            }
        }
    }
    
}


// MARK: Local constants for the views

private struct Constants {
    
    /// Width of the frame of all the buttons shown during a call (e.g., the end call button and the mute button).
    static let inCallButtonFrameWidth: CGFloat = 64
    
    /// The buttons shown during a call show a title. This is its size.
    static let inCallButtonTextSize: CGFloat = 16
    
    /// For buttons that show a png instead of an SF symbol (like for the bluetooth image)
    static let inCallImagePngSize: CGFloat = 20
    
    /// The font used for SF symbol images contained in the buttons shown during a call
    static let inCallImageFont = Font.system(size: 20, weight: .semibold, design: .default)
    
    /// Height of the frame delimiting the frame around the text below the buttons shown during a call.
    /// Specifying this height allows to have an acceptable design whatever the number of lines that the text requires (1 or 2).
    static let inCallButtonTextFrameHeight: CGFloat = 42
    
}


// MARK: - Previews

struct OlvidCallView_Previews: PreviewProvider {
    
    private static let cryptoIds: [ObvCryptoId] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
    ]
    
    private final class CallParticipantModelForPreviews: OlvidCallParticipantViewModelProtocol {
        var uuidForCallKit: UUID { UUID() }        
        var cryptoId: ObvTypes.ObvCryptoId
        var stateLocalizedDescription: String
        let showRemoveParticipantButton: Bool
        let displayName: String
        let circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration
        var contactIsMuted: Bool
        init(cryptoId: ObvTypes.ObvCryptoId, showRemoveParticipantButton: Bool, displayName: String, stateLocalizedDescription: String, circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration, contactIsMuted: Bool) {
            self.showRemoveParticipantButton = showRemoveParticipantButton
            self.displayName = displayName
            self.stateLocalizedDescription = stateLocalizedDescription
            self.circledInitialsConfiguration = circledInitialsConfiguration
            self.contactIsMuted = contactIsMuted
            self.cryptoId = cryptoId
        }
    }
    
    private final class ModelForPreviews: OlvidCallViewModelProtocol {
        let dateWhenCallSwitchedToInProgress: Date? = Date.now
        var direction: OlvidCall.Direction { .outgoing }
        let ownedCryptoId = OlvidCallView_Previews.cryptoIds[0]
        let availableAudioOptions: [OlvidCallAudioOption]?
        var currentAudioOptions: [OlvidCallAudioOption]
        @Published var isSpeakerEnabled: Bool
        let uuidForCallKit = UUID()
        let selfIsMuted: Bool
        let otherParticipants: [CallParticipantModelForPreviews]
        let localUserStillNeedsToAcceptOrRejectIncomingCall: Bool
        init(selfIsMuted: Bool, otherParticipants: [CallParticipantModelForPreviews], localUserStillNeedsToAcceptOrRejectIncomingCall: Bool, availableAudioOptions: [OlvidCallAudioOption]?) {
            self.otherParticipants = otherParticipants
            self.selfIsMuted = selfIsMuted
            self.localUserStillNeedsToAcceptOrRejectIncomingCall = localUserStillNeedsToAcceptOrRejectIncomingCall
            self.availableAudioOptions = availableAudioOptions
            self.currentAudioOptions = [availableAudioOptions!.first!]
            self.isSpeakerEnabled = false
        }
        func userWantsToActivateAudioOption(_ audioOption: OlvidCallAudioOption) async throws {}
        func userWantsToChangeSpeaker(to isSpeakerEnabled: Bool) async throws {
            self.isSpeakerEnabled = isSpeakerEnabled
        }
    }
    
    private static let model = ModelForPreviews(
        selfIsMuted: false,
        otherParticipants: [
            .init(cryptoId: cryptoIds[0],
                  showRemoveParticipantButton: true,
                  displayName: "Thomas Baignères",
                  stateLocalizedDescription: "Some s0tate",
                  circledInitialsConfiguration: .contact(
                    initial: "S",
                    photo: nil,
                    showGreenShield: false,
                    showRedShield: false,
                    cryptoId: cryptoIds[0],
                    tintAdjustementMode: .normal),
                  contactIsMuted: true),
            .init(cryptoId: cryptoIds[1],
                  showRemoveParticipantButton: true,
                  displayName: "Tim Cooks",
                  stateLocalizedDescription: "Some other state",
                  circledInitialsConfiguration: .contact(
                    initial: "T",
                    photo: nil,
                    showGreenShield: false,
                    showRedShield: false,
                    cryptoId: cryptoIds[1],
                    tintAdjustementMode: .normal),
                  contactIsMuted: false),
        ],
        localUserStillNeedsToAcceptOrRejectIncomingCall: false,
        availableAudioOptions: [
            OlvidCallAudioOption.builtInSpeaker(),
            OlvidCallAudioOption.forPreviews(portType: .headphones, portName: "Headphones"),
            //OlvidCallAudioOption.forPreviews(portType: .airPlay, portName: "Airplay"),
        ])
    
    private final class ActionsForPreviews: OlvidCallViewActionsProtocol {
        func userWantsToRemoveParticipant(uuidForCallKit: UUID, participantToRemove: ObvCryptoId) async throws {}
        func userWantsToAddParticipantsToExistingCall(uuidForCallKit: UUID, participantsToAdd: Set<ObvTypes.ObvCryptoId>) async throws {}
        func userWantsToSetMuteSelf(uuidForCallKit: UUID, muted: Bool) async throws {}
        func userWantsToEndOngoingCall(uuidForCallKit: UUID) async throws {}
        func userAcceptedIncomingCall(uuidForCallKit: UUID) async {}
        func userRejectedIncomingCall(uuidForCallKit: UUID) async {}
        func userWantsToAddParticipantToCall() {}
        func userWantsToMuteSelf() {}
    }
    
    
    private final class NavigationActionsForPreviews: OlvidCallViewNavigationActionsProtocol {
        func userWantsToAddParticipantToCall(ownedCryptoId: ObvTypes.ObvCryptoId, currentOtherParticipants: Set<ObvTypes.ObvCryptoId>) async -> Set<ObvCryptoId> {
            return Set([])
        }
    }
    
    private static let actions = ActionsForPreviews()
    private static let navigationActions = NavigationActionsForPreviews()

    
    static var previews: some View {
        OlvidCallView(model: model, actions: actions, navigationActions: navigationActions)
            .environment(\.locale, .init(identifier: "fr"))
    }
    
}
