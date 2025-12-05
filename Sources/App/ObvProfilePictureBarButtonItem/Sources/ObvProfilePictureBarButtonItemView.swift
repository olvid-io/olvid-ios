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
import CoreHaptics
import ObvTypes
import ObvDesignSystem
import ObvOwnedIdentityChooser


public struct ObvProfilePictureBarButtonItemViewModel: Sendable, Equatable {
    let ownedCryptoId: ObvCryptoId
    let avatarModel: ObvAvatarViewModel
    let showGreenShield: Bool
    let showRedDot: Bool
    
    public init(ownedCryptoId: ObvCryptoId, avatarModel: ObvAvatarViewModel, showGreenShield: Bool, showRedDot: Bool) {
        self.ownedCryptoId = ownedCryptoId
        self.avatarModel = avatarModel
        self.showGreenShield = showGreenShield
        self.showRedDot = showRedDot
    }
    
}


@MainActor
public protocol ObvProfilePictureBarButtonItemViewDataSource: Sendable {
    func getAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvProfilePictureBarButtonItemViewModel>)
    func finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, streamUUID: UUID)
    func getNextOwnedCryptoId(_ view: ObvProfilePictureBarButtonItemView, currentOwnedCryptoId: ObvCryptoId) async throws -> ObvCryptoId
}


@MainActor
public protocol ObvProfilePictureBarButtonItemViewActionsProtocol {
    func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItemView)
    func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) async
    func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItemView) async
}


// MARK: - Main view

public struct ObvProfilePictureBarButtonItemView: View {
    
    @Binding var currentOwnedCryptoId: ObvCryptoId
    let dataSource: ObvProfilePictureBarButtonItemViewDataSource
    let ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ObvProfilePictureBarButtonItemViewActionsProtocol
    
    public init(currentOwnedCryptoId: Binding<ObvCryptoId>, dataSource: ObvProfilePictureBarButtonItemViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource, actions: ObvProfilePictureBarButtonItemViewActionsProtocol) {
        self._currentOwnedCryptoId = currentOwnedCryptoId
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.ownedIdentityChooserViewDataSource = ownedIdentityChooserViewDataSource
        self.actions = actions
    }
    
    @State private var viewModel: ObvProfilePictureBarButtonItemViewModel?
    @State private var streamUUIDForViewModel: UUID?
    
    /// Animation values used on iOS17+, to perform an animation when the user performs a swipe
    /// on this profile picture to switch to the next profile.
    private struct SwipeAnimationValues {
        var scale = 1.0
        var verticalTranslation = 0.0
        var opacity = 1.0
    }
    
    @State private var toggleToPerformSwipeAnimation: Bool = false
    @State private var toggleToPerformSensoryFeedback: Bool = false
        
    private let swipeAnimationHidingDuration: Double = 0.1
    private let swipeAnimationUnhidingDuration: Double = 0.4
    
    private func onAppear() {
        Task {
            try await requestStream()
        }
    }
    
    private func requestStream() async throws {
        let (newStreamUUID, stream) = try await dataSource.getAsyncStreamOfObvProfilePictureBarButtonItemViewModel(self, ownedCryptoId: currentOwnedCryptoId)
        if let previousStreamUUID = self.streamUUIDForViewModel {
            dataSource.finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(self, streamUUID: previousStreamUUID)
        }
        self.streamUUIDForViewModel = newStreamUUID
        for await receivedModel in stream {
            withAnimation {
                self.viewModel = receivedModel
            }
        }
    }
    
    private func onDisappear() {
        if let streamUUIDForViewModel {
            dataSource.finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(self, streamUUID: streamUUIDForViewModel)
            self.streamUUIDForViewModel = nil
        }
    }

    
    private func startAnimatedSwitchingToNextProfile() async throws {
        // Request the next cryptoId to our data source and make sure it is different from the one currently shown
        let nextCurrentOwnedCryptoId = try await dataSource.getNextOwnedCryptoId(self, currentOwnedCryptoId: self.currentOwnedCryptoId)
        guard nextCurrentOwnedCryptoId != self.currentOwnedCryptoId else { return }
        // Start the swipe transition to the next ownedCryptoId
        toggleToPerformSwipeAnimation.toggle()
        try? await Task.sleep(seconds: swipeAnimationHidingDuration)
        withAnimation {
            self.currentOwnedCryptoId = nextCurrentOwnedCryptoId
            toggleToPerformSensoryFeedback.toggle()
        }
    }
    
    
    private var avatarSize: CGSize {
        CGSize(width: 35.25, height: 35.25) // Value that matches the UIKit result on an iPhone 16
    }

    private func onChangeOfCurrentOwnedCryptoId() {
        Task { try await requestStream() }
    }

