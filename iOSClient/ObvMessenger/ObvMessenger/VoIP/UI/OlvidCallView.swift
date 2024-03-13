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
import ObvUICoreData


protocol OlvidCallViewModelProtocol: ObservableObject, BottomSheetViewModelProtocol, AcceptOrRejectButtonsViewModelProtocol, OtherParticipantsViewModelProtocol, SidebarViewModelProtocol, DetailsViewModelProtocol {
    var ownedCryptoId: ObvCryptoId { get }
    var otherParticipants: [OlvidCallParticipantViewModel] { get }
    var state: OlvidCall.State { get }
    var uuidForCallKit: UUID { get }
    var direction: OlvidCall.Direction { get }
    var dateWhenCallSwitchedToInProgress: Date? { get }
    var localUserStillNeedsToAcceptOrRejectIncomingCall: Bool { get }
    var atLeastOneOtherParticipantHasCameraEnabled: Bool { get }
    var doMirrorViewSelfVideoView: Bool { get }
}


protocol OlvidCallViewActionsProtocol: AcceptOrRejectButtonsViewActionsProtocol, BottomSheetViewActionsProtocol, SidebarViewActionsProtocol, DetailsViewActionsProtocol {
    func callViewDidDisappear(uuidForCallKit: UUID) async
    func callViewDidAppear(uuidForCallKit: UUID) async
}


/// In practice, this is implemented by the hosting view controller in order to show the flow allowing the user to choose call participants to add
protocol OlvidCallAddParticipantsActionsProtocol: AnyObject {
    func userWantsToAddParticipantToCall(ownedCryptoId: ObvCryptoId, currentOtherParticipants: Set<ObvCryptoId>) async -> Set<ObvCryptoId>
}


struct OlvidCallView<Model: OlvidCallViewModelProtocol>: View {
    
    @Environment(\.callViewSafeAreaInsets) var callViewSafeAreaInsets
    @ObservedObject var model: Model
    let actions: OlvidCallViewActionsProtocol
    let chooseParticipantsToAddAction: OlvidCallAddParticipantsActionsProtocol

    @State private var callDuration: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

    private let dateFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.second, .minute, .hour]
        return f
    }()

    var body: some View {
        GeometryReader { geometry in
            if ObvMessengerConstants.targetEnvironmentIsMacCatalyst || UIDevice.current.userInterfaceIdiom == .pad {
                OlvidCallViewForMacOS(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction, callDuration: $callDuration)
                    .onReceive(timer) { (_) in
                        refreshCallDuration()
                    }
                    .onAppear {
                        Task { await actions.callViewDidAppear(uuidForCallKit: model.uuidForCallKit) }
                    }
                    .onDisappear {
                        Task { await actions.callViewDidDisappear(uuidForCallKit: model.uuidForCallKit) }
                    }
                    .environment(\.callViewSafeAreaInsets, geometry.safeAreaInsets)
                    .environment(\.callViewRatioZoomCompensation, UIScreen.main.nativeScale != 0 ? UIScreen.main.scale / UIScreen.main.nativeScale : 1.0)
            } else {
                OlvidCallViewForIOS(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction, callDuration: $callDuration)
                    .onReceive(timer) { (_) in
                        refreshCallDuration()
                    }
                    .onAppear {
                        Task { await actions.callViewDidAppear(uuidForCallKit: model.uuidForCallKit) }
                    }
                    .onDisappear {
                        Task { await actions.callViewDidDisappear(uuidForCallKit: model.uuidForCallKit) }
                    }
                    .environment(\.callViewSafeAreaInsets, geometry.safeAreaInsets)
                    .environment(\.callViewRatioZoomCompensation, UIScreen.main.nativeScale != 0 ? UIScreen.main.scale / UIScreen.main.nativeScale : 1.0)
            }
        }
    }
    
}


struct OlvidCallViewForMacOS<Model: OlvidCallViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: OlvidCallViewActionsProtocol
    let chooseParticipantsToAddAction: OlvidCallAddParticipantsActionsProtocol
    @Binding var callDuration: String?


    var body: some View {
        if #available(iOS 16.0, *) {
                NavigationSplitView {
                    SidebarView(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction, callDuration: $callDuration)
                } detail: {
                    DetailsView(model: model, actions: actions, callDuration: $callDuration)
                }
        } else {
            HStack {
                SidebarView(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction, callDuration: $callDuration)
                    .frame(width: 370)
                    .padding(.top, 48)
                DetailsView(model: model, actions: actions, callDuration: $callDuration)
            }
        }
        
    }
    
}


// MARK: - DetailsView

protocol DetailsViewModelProtocol: ObservableObject, AcceptOrRejectButtonsViewModelProtocol, OngoingCallButtonsViewModelProtocol {
    associatedtype OlvidCallParticipantViewModel: OlvidCallParticipantViewModelProtocol
    associatedtype InitialCircleViewNewModel: InitialCircleViewNewModelProtocol
    var otherParticipants: [OlvidCallParticipantViewModel] { get }
    var currentCameraPosition: AVCaptureDevice.Position? { get }
    var localPreviewVideoTrack: RTCVideoTrack? { get }
    var selfVideoSize: CGSize? { get }
    var localUserStillNeedsToAcceptOrRejectIncomingCall: Bool { get }
    var ownedInitialCircle: InitialCircleViewNewModel { get }
    var doMirrorViewSelfVideoView: Bool { get }
}


protocol DetailsViewActionsProtocol: AcceptOrRejectButtonsViewActionsProtocol, OngoingCallButtonsViewActionsProtocol {
    
}

