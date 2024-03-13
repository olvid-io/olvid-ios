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

import Foundation
import SwiftUI
import WebRTC
import ObvTypes
import UI_ObvCircledInitials
import UI_SystemIcon


protocol OlvidCallParticipantViewModelProtocol: ObservableObject, Identifiable, InitialCircleViewNewModelProtocol, ActionButtonsModelProtocol {

    var displayName: String { get }
    var stateLocalizedDescription: String { get }
    var state: OlvidCallParticipant.State { get }
    var contactIsMuted: Bool { get }
    var cryptoId: ObvCryptoId { get }
    
    var remoteCameraVideoTrackIsEnabled: Bool { get }
    var remoteScreenCastVideoTrackIsEnabled: Bool { get }
    var remoteCameraVideoTrack: RTCVideoTrack? { get }
    var remoteScreenCastVideoTrack: RTCVideoTrack? { get }
    
}


protocol OlvidCallParticipantViewActionsProtocol {
    func userWantsToRemoveParticipant(participantToRemove: ObvCryptoId) async throws
    func userWantsToChatWithParticipant(_ participant: ObvCryptoId) async throws
}

/// Encapsulates view parameters that cannot be easily implemented at the model level (i.e., by an `OlvidCallParticipant`, that will implement `OlvidCallParticipantViewModelProtocol`)
/// but that can easily be computed par the `OlvidCallView`.
struct OlvidCallParticipantViewState {
    let size: OlvidCallParticipantViewSize
    let showVideoContentModeToggleButton: Bool
    let paddingBellowParticipantName: CGFloat // >0 when there is 1 participant, with video enabled, when the bottom sheet is shown
    let viewIsFullScreen: Bool
}


// MARK: - OlvidCallParticipantView

enum OlvidCallParticipantViewSize {
    case xsmall
    case small
    case large
    case xlarge
    case fixedSize(_ size: CGSize)
}

struct OlvidCallParticipantView<Model: OlvidCallParticipantViewModelProtocol>: View {
        
    @ObservedObject var model: Model
    let state: OlvidCallParticipantViewState
    let actions: OlvidCallParticipantViewActionsProtocol?

    /// Custom environment key set by the top level view
    @Environment(\.callViewSafeAreaInsets) private var callViewSafeAreaInsets
    
    @State private var userPreferredVideoContentMode: UIView.ContentMode?
    
    private var orientation: CallViewOrientation {
        switch state.size {
        case .small, .xsmall: return .horizontal
        case .large, .xlarge, .fixedSize: return .vertical
        }
    }
    
    
    private var textAlignment: HorizontalAlignment {
        switch orientation {
        case .vertical: return .center
        case .horizontal: return .leading
        }
    }
    
    private var circleDiameter: CGFloat {
        switch state.size {
        case .small, .xsmall: return 56.0
        case .large, .xlarge, .fixedSize: return 100.0
        }
    }
    
    private var frameMaxWidth: CGFloat? {
        switch state.size {
        case .xsmall, .small, .large, .xlarge:
            return .infinity
        case .fixedSize(let size):
            return size.width
        }
    }

    private var frameMaxHeight: CGFloat? {
        switch state.size {
        case .small, .xsmall:
            return nil
        case .large, .xlarge: 
            return .infinity
        case .fixedSize(let size):
            return size.height
        }
    }
    
    private var displayNameFont: Font {
        switch state.size {
        case .xsmall: return .body
        case .small: return .title2
        case .large, .xlarge, .fixedSize: return .title
        }
    }
    
    private var displayNameFontWeight: Font.Weight {
        switch state.size {
        case .large, .xlarge, .fixedSize: return .heavy
        case .small, .xsmall: return .medium
        }
    }
    
    private var sizeIsLargeEnoughToDisplayVideo: Bool {
        switch state.size {
        case .large, .xlarge, .fixedSize: return true
        case .small, .xsmall: return false
        }
    }
    
    
    private var sizeIsXsmall: Bool {
        switch state.size {
        case .xsmall: return true
        default: return false
        }
    }