    public var body: some View {
        if #available(iOS 17.0, *) {
            Group {
                if let viewModel {
                    MainInternalView(currentOwnedCryptoId: $currentOwnedCryptoId,
                                     viewModel: viewModel,
                                     internalActions: self,
                                     dataSource: dataSource,
                                     ownedIdentityChooserDataSource: ownedIdentityChooserViewDataSource,
                                     avatarViewDataSource: avatarViewDataSource,
                                     avatarSize: avatarSize)
                    .keyframeAnimator(initialValue: SwipeAnimationValues(), trigger: toggleToPerformSwipeAnimation) { content, value in
                        content
                            .scaleEffect(value.scale)
                            .offset(y: value.verticalTranslation)
                            .opacity(value.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.verticalTranslation) {
                            LinearKeyframe(avatarSize.height, duration: swipeAnimationHidingDuration)
                            MoveKeyframe(0.0)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1.0, duration: swipeAnimationHidingDuration * 0.25)
                            LinearKeyframe(0.0, duration: swipeAnimationHidingDuration * 0.75)
                            //SpringKeyframe(1.0, duration: swipeAnimationUnhidingDuration)
                            MoveKeyframe(1.0) // Required for some reason
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1.0, duration: swipeAnimationHidingDuration)
                            MoveKeyframe(0.0)
                            SpringKeyframe(1.0, spring: .smooth(duration: swipeAnimationUnhidingDuration, extraBounce: 0.3))
                            MoveKeyframe(1.0)
                        }
                    }
                    .sensoryFeedback(.success, trigger: toggleToPerformSensoryFeedback)
                    .padding(4.25) // Value that matches the UIKit result on an iPhone 16
                    .clipped()

                } else {
                    ProgressView()
                        .frame(width: avatarSize.width, height: avatarSize.height)
                }
            }
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onChange(of: currentOwnedCryptoId, onChangeOfCurrentOwnedCryptoId)
        } else {
            Group {
                if let viewModel {
                    MainInternalView(currentOwnedCryptoId: $currentOwnedCryptoId,
                                     viewModel: viewModel,
                                     internalActions: self,
                                     dataSource: dataSource,
                                     ownedIdentityChooserDataSource: ownedIdentityChooserViewDataSource,
                                     avatarViewDataSource: avatarViewDataSource,
                                     avatarSize: avatarSize)
                } else {
                    ProgressView()
                        .frame(width: avatarSize.width, height: avatarSize.height)
                }
            }
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onChange(of: currentOwnedCryptoId, perform: { _ in onChangeOfCurrentOwnedCryptoId() })
        }
    }
    
}


extension ObvProfilePictureBarButtonItemView: MainInternalViewActionsProtocol {
    
    // OwnedIdentityChooserViewActionsProtocol
    
    public func userChoseProfile(_ view: OwnedIdentityChooserView, chosenOwnedCryptoId: ObvTypes.ObvCryptoId) async throws {
        if self.currentOwnedCryptoId == chosenOwnedCryptoId {
            Task { await actions.userWantsToEditOwnedIdentity(self, ownedCryptoId: chosenOwnedCryptoId) }
        } else {
            withAnimation {
                self.currentOwnedCryptoId = chosenOwnedCryptoId
            }
        }
    }
    
    public func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        await actions.userWantsToEditOwnedIdentity(self, ownedCryptoId: currentOwnedCryptoId)
    }
    
    public func userWantsToAddNewProfile(_ view: OwnedIdentityChooserView) async {
        await actions.userWantsToAddNewProfile(self)
    }
    
    // MainInternalViewActionsProtocol
    
    fileprivate func onSwipeDown(_ view: MainInternalView) {
        Task { try await startAnimatedSwitchingToNextProfile() }
    }
    
    fileprivate func userDidLongPressOnProfilePicture(_ view: MainInternalView) {
        actions.userDidLongPressOnProfilePicture(self)
    }

}


@MainActor
private protocol MainInternalViewActionsProtocol: OwnedIdentityChooserViewActionsProtocol {
    func userDidLongPressOnProfilePicture(_ view: MainInternalView)
    func onSwipeDown(_ view: MainInternalView)
}


private struct MainInternalView: View {
    
    @Binding var currentOwnedCryptoId: ObvCryptoId
    let viewModel: ObvProfilePictureBarButtonItemViewModel
    let internalActions: MainInternalViewActionsProtocol
    let dataSource: ObvProfilePictureBarButtonItemViewDataSource
    let ownedIdentityChooserDataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let avatarSize: CGSize

    @State private var showOwnedIdentityChooserView = false
    
    func onSwipeDown() {
        internalActions.onSwipeDown(self)
    }