/// View used on macOS to show all the participants views
private struct DetailsView<Model: DetailsViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: DetailsViewActionsProtocol
    @Binding var callDuration: String?

    @State private var showVideoContentModeToggleButton = true
    
    init(model: Model, actions: DetailsViewActionsProtocol, callDuration: Binding<String?>) {
        self.model = model
        self.actions = actions
        self._callDuration = callDuration
    }
    
    /// State common to all `OlvidCallParticipantView` instances displayed by this view
    private func callParticipantViewState(itemSize: CGSize) -> OlvidCallParticipantViewState {
        return .init(size: .fixedSize(itemSize),
                     showVideoContentModeToggleButton: showVideoContentModeToggleButton, 
                     paddingBellowParticipantName: 0, 
                     viewIsFullScreen: false)
    }

    private var callParticipantViewSize: OlvidCallParticipantViewSize {
        switch model.otherParticipants.count {
        case 1: return .xlarge
        case 2: return .large
        default: return .small
        }
    }
    
    private var columns = [
        GridItem(.adaptive(minimum: 300), spacing: 8),
        GridItem(.adaptive(minimum: 300), spacing: 8),
    ]
    
    private let buttonStackHeight: CGFloat = 100
    

    private func indexOf(_ participant: Model.OlvidCallParticipantViewModel) -> Int {
        return model.otherParticipants.firstIndex(where: { $0.id == participant.id }) ?? 0
    }
        
    private var numberOfItems: Int {
        model.otherParticipants.count + 1
    }
    
    private var numberOfColumns: Int {
        Int(ceil(sqrt(Double(numberOfItems))))
    }
    
    private var numberOfRows: Int {
        return 1 + (numberOfItems-1)/numberOfColumns
    }
    
    private func widthAvailable(for geometry: GeometryProxy) -> CGFloat {
        let widthAvailable = max(0, geometry.size.width)
        return widthAvailable
    }
    
    private func heightAvailable(for geometry: GeometryProxy) -> CGFloat {
        let heightAvailable = max(0, geometry.size.height - buttonStackHeight)
        return heightAvailable
    }

    private func widthOfItem(geometry: GeometryProxy) -> CGFloat {
        let widthAvailable = widthAvailable(for: geometry)
        guard widthAvailable > 0 else { return 0 }
        let width = widthAvailable / CGFloat(numberOfColumns)
        return width
    }
    
    private func heightOfItem(geometry: GeometryProxy) -> CGFloat {
        let heightAvailable = heightAvailable(for: geometry)
        guard heightAvailable > 0 else { return .zero }
        let height = heightAvailable / CGFloat(numberOfRows)
        return height
    }
    
    private func itemSize(geometry: GeometryProxy) -> CGSize {
        return .init(width: widthOfItem(geometry: geometry), height: heightOfItem(geometry: geometry))
    }
        
    private func itemOffset(at index: Int, geometry: GeometryProxy) -> CGSize {
        guard index >= 0 && index < numberOfItems else { assertionFailure(); return .zero }
        guard numberOfColumns > 0 else { assertionFailure(); return .zero }
        let i = index % numberOfColumns
        let j = (index - i) / numberOfColumns
        let itemSize = itemSize(geometry: geometry)
        let originX = CGFloat(i) * itemSize.width
        let originY = CGFloat(j) * itemSize.height
        let centerX = originX + itemSize.width / 2
        let centerY = originY + itemSize.height / 2
        let x = centerX - widthAvailable(for: geometry) / 2
        let y = centerY - heightAvailable(for: geometry) / 2
        return .init(width: x, height: y)
    }
    
    
    private func tapGesturePerformedOnOlvidCallParticipantView() {
        withAnimation {
            showVideoContentModeToggleButton.toggle()
        }
    }
    
    
    private var defaultSelfVideoContentMode: AVLayerVideoGravity {
        .resizeAspect
    }
    
    
    var body: some View {
                
        GeometryReader { geometry in
            
            VStack {
                
                ZStack(alignment: .center) {
                      
                    let itemSize = itemSize(geometry: geometry)
                    let callParticipantViewState = callParticipantViewState(itemSize: itemSize)
                    
                    ForEach(model.otherParticipants) { participant in
                        OlvidCallParticipantView(
                            model: participant,
                            state: callParticipantViewState,
                            actions: nil)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: tapGesturePerformedOnOlvidCallParticipantView)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding()
                        .frame(width: itemSize.width, height: itemSize.height)
                        .offset(itemOffset(at: indexOf(participant), geometry: geometry))
                    }
                    
                    ZStack {
                        Color(UIColor.secondarySystemFill)
                        VStack {
                            InitialCircleViewNew(model: model.ownedInitialCircle, state: .init(circleDiameter: 100))
                            Text("YOU")
                                .font(.title)
                                .fontWeight(.heavy)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        if model.currentCameraPosition != nil {
                            ZStack {
                                Color(UIColor.secondarySystemBackground)
                                ProgressView()
                                if let localPreviewVideoTrack = model.localPreviewVideoTrack {
                                    ZStack(alignment: .bottomLeading) {
                                        OlvidCallVideoView(videoTrack: localPreviewVideoTrack,
                                                           defaultVideoContentMode: .scaleAspectFit,
                                                           doMirrorView: model.doMirrorViewSelfVideoView,
                                                           userPreferredVideoContentMode: .constant(nil))
                                        NameOnVideoView(verbatim: NSLocalizedString("YOU", comment: ""), preferredFont: .title2)
                                            .offset(x: 20, y: -20)
                                    }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding()
                    .frame(width: itemSize.width, height: itemSize.height)
                    .offset(itemOffset(at: model.otherParticipants.count, geometry: geometry))

                }
                .frame(width: widthAvailable(for: geometry), height: heightAvailable(for: geometry))
                
                Spacer()
                
                ZStack {
                    AcceptOrRejectButtonsView(model: model, actions: actions)
                        .opacity(model.localUserStillNeedsToAcceptOrRejectIncomingCall ? 1.0 : 0.0)
                    OngoingCallButtonsView(model: model, actions: actions)
                        .opacity(model.localUserStillNeedsToAcceptOrRejectIncomingCall ? 0.0 : 1.0)
                }
                .frame(height: buttonStackHeight)
                .padding(.bottom)

            }
                        
        }

    }
    
}


struct NameOnVideoView: View {
    
    let verbatim: String
    let preferredFont: Font?
    
    var body: some View {
        Text(verbatim: verbatim)
            .font(preferredFont ?? .title2)
            .foregroundStyle(Color.white)
            .if(preferredFont == .title2) { $0.padding() }
            .if(preferredFont != .title2) {
                $0.padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background {
                ObvVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
                    .clipShape(RoundedRectangle(cornerRadius: preferredFont == .title2 ? 12 : 8, style: .continuous))
            }
    }
}


/// Main view used when displaying a call to the user.
private struct OlvidCallViewForIOS<Model: OlvidCallViewModelProtocol>: View, OtherParticipantsViewActionsProtocol {
            
    @ObservedObject var model: Model
    let actions: OlvidCallViewActionsProtocol
    let chooseParticipantsToAddAction: OlvidCallAddParticipantsActionsProtocol
    @Binding var callDuration: String?

    @State private var userWantsToDismissSheet = false
    @State private var deviceOrientationInfo = ObvSimpleDeviceOrientationInfo()

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    
    /// When we one or two participants, we want to make it possible to dismiss the bottom sheet.
    /// If the sheet *must* be shown, this tap has (almost) no effect.
    /// Otherwise, we toggle the `userWantsToDismissSheet` propery. This will refresh the view, that will
    /// use a fresh value of the `isSheetPresented` propery.
    func tapGesturePerformedOnFirstOrSecondParticipant() {
        if mustShowSheet {
            if userWantsToDismissSheet {
                withAnimation {
                    userWantsToDismissSheet = false
                }
            }
        } else {
            withAnimation {
                userWantsToDismissSheet.toggle()
            }
        }
    }
    
    
    /// This property returns `true` if the sheet *must* be shown, independently of the user choice.
    private var mustShowSheet: Bool {
        
        // If the vertical size class is compact, we cannot require the sheet to be shown as there is not enough room for it.
        if verticalSizeClass == .compact { return false }

        // If the number of participants is larger than 2, or if the user still needs to accept a call, or if no other participant is streaming her video,
        // we must show the sheet (when the vertical size class is not compact)
        if model.otherParticipants.count > 2 || model.localUserStillNeedsToAcceptOrRejectIncomingCall || !model.atLeastOneOtherParticipantHasCameraEnabled {
            return true
        }

        return false
        
    }

    
    /// When the value of `userWantsToDismissSheet` changes, this method is called by the interface to determine if the sheet should be dismissed or not.
    private var isSheetPresented: Bool {
        if mustShowSheet { return true }
        // We never show the sheet when the vertical size class is comptact, as there isn't enough room for it.
        if verticalSizeClass == .compact { return false }
        // If we reach this point, we can honour the decision of the user to dismiss/show the bottom sheet
        return !userWantsToDismissSheet
    }
    
    
    /// Called whenever more than 2 participants are shown. In that case, we want to make sure that the sheet is shown when appropriate.
    func moreThanTwoParticipantsDidAppear() {
        userWantsToDismissSheet = false
    }


    func userWantsToChangeVideoCameraPosition() {
        Task {
            do {
                let currentPosition = model.currentCameraPosition ?? .front
                let preferredPosition: AVCaptureDevice.Position
                switch currentPosition {
                case .unspecified, .back:
                    preferredPosition = .front
                case .front:
                    preferredPosition = .back
                @unknown default:
                    preferredPosition = .front
                }
                try await actions.userWantsToStartOrStopVideoCamera(uuidForCallKit: model.uuidForCallKit, start: model.localPreviewVideoTrack != nil, preferredPosition: preferredPosition)
            } catch {
                assertionFailure()
            }
        }
    }

    
    private let participantCountSmallLimit = 3
    
        
    private var topBlurEffectStyle: UIBlurEffect.Style {
        switch colorScheme {
        case .dark: return .systemChromeMaterialDark
        case .light: return .light
        @unknown default: return .dark
        }
    }
     
    
    private func selfVideoOffset(for geometry: GeometryProxy) -> CGSize? {
        guard let selfVideoViewSize else { return nil }
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            let x = geometry.size.width / 2 - selfVideoViewSize.width/2 - 8
            let y = geometry.size.height / 2 - selfVideoViewSize.height/2 - 8
            return .init(width: x, height: y)
        } else {
            let x = geometry.size.width / 2 - selfVideoViewSize.width/2 - 8
            if bottomSheetCanBeMadeAvailable {
                let detentToConsider = (isSheetPresented && verticalSizeClass == .regular) ? Constants.smallDetent : 0
                let y = geometry.size.height / 2 - selfVideoViewSize.height/2 - detentToConsider - 8
                return .init(width: x, height: y)
            } else {
                let detentToConsider = verticalSizeClass == .regular ? Constants.smallDetent : 0
                let y = geometry.size.height / 2 - selfVideoViewSize.height/2 - detentToConsider - 8
                return .init(width: x, height: y)
            }
        }
    }
    
    
    private var selfVideoViewSize: CGSize? {
        guard let selfVideoPreviewLayerRatio else { return nil }
        let sideSize: CGFloat
        if verticalSizeClass == .compact {
            sideSize = Constants.SelfVideoSize.small
        } else {
            sideSize = isSheetPresented ? Constants.SelfVideoSize.large : Constants.SelfVideoSize.small
        }
        return .init(width: sideSize * selfVideoPreviewLayerRatio, height: sideSize)
    }
    
    
    private var selfVideoPreviewLayerRatio: CGFloat? {
        guard let size = model.selfVideoSize else { return nil }
        switch deviceOrientationInfo.orientation {
        case .portrait:
            guard size.width != 0 else { assertionFailure(); return nil }
            return size.height / size.width
        case .landscape:
            guard size.height != 0 else { assertionFailure(); return nil }
            return size.width / size.height
        }
    }
    
    private var bottomSheetCanBeMadeAvailable: Bool {
        if #available(iOS 16.4, *) {
            return true
        } else {
            return false
        }
    }
    

    /// Only used under iOS before 16.4, when the user taps on the button allowing to add a participant. On recent iOS versions, this button is shown in the bottom sheet view instead.
    private func userWantsToAddParticipantToCall() {
        Task {
            let currentOtherParticipants = Set(model.otherParticipants.map({ $0.cryptoId }))
            let participantsToAdd = await chooseParticipantsToAddAction.userWantsToAddParticipantToCall(ownedCryptoId: model.ownedCryptoId, currentOtherParticipants: currentOtherParticipants)
            do {
                try await actions.userWantsToAddParticipantsToExistingCall(uuidForCallKit: model.uuidForCallKit, participantsToAdd: participantsToAdd)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    var body: some View {
        GeometryReader { geometry in
            
            ZStack {
                
                VStack {
                    OtherParticipantsView(model: model, actions: self, isSheetPresented: isSheetPresented)
                    if !model.localUserStillNeedsToAcceptOrRejectIncomingCall && verticalSizeClass != .compact && !bottomSheetCanBeMadeAvailable {
                        // Fallback view to display ongoing call buttons view under iOS < 16.4
                        OngoingCallButtonsView(model: model, actions: actions)
                    }
                }
                
                VStack {
                    CallDurationAndTitle(callDuration: callDuration)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                        .padding(.top, 4)
                        .if(model.otherParticipants.count != 1) { view in
                            view
                                .background {
                                    ObvVisualEffectView(effect: UIBlurEffect(style: topBlurEffectStyle))
                                        .ignoresSafeArea()
                                }
                        }
                    Spacer()
                }
                
                if model.localUserStillNeedsToAcceptOrRejectIncomingCall {
                    VStack {
                        Spacer()
                        AcceptOrRejectButtonsView(model: model, actions: actions)
                    }
                }
                
                if let selfVideoViewSize, let offset = selfVideoOffset(for: geometry), model.currentCameraPosition != nil {
                    ZStack {
                        Color(UIColor.systemFill)
                        ProgressView()
                        if let localPreviewVideoTrack = model.localPreviewVideoTrack {
                            OlvidCallVideoView(videoTrack: localPreviewVideoTrack,
                                               defaultVideoContentMode: .scaleAspectFit, 
                                               doMirrorView: model.doMirrorViewSelfVideoView,
                                               userPreferredVideoContentMode: .constant(nil))
                            .overlay(alignment: .bottomLeading) {
                                CallButton(action: userWantsToChangeVideoCameraPosition,
                                           systemIcon: .arrowTriangle2CirclepathCamera,
                                           background: .systemFill,
                                           size: 44,
                                           weight: .semibold)
                                .offset(x: 8, y: -8)
                                .opacity(isSheetPresented ? 1.0 : 0.0)
                            }
                        }
                    }
                    .frame(width: selfVideoViewSize.width, height: selfVideoViewSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: min(20, (selfVideoViewSize.width + selfVideoViewSize.height) / 14.0), style: .continuous))
                    .offset(offset)
                }
                
                // Under iOS < 16.4, add a button allowing to add new call participants (as there is no bottom sheet on these platforms)
                if model.direction == .outgoing && !model.localUserStillNeedsToAcceptOrRejectIncomingCall && verticalSizeClass != .compact && !bottomSheetCanBeMadeAvailable {
                    Button(action: userWantsToAddParticipantToCall) {
                        Image(systemIcon: .personCropCircleBadgePlus)
                            .font(.system(size: 22))
                    }
                    .frame(width: 44, height: 44)
                    .offset(x: -geometry.size.width/2 + 30, y: -geometry.size.height/2 + 16)
                }
                
            }
            .if(!model.localUserStillNeedsToAcceptOrRejectIncomingCall && verticalSizeClass != .compact && bottomSheetCanBeMadeAvailable) { view in
                view.sheet(isPresented: .constant(isSheetPresented)) {
                    if #available(iOS 16.4, *) {
                        BottomSheetView(model: model, callDuration: $callDuration, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction)
                            .presentationDetents([.height(Constants.smallDetent), .medium, .large])
                            .interactiveDismissDisabled()
                            .presentationDragIndicator(.visible)
                            .presentationBackgroundInteraction(.enabled)
                            .presentationCornerRadius(21)
                    } else {
                        // We do not expect this to happen, as bottomSheetCanBeMadeAvailable is false when iOS 16.4 is not available
                    }
                }
            }
            .onChange(of: verticalSizeClass) { verticalSizeClass in
                // Make sure the sheet is shown when rotating the screen back to a regular vertical size class
                userWantsToDismissSheet = false
            }
        }
    }
}


// MARK: - OtherParticipantsView

protocol OtherParticipantsViewModelProtocol: ObservableObject {
    associatedtype OlvidCallParticipantViewModel: OlvidCallParticipantViewModelProtocol
    var otherParticipants: [OlvidCallParticipantViewModel] { get }
}


protocol OtherParticipantsViewActionsProtocol {
    func tapGesturePerformedOnFirstOrSecondParticipant()
    func moreThanTwoParticipantsDidAppear()
}


/// Used under iOS only
private struct OtherParticipantsView<Model: OtherParticipantsViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: OtherParticipantsViewActionsProtocol
    let isSheetPresented: Bool

    @Environment(\.verticalSizeClass) var verticalSizeClass

    /// State common to all `OlvidCallParticipantView` instances displayed by this view
    private var callParticipantViewState: OlvidCallParticipantViewState {
        let paddingBellowParticipantName: CGFloat
        if model.otherParticipants.count > 1 {
            paddingBellowParticipantName = 0
        } else {
            paddingBellowParticipantName = isSheetPresented ? Constants.smallDetent : 0
        }
        return .init(size: callParticipantViewSize,
                     showVideoContentModeToggleButton: isSheetPresented,
                     paddingBellowParticipantName: paddingBellowParticipantName, 
                     viewIsFullScreen: model.otherParticipants.count == 1)
    }
    

    private var callParticipantViewSize: OlvidCallParticipantViewSize {
        switch model.otherParticipants.count {
        case 1: return .xlarge
        case 2: return .large
        default: return .small
        }
    }

    
    var body: some View {
        
        ScrollViewIf(model.otherParticipants.count > 2) {
            HStackOrVStack(useHStack: model.otherParticipants.count == 2 && verticalSizeClass == .compact) {
                
                if let firstParticipant = model.otherParticipants.first {
                    OlvidCallParticipantView(
                        model: firstParticipant,
                        state: callParticipantViewState,
                        actions: nil)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: actions.tapGesturePerformedOnFirstOrSecondParticipant)
                }
                
                if let secondParticipant = model.otherParticipants[safe: 1] {
                    OlvidCallParticipantView(
                        model: secondParticipant,
                        state: callParticipantViewState,
                        actions: nil)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: actions.tapGesturePerformedOnFirstOrSecondParticipant)
                }
                
                if model.otherParticipants.count > 2 {
                    ForEach(model.otherParticipants[2...]) { participant in
                        OlvidCallParticipantView(
                            model: participant,
                            state: callParticipantViewState,
                            actions: nil)
                        .onAppear(perform: actions.moreThanTwoParticipantsDidAppear)
                    }
                }
                
                if model.otherParticipants.count > 2 {
                    Spacer()
                }
                
            }
        }
        
        .if(model.otherParticipants.count == 1) { view in
            view.ignoresSafeArea()
        }
        .if(model.otherParticipants.count != 1) { view in
            view
                .padding(.top, 64)
                .padding(.horizontal)
                .padding(.bottom, isSheetPresented ? Constants.smallDetent + 8 : 0)
        }
        
    }
}