    private var sizeIsSmall: Bool {
        switch state.size {
        case .small: return true
        default: return false
        }
    }

    private var sizeIsXlarge: Bool {
        switch state.size {
        case .xlarge: return true
        default: return false
        }
    }
    
    private var sizeIsFixed: Bool {
        switch state.size {
        case .fixedSize: return true
        default: return false
        }
    }
    
    private var fontForNameOnVideoView: Font {
        switch state.size {
        case .xsmall, .small, .large:
            return .body
        case .xlarge, .fixedSize:
            return .title2
        }
    }
    

    private var defaultVideoContentMode: UIView.ContentMode {
        if model.remoteScreenCastVideoTrackIsEnabled { return .scaleAspectFit }
        return .scaleAspectFill
    }
    
    
    private func userWantsToToggleVideoContentMode() {
        if userPreferredVideoContentMode == .scaleAspectFit {
            userPreferredVideoContentMode = .scaleAspectFill
        } else {
            userPreferredVideoContentMode = .scaleAspectFit
        }
    }
    
    
    private var toggleVideoContentModeButtonImage: SystemIcon {
        let currentContentMode = userPreferredVideoContentMode ?? defaultVideoContentMode
        if currentContentMode == .scaleAspectFill {
            return .arrowDownRightAndArrowUpLeft
        } else {
            return .arrowUpLeftAndArrowDownRight
        }
    }
    
    
    private var offsetOfCallButon: CGSize {
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            return .init(width: -16, height: 16)
        } else {
            switch state.size {
            case .xsmall, .small, .large:
                return .init(width: -16, height: 16)
            case .xlarge, .fixedSize:
                return .init(width: -8, height: 32)
            }
        }
    }
    
    
    private var offsetForNameOnVideoView: CGSize {
        if state.viewIsFullScreen {
            return .init(width: 8, height: -8 - callViewSafeAreaInsets.bottom - state.paddingBellowParticipantName)
        } else {
            return .init(width: 8, height: -8 - state.paddingBellowParticipantName)
        }
    }
    
    
    private enum RemoteVideoTrackToShow {
        case video(track: RTCVideoTrack)
        case screenCast(track: RTCVideoTrack)
        case none
    }
    
    
    /// Returns the video track that is appropriate to show, `.none` otherwise.
    ///
    /// This is used to determine if we should show the remote video.
    /// If this is the case, this is also used to hide the initial circle view and other graphical elements.
    private var remoteVideoTrackToShow: RemoteVideoTrackToShow {
        guard sizeIsLargeEnoughToDisplayVideo else { return .none }
        guard model.state == .connected else { return .none }
        if let track = model.remoteScreenCastVideoTrack, model.remoteScreenCastVideoTrackIsEnabled {
            return .screenCast(track: track)
        } else if let track = model.remoteCameraVideoTrack, model.remoteCameraVideoTrackIsEnabled {
            return .video(track: track)
        } else {
            return .none
        }
    }
    

    var body: some View {
        
        ZStack {
            
            switch remoteVideoTrackToShow {

            case .none:
                
                VHStack(orientation: orientation) {
                    
                    InitialCircleViewNew(model: model, state: .init(circleDiameter: circleDiameter))
                        .overlay(alignment: .topTrailing) {
                            MuteView()
                                .opacity(model.contactIsMuted ? 1.0 : 0.0)
                        }
                    
                    VStack(alignment: textAlignment) {
                        
                        ScrollViewIf(orientation == .horizontal && !sizeIsXsmall, axes: .horizontal) {
                            Text(verbatim: model.displayName)
                                .font(displayNameFont)
                                .fontWeight(displayNameFontWeight)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        
                        if !sizeIsXsmall {
                            Text(verbatim: model.stateLocalizedDescription)
                                .font(.callout)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        
                    }
                    .padding(.leading, 4)
                    
                    if sizeIsXsmall {
                        Spacer()
                    }
                    
                    if let actions, (sizeIsSmall || sizeIsXsmall) {
                        ActionButtons(model: model, actions: actions)
                    }
                    
                }

            case .video(track: let track),
                 .screenCast(track: let track):
                
                ZStack(alignment: .bottomLeading) {
                    
                    OlvidCallVideoView(videoTrack: track, defaultVideoContentMode: defaultVideoContentMode, doMirrorView: false, userPreferredVideoContentMode: $userPreferredVideoContentMode)
                        .id(track.trackId) // Make sure we instanciate distinct OlvidCallVideoView for each track. Trying to reuse one view for two tracks leads to bugs
                        .clipped()
                        .if(sizeIsXlarge) { view in view.ignoresSafeArea() }
                        .overlay(alignment: .topTrailing) {
                            CallButton(action: userWantsToToggleVideoContentMode,
                                       systemIcon: toggleVideoContentModeButtonImage,
                                       background: .systemFill,
                                       size: 44,
                                       weight: .semibold)
                            .offset(offsetOfCallButon)
                            .opacity(state.showVideoContentModeToggleButton ? 1.0 : 0.0)
                        }
                    
                    NameOnVideoView(verbatim: model.displayName, preferredFont: fontForNameOnVideoView)
                        .overlay(MuteView()
                            .offset(x: Constants.muteViewSize/3, y: -Constants.muteViewSize/3)
                            .opacity(model.contactIsMuted ? 1.0 : 0.0), alignment: .topTrailing)
                        .offset(offsetForNameOnVideoView)
                    
                }

            }
            
        }
        .frame(maxWidth: frameMaxWidth, maxHeight: frameMaxHeight)
        .if(sizeIsSmall) { $0.padding(.all) }
        .background {
            Color(sizeIsXlarge || sizeIsXsmall ? .clear : .quaternarySystemFill)
        }
        .if(!sizeIsXlarge && !sizeIsXsmall && !sizeIsFixed) { view in
            view
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.tertiary, lineWidth: 1))
        }
        
    }
        
}