    private let ownedIdentityChooserViewConfiguration = OwnedIdentityChooserViewConfiguration(
        mode: .changeCurrentProfile,
        explanation: nil,
        title: String(localizedInThisBundle: "MY_OWN_IDS"))
    
    private func onLongPressGesture() {
        internalActions.userDidLongPressOnProfilePicture(self)
    }
    
    private var redDotWidth: CGFloat {
        avatarSize.width / 2.5
    }
    
    private var greenShieldWidth: CGFloat {
        avatarSize.width / 2.9
    }
    
    private var greeShieldOffset: CGSize {
        .init(width: viewModel.showRedDot ? 4.0 : 4.0,
              height: viewModel.showRedDot ? 4.0 : -4.0)
    }
    
    var body: some View {
        ObvAvatarView(model: viewModel.avatarModel,
                      style: .topBar,
                      size: .custom(frameSize: avatarSize),
                      dataSource: avatarViewDataSource)
        .overlay(alignment: .topTrailing) {
            RedDotView(redDotWidth: redDotWidth)
                .scaleEffect(viewModel.showRedDot ? 1.0 : 0.0, anchor: .center)
                .offset(x: 3, y: -3)
                .animation(viewModel.showRedDot ? .spring(bounce: 0.5) : .smooth(duration: 0.5), value: viewModel.showRedDot)
        }
        .overlay(alignment: viewModel.showRedDot ? .bottomTrailing : .topTrailing) {
            GreenShieldView(greenShieldWidth: greenShieldWidth)
                .scaleEffect(viewModel.showGreenShield ? 1.0 : 0.0, anchor: .center)
                .offset(greeShieldOffset)
                .animation(.spring(bounce: 0.3), value: viewModel.showRedDot)
                .animation(.spring(bounce: 0.3), value: viewModel.showGreenShield)
        }
        .onTapGesture(perform: { showOwnedIdentityChooserView.toggle() })
        .onLongPressGesture(perform: onLongPressGesture)
        .gesture(DragGesture().onEnded({ value in
            guard value.translation.height > 0 else { return }
            onSwipeDown()
        }))
        .popoverOrSheetOnCatalyst(isPresented: $showOwnedIdentityChooserView, arrowEdge: .top) {
            OwnedIdentityChooserView(currentOwnedCryptoId: currentOwnedCryptoId,
                                     actions: internalActions,
                                     dataSource: ownedIdentityChooserDataSource,
                                     avatarViewDataSource: avatarViewDataSource,
                                     configuration: ownedIdentityChooserViewConfiguration,
                                     toggleToDismiss: $showOwnedIdentityChooserView)
            .presentationDetentsOniOS16([.medium, .large])
        }
    }
}


private struct GreenShieldView: View {
    
    let greenShieldWidth: CGFloat
    
    var body: some View {
        ZStack {
            Image(systemIcon: .shieldFill)
                .foregroundStyle(.white)
                .font(.system(size: greenShieldWidth-2))
            Image(systemIcon: .checkmarkShieldFill)
                .font(.system(size: greenShieldWidth))
                .foregroundStyle(.green)
        }
    }
}


private struct RedDotView: View {
    
    let redDotWidth: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(.background)
            Circle()
                .frame(width: redDotWidth-4)
                .foregroundStyle(.red)
        }
        .frame(width: redDotWidth)
    }
}


// MARK: - Internal ViewModifier

/// Prevents a crash on macOS 26 caused by using the `.popover` modifier on a `ToolbarItem`.
///
/// This custom `ViewModifier` provides a platform-specific workaround:
/// - Uses a `.sheet` modifier on macOS (Catalyst) to avoid the crash.
/// - Falls back to the standard `.popover` modifier on all other platforms.
private struct PopoverOrSheetOnCatalyst<PresentedContent: View>: ViewModifier {
    
    @Binding var isPresented: Bool
    let arrowEdge: Edge?
    let presentedContent: PresentedContent

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.sheet(isPresented: $isPresented) {
            presentedContent
        }
        #else
        content.popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            presentedContent
        }
        #endif

    }
    
}


private extension View {
    
    /// Prevents a crash on macOS 26 caused by using the `.popover` modifier on a `ToolbarItem`.
    ///
    /// This custom `ViewModifier` provides a platform-specific workaround:
    /// - Uses a `.sheet` modifier on macOS (Catalyst) to avoid the crash.
    /// - Falls back to the standard `.popover` modifier on all other platforms.
    func popoverOrSheetOnCatalyst<PresentedContent>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil, @ViewBuilder content: @escaping () -> PresentedContent) -> some View where PresentedContent : View {
        self.modifier(PopoverOrSheetOnCatalyst.init(isPresented: isPresented, arrowEdge: arrowEdge, presentedContent: content()))
    }
    
}