enum CallViewOrientation {
    case vertical
    case horizontal
}


// MARK: Bottom sheet view

protocol BottomSheetViewActionsProtocol: OngoingCallButtonsViewActionsProtocol, ListOfOtherParticipantsViewActionsProtocol, AddParticipantButtonViewActionsProtocol {
    func userWantsToAddParticipantsToExistingCall(uuidForCallKit: UUID, participantsToAdd: Set<ObvCryptoId>) async throws
}


protocol BottomSheetViewModelProtocol: ObservableObject, OngoingCallButtonsViewModelProtocol, OngoingCallDurationViewModelProtocol, ListOfOtherParticipantsViewModelProtocol, AddParticipantButtonViewModel {
    associatedtype BottomSheetParticipantViewModel: OlvidCallParticipantViewModelProtocol
    var otherParticipants: [BottomSheetParticipantViewModel] { get }
}


private struct BottomSheetView<Model: BottomSheetViewModelProtocol>: View {

    @ObservedObject var model: Model
    @Binding var callDuration: String?
    let actions: BottomSheetViewActionsProtocol
    let chooseParticipantsToAddAction: OlvidCallAddParticipantsActionsProtocol
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .center) {

                OngoingCallButtonsView(model: model, actions: actions)
                    .padding(.top, Constants.spaceAboveCallButtonsStack)

                VStack {

                    OngoingCallDurationView(model: model, callDuration: $callDuration)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    VStack {
                        
                        Divider()
                            .padding()
                        
                        if model.direction == .outgoing {
                            AddParticipantButtonView(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction)
                        }
                        
                        ListOfOtherParticipantsView(model: model, actions: actions)
                        
                        Spacer()
                    }
                    
                }
                .opacity(geometry.size.height <= Constants.smallDetent ? 0 : 1)
            }
            .ignoresSafeArea()
        }
        //.preferredColorScheme(.dark)
    }
    
}