// MARK: - Buttons shown on each call participant row

protocol ActionButtonsModelProtocol {
    var cryptoId: ObvCryptoId { get } // the contact cryptoId
    var isOneToOne: Bool { get }
}


private struct ActionButtons: View {
    
    let model: ActionButtonsModelProtocol
    let actions: OlvidCallParticipantViewActionsProtocol
    
    private func userWantsToRemoveParticipant() {
        Task {
            do {
                try await actions.userWantsToRemoveParticipant(participantToRemove: model.cryptoId)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func userWantsToChatWithParticipant() {
        Task {
            do {
                guard model.isOneToOne else { return }
                try await actions.userWantsToChatWithParticipant(model.cryptoId)
            } catch {
                assertionFailure()
            }
        }
    }
    


    var body: some View {
    
        HStack {

            if model.isOneToOne {
                Button(action: {}) {
                    Image(systemIcon: .bubbleLeft)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                        .font(.system(size: 24))
                }
                .padding(.leading, 4)
                // We do not use the action of the button, due to a strange behaviour of a SwiftUI list cell if we do:
                // tapping anywhere on the cell activate the button.
                .onTapGesture(perform: userWantsToChatWithParticipant)
            }

        }
        
    }
    
}


// MARK: - Small mute icon shown when the participant is muted

private struct MuteView: View {
    var body: some View {
        Image(systemIcon: .micSlashFill)
            .foregroundStyle(Color(UIColor.white))
            .font(.system(size: 12, weight: .semibold))
            .frame(width: Constants.muteViewSize, height: Constants.muteViewSize)
            .background(Color(UIColor.systemRed))
            .clipShape(Circle())
    }
}



// MARK: - VHStack view

private struct VHStack<Content: View>: View {

    let orientation: CallViewOrientation
    let spacing: CGFloat?
    
    let content: Content

    init(orientation: CallViewOrientation, spacing: CGFloat? = nil, @ViewBuilder _ content: () -> Content) {
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


// MARK: - Video view

struct OlvidCallVideoView: UIViewRepresentable {
    
    let videoTrack: RTCVideoTrack
    let defaultVideoContentMode: UIView.ContentMode
    let doMirrorView: Bool
    @Binding var userPreferredVideoContentMode: UIView.ContentMode?
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let rtcmtlVideoView = RTCMTLVideoView(frame: .zero)
        videoTrack.add(rtcmtlVideoView)
        rtcmtlVideoView.videoContentMode = userPreferredVideoContentMode ?? defaultVideoContentMode
        if doMirrorView {
            rtcmtlVideoView.transform = .init(scaleX: -1, y: 1)
        }
        return rtcmtlVideoView
    }
    
    /// When taps on the button allowing to toggle between the two possible ``ContentMode``,
    /// this method is called, allowing to update the `videoContentMode` of the ``RTCMTLVideoView``
    /// thanks to the ``userPreferredVideoContentMode`` binding.
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.videoContentMode = userPreferredVideoContentMode ?? defaultVideoContentMode
    }
    
}


// MARK: Contants

fileprivate struct Constants {
    static let muteViewSize: CGFloat = 24.0
}



// MARK: - Previews

struct OlvidCallParticipantView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    private static let contactCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)

    private final class ModelForPreviews: OlvidCallParticipantViewModelProtocol {
        
        let remoteCameraVideoTrackIsEnabled = false
        let remoteScreenCastVideoTrackIsEnabled = false
        var remoteCameraVideoTrack: RTCVideoTrack? { nil }
        var remoteScreenCastVideoTrack: RTCVideoTrack? { nil }
                
        var cryptoId: ObvTypes.ObvCryptoId { contactCryptoId }
        let isOneToOne = true

        var circledInitialsConfiguration: CircledInitialsConfiguration {
            .contact(initial: "S",
                     photo: nil,
                     showGreenShield: false,
                     showRedShield: false,
                     cryptoId: contactCryptoId,
                     tintAdjustementMode: .normal)
        }
        
        var displayName: String {
            "Steve Jobs"
        }
        
        var stateLocalizedDescription: String {
            "Some description"
        }
        
        var state: OlvidCallParticipant.State {
            .connected
        }
                
        @Published var contactIsMuted: Bool = false
        
        var uuidForCallKit: UUID { UUID() }
        
    }
    
    
    private final class ActionsForPreviews: OlvidCallParticipantViewActionsProtocol {
        func userWantsToChatWithParticipant(_ participant: ObvTypes.ObvCryptoId) async throws {}
        func userWantsToRemoveParticipant(participantToRemove: ObvCryptoId) async throws {}
    }
    
    private static let model = ModelForPreviews()
    private static let actions = ActionsForPreviews()
    private static let stateWithLargeSize = OlvidCallParticipantViewState(size: .large, showVideoContentModeToggleButton: true, paddingBellowParticipantName: 0, viewIsFullScreen: true)
    private static let stateWithSmallSize = OlvidCallParticipantViewState(size: .small, showVideoContentModeToggleButton: true, paddingBellowParticipantName: 0, viewIsFullScreen: false)
    private static let stateWithXSmallSize = OlvidCallParticipantViewState(size: .xsmall, showVideoContentModeToggleButton: true, paddingBellowParticipantName: 0, viewIsFullScreen: false)

    static var previews: some View {
        OlvidCallParticipantView(model: model, state: stateWithLargeSize, actions: actions)
            .previewDisplayName("XLarge")
        VStack(spacing: 8) {
            OlvidCallParticipantView(model: model, state: stateWithLargeSize, actions: actions)
            OlvidCallParticipantView(model: model, state: stateWithLargeSize, actions: actions)
        }
        .previewDisplayName("Large")
        OlvidCallParticipantView(model: model, state: stateWithSmallSize, actions: actions)
            .previewDisplayName("Small")
        OlvidCallParticipantView(model: model, state: stateWithXSmallSize, actions: actions)
            .previewDisplayName("XSmall")
    }
    
}