// MARK: - Previews

#if DEBUG


@MainActor
private final class DataSourceAndActionsForPreviews: ObvProfilePictureBarButtonItemViewDataSource, ObvProfilePictureBarButtonItemViewActionsProtocol, ObvAvatarViewDataSource, OwnedIdentityChooserViewDataSource {
    
    private var continuation: AsyncStream<ObvProfilePictureBarButtonItemViewModel>.Continuation?
    private var continuationForOwnedIdentityChooserViewModel: AsyncStream<OwnedIdentityChooserViewModel>.Continuation?
    
    static var initialCurrentOwnedCryptoId: ObvCryptoId = ObvCryptoId.sampleDatasForOwnedCryptoId[0]
    private var currentOwnedCryptoId: ObvCryptoId = DataSourceAndActionsForPreviews.initialCurrentOwnedCryptoId
    
    // Data source
    
    func getNextOwnedCryptoId(_ view: ObvProfilePictureBarButtonItemView, currentOwnedCryptoId: ObvCryptoId) async throws -> ObvCryptoId {
        guard let currentIndex = ObvCryptoId.sampleDatasForOwnedCryptoId.firstIndex(where: { $0 == currentOwnedCryptoId }) else {
            return currentOwnedCryptoId
        }
        let newIndex = (currentIndex + 1) % ObvCryptoId.sampleDatasForOwnedCryptoId.count
        let newCurrentOwnedCryptoId = ObvCryptoId.sampleDatasForOwnedCryptoId[newIndex]
        return newCurrentOwnedCryptoId
    }
    

    func getAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvProfilePictureBarButtonItemViewModel>) {
        print("[DataSource] getAsyncStreamOfObvProfilePictureBarButtonItemViewModel for \(ownedCryptoId.getIdentity().hexString().suffix(8))")
        let stream = AsyncStream(ObvProfilePictureBarButtonItemViewModel.self) { (continuation: AsyncStream<ObvProfilePictureBarButtonItemViewModel>.Continuation) in
            self.continuation = continuation
            Task {
                for model in ObvProfilePictureBarButtonItemViewModel.sampleDataForOwnedCryptoId(ownedCryptoId) {
                    continuation.yield(model)
                    try? await Task.sleep(seconds: 2)
                }
            }
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, streamUUID: UUID) {
        continuation?.finish()
    }
    
    
    func fetchAvatar(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        let image = UIImage.avatarImageForURL(photoURL)
        //try? await Task.sleep(seconds: 1)
        return image
    }
    

    func fetchAvatarFromCache(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        return UIImage.avatarImageForURL(photoURL)
    }
    
    
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserView, currentOwnedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>) {
        let stream = AsyncStream(OwnedIdentityChooserViewModel.self) { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            self.continuationForOwnedIdentityChooserViewModel = continuation
            let model = OwnedIdentityChooserViewModel.sampleDatas[0]
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserView, streamUUID: UUID) {
        continuationForOwnedIdentityChooserViewModel?.finish()
    }
    
    
    // Actions called by the owned identity chooser view
    
    func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) async {
        print("User wants to edit owned identity")
    }
    
    func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItemView) async {
        print("User wants to add new profile")
    }
    
    // Actions
    
    func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItemView) {
        print("User did long press on profile picture")
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

@available(iOS 16.0, *)
private struct PreviewView: View {
    
    @State private var currentOwnedCryptoId: ObvCryptoId = DataSourceAndActionsForPreviews.initialCurrentOwnedCryptoId
    
    var body: some View {
        Text(verbatim: "Testing ObvProfilePictureBarButtonItemView")
            .font(.headline)
            .padding()
            .toolbar {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        ObvProfilePictureBarButtonItemView(
                            currentOwnedCryptoId: $currentOwnedCryptoId,
                            dataSource: dataSourceAndActionsForPreviews,
                            avatarViewDataSource: dataSourceAndActionsForPreviews,
                            ownedIdentityChooserViewDataSource: dataSourceAndActionsForPreviews,
                            actions: dataSourceAndActionsForPreviews)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        ObvProfilePictureBarButtonItemView(
                            currentOwnedCryptoId: $currentOwnedCryptoId,
                            dataSource: dataSourceAndActionsForPreviews,
                            avatarViewDataSource: dataSourceAndActionsForPreviews,
                            ownedIdentityChooserViewDataSource: dataSourceAndActionsForPreviews,
                            actions: dataSourceAndActionsForPreviews)
                    }
                }
            }
    }
}

@available(iOS 16, *)
#Preview {
    NavigationView {
        PreviewView()
    }
}


#endif