// MARK: -

protocol SidebarViewModelProtocol: ObservableObject, OngoingCallDurationViewModelProtocol, AddParticipantButtonViewModel, ListOfOtherParticipantsViewModelProtocol {
    
}


protocol SidebarViewActionsProtocol: AddParticipantButtonViewActionsProtocol, ListOfOtherParticipantsViewActionsProtocol {
    
}


private struct SidebarView<Model: SidebarViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: SidebarViewActionsProtocol
    let chooseParticipantsToAddAction: OlvidCallAddParticipantsActionsProtocol
    @Binding var callDuration: String?

    var body: some View {
        
        VStack {
            
            OngoingCallDurationView(model: model, callDuration: $callDuration)
                .padding(.horizontal)
                .padding(.top)
            
            Divider()
                .padding()
            
            if model.direction == .outgoing {
                AddParticipantButtonView(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction)
            }
            
            ListOfOtherParticipantsView(model: model, actions: actions)
            
            Spacer()

        }
        
    }
    
}


// MARK: - ListOfOtherParticipantsView

protocol ListOfOtherParticipantsViewActionsProtocol {
    func userWantsToRemoveParticipant(uuidForCallKit: UUID, participantToRemove: ObvCryptoId) async throws
    func userWantsToEndOngoingCall(uuidForCallKit: UUID) async throws
    func userWantsToChatWithParticipant(uuidForCallKit: UUID, participant: ObvCryptoId) async throws
}


protocol ListOfOtherParticipantsViewModelProtocol: ObservableObject {
    associatedtype OlvidCallParticipantViewModel: OlvidCallParticipantViewModelProtocol
    var otherParticipants: [OlvidCallParticipantViewModel] { get }
    var uuidForCallKit: UUID { get }
    var direction: OlvidCall.Direction { get }
}


struct ListOfOtherParticipantsView<Model: ListOfOtherParticipantsViewModelProtocol>: View, OlvidCallParticipantViewActionsProtocol {

    @ObservedObject var model: Model
    let actions: ListOfOtherParticipantsViewActionsProtocol
    
    
    /// Part of the `OlvidCallParticipantViewActionsProtocol`.
    func userWantsToRemoveParticipant(participantToRemove: ObvCryptoId) async throws {
        do {
            if model.otherParticipants.count > 1 {
                try await actions.userWantsToRemoveParticipant(uuidForCallKit: model.uuidForCallKit, participantToRemove: participantToRemove)
            } else {
                try await actions.userWantsToEndOngoingCall(uuidForCallKit: model.uuidForCallKit)
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    /// Part of the `OlvidCallParticipantViewActionsProtocol`.
    func userWantsToChatWithParticipant(_ participant: ObvCryptoId) async throws {
        try await actions.userWantsToChatWithParticipant(uuidForCallKit: model.uuidForCallKit, participant: participant)
    }

    
    private func performOnDelete(_ indexSet: IndexSet) {
        guard model.direction == .outgoing else { assertionFailure(); return }
        guard let index = indexSet.first else { assertionFailure(); return }
        guard index >= 0 && index < model.otherParticipants.count else { assertionFailure(); return }
        let participantToRemove = model.otherParticipants[index]
        Task {
            do {
                try await actions.userWantsToRemoveParticipant(uuidForCallKit: model.uuidForCallKit, participantToRemove: participantToRemove.cryptoId)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private let olvidCallParticipantViewState = OlvidCallParticipantViewState(size: .xsmall, 
                                                                              showVideoContentModeToggleButton: false,
                                                                              paddingBellowParticipantName: 0,
                                                                              viewIsFullScreen: false)

    
    var body: some View {
        List {
            ForEach(model.otherParticipants) { participant in
                OlvidCallParticipantView(
                    model: participant,
                    state: olvidCallParticipantViewState,
                    actions: self)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .if(ObvMessengerConstants.targetEnvironmentIsMacCatalyst) {
                    $0.padding(.bottom)
                }
            }
            .if(model.direction == .outgoing) { $0.onDelete(perform: performOnDelete) }
        }
        .listStyle(.plain)
        .if(model.direction == .outgoing) { $0.toolbar { EditButton() } }
        
    }
    
}

// MARK: - Add participant Button

protocol AddParticipantButtonViewActionsProtocol {
    func userWantsToAddParticipantsToExistingCall(uuidForCallKit: UUID, participantsToAdd: Set<ObvCryptoId>) async throws
}

protocol AddParticipantButtonViewModel: ObservableObject {
    associatedtype OlvidCallParticipantViewModel: OlvidCallParticipantViewModelProtocol
    var ownedCryptoId: ObvCryptoId { get }
    var otherParticipants: [OlvidCallParticipantViewModel] { get }
    var uuidForCallKit: UUID { get }
}

/// This button is shown in the bottom sheet under iOS and in the sidebar under macOS. It allows the caller to add new participants to the call.
private struct AddParticipantButtonView<Model: AddParticipantButtonViewModel>: View {

    @ObservedObject var model: Model
    let actions: AddParticipantButtonViewActionsProtocol
    let chooseParticipantsToAddAction: OlvidCallAddParticipantsActionsProtocol
    
    
    private func userWantsToAddParticipantToCall() {
        Task {
            let currentOtherParticipants = Set(model.otherParticipants.map({ $0.cryptoId }))
            let participantsToAdd = await chooseParticipantsToAddAction.userWantsToAddParticipantToCall(ownedCryptoId: model.ownedCryptoId, currentOtherParticipants: currentOtherParticipants)
            do {
                try await actions.userWantsToAddParticipantsToExistingCall(uuidForCallKit: model.uuidForCallKit, participantsToAdd: participantsToAdd)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    

    var body: some View {
        Button(action: userWantsToAddParticipantToCall) {
            HStack {
                CallButton(action: {}, systemIcon: .personBadgePlus, background: .systemFill, size: 56.0)
                Text("ADD_PARTICIPANTS")
                    .padding(.leading, 4)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemIcon: .chevronRight)
            }
            .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped (trick)
            .padding(.horizontal, 20) // Matches the leading padding of the list items bellow
            .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
    }
    
}


// MARK: Ongoing call duration


protocol OngoingCallDurationViewModelProtocol: ObservableObject {
    var direction: OlvidCall.Direction { get }
}

/// View displayed in the bottom sheet view under iOS and in the sidebar under macOS. It shows the current call duration.
private struct OngoingCallDurationView<Model: OngoingCallDurationViewModelProtocol>: View {

    @ObservedObject var model: Model
    @Binding var callDuration: String?

    /// The icon used in the label displaying the call duration
    private var phoneIcon: SystemIcon {
        switch model.direction {
        case .incoming: return .phoneArrowDownLeft
        case .outgoing: return .phoneArrowUpRight
        }
    }

    var body: some View {
        HStack {
            Label(
                title: {
                    Text(callDuration == nil ? "ONGOING_CALL" : "ONGOING_CALL_WITH_DURATION_\(callDuration ?? "")")
                },
                icon: { Image(systemIcon: phoneIcon) }
            )
            .font(.body)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }
    
}


// MARK: Call duration and title

private struct CallDurationAndTitle: View {

    let callDuration: String?

    var body: some View {
        
        VStack {
            BadgeAndTextView()
            if let callDuration {
                Text(verbatim: callDuration)
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Color(UIColor.secondaryLabel))

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
        HStack(spacing: 64) {
            
            CallButton(action: userRejectedIncomingCall,
                       systemIcon: .xmark,
                       background: .systemRed)
            
            CallButton(action: userAcceptedIncomingCall,
                       systemIcon: .checkmark,
                       background: .systemBlue)
            
        }
    }
}


// MARK: - Stack of buttons shown during an ongoing call

protocol OngoingCallButtonsViewModelProtocol: ObservableObject, AudioMenuButtonModelProtocol {
    var selfIsMuted: Bool { get }
    var localPreviewVideoTrack: RTCVideoTrack? { get }
    var currentCameraPosition: AVCaptureDevice.Position? { get }
    var uuidForCallKit: UUID { get }
}


protocol OngoingCallButtonsViewActionsProtocol: AudioMenuButtonActionsProtocol {
    func userWantsToEndOngoingCall(uuidForCallKit: UUID) async throws
    func userWantsToSetMuteSelf(uuidForCallKit: UUID, muted: Bool) async throws
    func userWantsToStartOrStopVideoCamera(uuidForCallKit: UUID, start: Bool, preferredPosition: AVCaptureDevice.Position) async throws
}


private struct OngoingCallButtonsView<Model: OngoingCallButtonsViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: OngoingCallButtonsViewActionsProtocol
    
    // Presenting an alert if an error occurs while starting camera
    @State private var alertIsPresented = false
    @State private var alertType: AlertType = .none
    
    @Environment(\.colorScheme) var colorScheme

    private enum AlertType {
        case none
        case cameraAuthorizationStatusRestricted
        case cameraAuthorizationStatusDenied
        case maxOtherParticipantCountForVideoCallsExceeded
    }
    
    private let buttonImageFontSize: CGFloat = 20
    private let buttonSpacing: CGFloat = 12
    
    
    private func userWantsToToggleMuteSelf() {
        Task {
            do {
                try await actions.userWantsToSetMuteSelf(uuidForCallKit: model.uuidForCallKit, muted: !model.selfIsMuted)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func userWantsToToggleVideoCamera() {
        Task {
            do {
                try await actions.userWantsToStartOrStopVideoCamera(uuidForCallKit: model.uuidForCallKit, start: model.localPreviewVideoTrack == nil, preferredPosition: .front)
            } catch {
                Task { await processStartOrStopVideoCameraError(error: error) }
            }
        }
    }
    
    
    private func processStartOrStopVideoCameraError(error: Error) async {
        if let obvError = error as? ObvPeerConnectionFactory.ObvError {
            switch obvError {
            case .badAVCaptureDeviceAuthorizationStatus(let currentStatus):
                switch currentStatus {
                case .notDetermined:
                    await AVCaptureDevice.requestAccess(for: .video)
                    DispatchQueue.main.async {
                        userWantsToToggleVideoCamera()
                    }
                case .restricted:
                    alertType = .cameraAuthorizationStatusRestricted
                    alertIsPresented = true
                case .denied:
                    alertType = .cameraAuthorizationStatusDenied
                    alertIsPresented = true
                case .authorized:
                    assertionFailure("We should not have thrown")
                @unknown default:
                    assertionFailure("We should not have thrown")
                }
            default:
                assertionFailure()
            }
        } else if let obvError = error as? OlvidCall.ObvError {
            switch obvError {
            case .maxOtherParticipantCountForVideoCallsExceeded:
                alertType = .maxOtherParticipantCountForVideoCallsExceeded
                alertIsPresented = true
            default:
                assertionFailure()
            }
        } else {
            assertionFailure()
        }
    }

    
    private var titleForAlert: LocalizedStringKey {
        switch alertType {
        case .cameraAuthorizationStatusRestricted,
                .cameraAuthorizationStatusDenied,
                .none:
            return "Authorization Required"
        case .maxOtherParticipantCountForVideoCallsExceeded:
            return "VIDEO_CANNOT_START_FOR_CALL"
        }
    }

    
    private var messageForAlert: LocalizedStringKey {
        switch alertType {
        case .cameraAuthorizationStatusRestricted:
            return "Olvid is not authorized to access the camera. Because your settings are restricted, there is nothing we can do about this. Please contact your administrator."
        case .cameraAuthorizationStatusDenied, .none:
            return "Olvid is not authorized to access the camera. You can change this setting within the Settings app."
        case .maxOtherParticipantCountForVideoCallsExceeded:
            return "MAX_OTHER_PARTICIPANT_COUNT_FOR_VIDEO_CALL_EXCEEDED"
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
    
    private var cameraIsOn: Bool {
        model.currentCameraPosition != nil
    }
    

    private var foregroundColorOfMuteButton: UIColor {
        model.selfIsMuted ? .systemRed : .white
    }
    

    private var backgroundColorOfMuteButton: UIColor {
        if model.selfIsMuted {
            switch colorScheme {
            case .light:
                return .black.withAlphaComponent(0.75)
            case .dark:
                return .white
            @unknown default:
                return .black
            }
        } else {
            return .systemFill
        }
    }
    
    
    private var foregroundColorOfCamera: UIColor {
        if cameraIsOn {
            switch colorScheme {
            case .light:
                return .white
            case .dark:
                return .black
            @unknown default:
                return .white
            }
        } else {
            return .white
        }
    }
    
    
    private var backgroundColorOfCamera: UIColor {
        if cameraIsOn {
            switch colorScheme {
            case .light:
                return .black.withAlphaComponent(0.75)
            case .dark:
                return .white
            @unknown default:
                return .black
            }
        } else {
            return .systemFill
        }
    }
    
    
    var body: some View {
        
        HStack {
            
            Spacer(minLength: 0)
            
            CallButton(action: userWantsToToggleMuteSelf,
                       systemIcon: .micSlashFill,
                       foreground: foregroundColorOfMuteButton,
                       background: backgroundColorOfMuteButton)
            
            AudioMenuButton(model: model, actions: actions)
            
            CallButton(action: userWantsToChat,
                       systemIcon: .bubbleLeftAndBubbleRightFill,
                       background: .systemFill)
            
            CallButton(action: userWantsToToggleVideoCamera,
                       systemIcon: .videoFill,
                       foreground: foregroundColorOfCamera,
                       background: backgroundColorOfCamera)

            CallButton(action: userWantsToEndOngoingCall,
                       systemIcon: .phoneDownFill,
                       background: .systemRed)
            
            Spacer(minLength: 0)

        }
        .padding(.horizontal, buttonSpacing)
        .alert(titleForAlert, isPresented: $alertIsPresented, actions: {}, message: { Text(messageForAlert) })
        
    }
}


// MARK: - Generic view for most buttons shown during a call

struct CallButton: View {
    
    private let action: () -> Void
    private let systemIcon: SystemIcon
    private let foreground: UIColor
    private let background: UIColor
    private let size: CGFloat
    private let weight: Font.Weight
    
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.callViewRatioZoomCompensation) var callViewRatioZoomCompensation
    
    init(action: @escaping () -> Void, systemIcon: SystemIcon, foreground: UIColor = .white, background: UIColor, size: CGFloat = Constants.inCallButtonFrameWidth, weight: Font.Weight = .heavy) {
        self.action = action
        self.systemIcon = systemIcon
        self.background = background
        self.size = size
        self.foreground = foreground
        self.weight = weight
    }
    
    private var opacity: Double {
        isEnabled ? 1.0 : 0.4
    }
    
    private var frameSize: CGFloat {
        size * callViewRatioZoomCompensation
    }
    
    var body: some View {
        VStack {
            Button(action: action, label: {
                ZStack {
                    Circle()
                        .foregroundStyle(Color(background).opacity(opacity))
                    Image(systemIcon: systemIcon)
                        .font(Constants.inCallImageFontWith(weight: weight))
                        .foregroundStyle(Color(foreground))
                        .opacity(opacity)
                }
            })
            .frame(width: frameSize, height: frameSize)
        }
        .frame(width: frameSize)
    }
    
}


// MARK: - Button for choosing Audio input

protocol AudioMenuButtonModelProtocol: ObservableObject, AudioMenuButtonLabelViewModelProtocol {
    var availableAudioOptions: [OlvidCallAudioOption]? { get } // Nil if the available options cannot be determined yet
    func userWantsToActivateAudioOption(_ audioOption: OlvidCallAudioOption) async throws
    func userWantsToChangeSpeaker(to isSpeakerEnabled: Bool) async throws
}


protocol AudioMenuButtonActionsProtocol {}


private struct AudioMenuButton<Model: AudioMenuButtonModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: AudioMenuButtonActionsProtocol
    
    @Environment(\.callViewRatioZoomCompensation) var callViewRatioZoomCompensation

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
    
    private var frameSize: CGFloat {
        Constants.inCallButtonFrameWidth * callViewRatioZoomCompensation
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
                .frame(width: frameSize, height: frameSize)
                
            case .button:

                Button(action: userTappedOnAudioButton) {
                    AudioMenuButtonLabelView(model: model)
                }
                .frame(width: frameSize, height: frameSize)

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
                .frame(width: frameSize, height: frameSize)
            }
            
        }
        .frame(width: frameSize)

    }
    
}

// MARK: - The view used for the audio button, both when using a menu or a button

protocol AudioMenuButtonLabelViewModelProtocol: ObservableObject {
    var isSpeakerEnabled: Bool { get }
    var currentAudioOptions: [OlvidCallAudioOption] { get } // Empty if the current option cannot be determined yet
}


private struct AudioMenuButtonLabelView<Model: AudioMenuButtonLabelViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    @Environment(\.colorScheme) var colorScheme

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
    

    private var backgroundColor: Color {
        if model.isSpeakerEnabled {
            switch colorScheme {
            case .light:
                return .black.opacity(0.75)
            case .dark:
                return .white
            @unknown default:
                return .black
            }
        } else {
            return Color(UIColor.systemFill)
        }
    }
    
    
    private var foregroundColor: Color {
        if model.isSpeakerEnabled {
            switch colorScheme {
            case .light:
                return .white
            case .dark:
                return .black
            @unknown default:
                return .white
            }
        } else {
            return .white
        }
    }
    
    
    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(backgroundColor)
            switch displayedIcon {
            case .sf(let systemIcon):
                Image(systemIcon: systemIcon)
                    .font(Constants.inCallImageFont)
                    .foregroundStyle(foregroundColor)
            case .png(let filename):
                Image(filename)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundColor(foregroundColor)
                    .frame(width: Constants.inCallImagePngSize, height: Constants.inCallImagePngSize)
            }
        }
    }
    
}


// MARK: Local constants for the views

private struct Constants {
    
    static let xSmallDetent: CGFloat = spaceAboveCallButtonsStack
    static let smallDetent: CGFloat = inCallButtonFrameWidth + spaceAboveCallButtonsStack + spaceBellowCallButtonsStack
    
    static let spaceAboveCallButtonsStack: CGFloat = 24
    static let spaceBellowCallButtonsStack: CGFloat = 8
    
    /// Width of the frame of all the buttons shown during a call (e.g., the end call button and the mute button).
    static let inCallButtonFrameWidth: CGFloat = 64
    
    /// The buttons shown during a call show a title. This is its size.
    static let inCallButtonTextSize: CGFloat = 16
    
    /// For buttons that show a png instead of an SF symbol (like for the bluetooth image)
    static let inCallImagePngSize: CGFloat = 20
    
    /// The font used for SF symbol images contained in the buttons shown during a call
    static let inCallImageFont = Font.system(size: 20, weight: .heavy, design: .default)
    static func inCallImageFontWith(weight: Font.Weight = .heavy) -> Font { Font.system(size: 20, weight: weight, design: .default) }

    /// Height of the frame delimiting the frame around the text below the buttons shown during a call.
    /// Specifying this height allows to have an acceptable design whatever the number of lines that the text requires (1 or 2).
    static let inCallButtonTextFrameHeight: CGFloat = 42
    
    /// Width and height of the view allowing a user to preview her own video stream
    struct SelfVideoSize {
        static let small: CGFloat = 80
        static let large: CGFloat = 140
    }
    
}


// MARK: - ObvSimpleDeviceOrientationInfo

/// Simple class allowing to track the current device orientation, restricting to the portrait and landscape aspects.
/// This is used in the iOS call view to track the device orientation and modify the self video view accordingly.
private final class ObvSimpleDeviceOrientationInfo {

    enum Orientation {
        case portrait
        case landscape
    }
    
    private(set) var orientation: Orientation = .portrait
    private var token: NSObjectProtocol?
    
    init() {
        self.orientation = UIDevice.current.orientation.isPortrait ? .portrait : .landscape
        token = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            switch UIDevice.current.orientation {
            case .unknown, .faceUp, .faceDown:
                // Don't change the stored orientation
                break
            case .portrait, .portraitUpsideDown:
                self.orientation = .portrait
            case .landscapeLeft, .landscapeRight:
                self.orientation = .landscape
            @unknown default:
                // Don't change the stored orientation
                break
            }
        }
    }
    
    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
    
}


// MARK: - Helper

struct CallViewSafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets = .init(.zero)
}


/// We use this ratio the handle the case where the user changed the display zoom (and choosed the larger text option).
/// It is set at the top level view of the call view.
struct CallViewRatioZoomCompensation: EnvironmentKey {
    static var defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var callViewSafeAreaInsets: EdgeInsets {
        get { self[CallViewSafeAreaInsetsKey.self] }
        set { self[CallViewSafeAreaInsetsKey.self] = newValue }
    }
    var callViewRatioZoomCompensation: CGFloat {
        get { self[CallViewRatioZoomCompensation.self] }
        set { self[CallViewRatioZoomCompensation.self] = newValue }
    }
}


// MARK: - Previews

struct OlvidCallView_Previews: PreviewProvider {
    
    private static let cryptoIds: [ObvCryptoId] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]
    
    private final class CallParticipantModelForPreviews: OlvidCallParticipantViewModelProtocol {
        let isOneToOne: Bool
        let remoteCameraVideoTrackIsEnabled = false
        let remoteScreenCastVideoTrackIsEnabled = false
        var remoteCameraVideoTrack: RTCVideoTrack? { nil }
        var remoteScreenCastVideoTrack: RTCVideoTrack? { nil }
        var uuidForCallKit: UUID { UUID() }        
        var cryptoId: ObvTypes.ObvCryptoId
        var stateLocalizedDescription: String
        let state = OlvidCallParticipant.State.connected
        let showRemoveParticipantButton: Bool
        let displayName: String
        let circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration
        var contactIsMuted: Bool
        init(cryptoId: ObvTypes.ObvCryptoId, showRemoveParticipantButton: Bool, displayName: String, stateLocalizedDescription: String, circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration, contactIsMuted: Bool, isOneToOne: Bool) {
            self.showRemoveParticipantButton = showRemoveParticipantButton
            self.displayName = displayName
            self.stateLocalizedDescription = stateLocalizedDescription
            self.circledInitialsConfiguration = circledInitialsConfiguration
            self.contactIsMuted = contactIsMuted
            self.cryptoId = cryptoId
            self.isOneToOne = isOneToOne
        }
    }
    
    
    private final class OwnedCircleViewModelForPreviews: InitialCircleViewNewModelProtocol {
        var circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration {
            return .icon(.person)
        }
    }
    
    private final class ModelForPreviews: OlvidCallViewModelProtocol {
        let localPreviewVideoTrack: RTCVideoTrack? = nil
        let atLeastOneOtherParticipantHasCameraEnabled = false
        let ownedInitialCircle = OwnedCircleViewModelForPreviews()
        let localUserStillNeedsToAcceptOrRejectIncomingCall = false
        let state: OlvidCall.State = .callInProgress
        var currentCameraPosition: AVCaptureDevice.Position? { .back }
        let dateWhenCallSwitchedToInProgress: Date? = Date.now
        var direction: OlvidCall.Direction { .outgoing }
        let ownedCryptoId = OlvidCallView_Previews.cryptoIds[0]
        let availableAudioOptions: [OlvidCallAudioOption]?
        var currentAudioOptions: [OlvidCallAudioOption]
        let selfVideoCameraCaptureSession: AVCaptureSession? = nil
        let selfVideoSize: CGSize? = nil
        let doMirrorViewSelfVideoView = false
        @Published var isSpeakerEnabled: Bool
        let uuidForCallKit = UUID()
        let selfIsMuted: Bool
        let otherParticipants: [CallParticipantModelForPreviews]
        init(selfIsMuted: Bool, otherParticipants: [CallParticipantModelForPreviews], availableAudioOptions: [OlvidCallAudioOption]?) {
            self.otherParticipants = otherParticipants
            self.selfIsMuted = selfIsMuted
            self.availableAudioOptions = availableAudioOptions
            self.currentAudioOptions = [availableAudioOptions!.first!]
            self.isSpeakerEnabled = true
        }
        func userWantsToActivateAudioOption(_ audioOption: OlvidCallAudioOption) async throws {}
        func userWantsToChangeSpeaker(to isSpeakerEnabled: Bool) async throws {
            self.isSpeakerEnabled = isSpeakerEnabled
        }
    }
    
    private static let model = ModelForPreviews(
        selfIsMuted: true,
        otherParticipants: [
            .init(cryptoId: cryptoIds[0],
                  showRemoveParticipantButton: false,
                  displayName: "Thomas Baignères",
                  stateLocalizedDescription: "Some s0tate",
                  circledInitialsConfiguration: .contact(
                    initial: "S",
                    photo: nil,
                    showGreenShield: false,
                    showRedShield: false,
                    cryptoId: cryptoIds[0],
                    tintAdjustementMode: .normal),
                  contactIsMuted: true,
                  isOneToOne: true),
            .init(cryptoId: cryptoIds[1],
                  showRemoveParticipantButton: false,
                  displayName: "Tim Cooks",
                  stateLocalizedDescription: "Some other state",
                  circledInitialsConfiguration: .contact(
                    initial: "T",
                    photo: nil,
                    showGreenShield: false,
                    showRedShield: false,
                    cryptoId: cryptoIds[1],
                    tintAdjustementMode: .normal),
                  contactIsMuted: false,
                  isOneToOne: false),
            .init(cryptoId: cryptoIds[1],
                  showRemoveParticipantButton: false,
                  displayName: "Steve Jobs",
                  stateLocalizedDescription: "Connected",
                  circledInitialsConfiguration: .contact(
                    initial: "S",
                    photo: nil,
                    showGreenShield: false,
                    showRedShield: false,
                    cryptoId: cryptoIds[2],
                    tintAdjustementMode: .normal),
                  contactIsMuted: false,
                  isOneToOne: true),
        ],
        availableAudioOptions: [
            OlvidCallAudioOption.builtInSpeaker(),
            OlvidCallAudioOption.forPreviews(portType: .headphones, portName: "Headphones"),
            //OlvidCallAudioOption.forPreviews(portType: .airPlay, portName: "Airplay"),
        ])
    
    private final class ActionsForPreviews: OlvidCallViewActionsProtocol {
        func callViewDidDisappear(uuidForCallKit: UUID) async {}
        func callViewDidAppear(uuidForCallKit: UUID) async {}
        func userWantsToChatWithParticipant(uuidForCallKit: UUID, participant: ObvTypes.ObvCryptoId) async throws {}
        func userWantsToRemoveParticipant(participantToRemove: ObvTypes.ObvCryptoId) async throws {}
        func userWantsToRemoveParticipant(uuidForCallKit: UUID, participantToRemove: ObvTypes.ObvCryptoId) async throws {}
        func userWantsToAddParticipantsToExistingCall(uuidForCallKit: UUID, participantsToAdd: Set<ObvTypes.ObvCryptoId>) async throws {}
        func userWantsToSetMuteSelf(uuidForCallKit: UUID, muted: Bool) async throws {}
        func userWantsToEndOngoingCall(uuidForCallKit: UUID) async throws {}
        func userAcceptedIncomingCall(uuidForCallKit: UUID) async {}
        func userRejectedIncomingCall(uuidForCallKit: UUID) async {}
        func userWantsToAddParticipantToCall() {}
        func userWantsToMuteSelf() {}
        func userWantsToStartOrStopVideoCamera(uuidForCallKit: UUID, start: Bool, preferredPosition: AVCaptureDevice.Position) async throws {}
    }
    
    
    private static let actions = ActionsForPreviews()

    private final class OlvidCallAddParticipantActionsForPreviews: OlvidCallAddParticipantsActionsProtocol {
        func userWantsToAddParticipantToCall(ownedCryptoId: ObvTypes.ObvCryptoId, currentOtherParticipants: Set<ObvTypes.ObvCryptoId>) async -> Set<ObvTypes.ObvCryptoId> { Set([]) }
    }
    
    private static let chooseParticipantsToAddAction = OlvidCallAddParticipantActionsForPreviews()
    
    static var previews: some View {
        OlvidCallView(model: model, actions: actions, chooseParticipantsToAddAction: chooseParticipantsToAddAction)
            //.environment(\.locale, .init(identifier: "fr"))
    }
    
}
