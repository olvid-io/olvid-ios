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
import OSLog
import CoreData
import ObvSystemIcon
import ObvAppTypes
import ObvDesignSystem
import ObvTypes
import ObvAppCoreConstants

@MainActor
public protocol ObvSideBarViewActions {
    func userDidTapOnSidebarItem(_ view: ObvSideBarView, _ flow: ObvAppTypes.ObvFlow) async throws
}

public struct ObvSideBarViewModel: Equatable, Sendable {
    let badgeCountForLatestDiscussions: Int
    let badgeCountForInvitations: Int
    let flowToHighlight: ObvAppTypes.ObvFlow
    
    public init(badgeCountForLatestDiscussions: Int, badgeCountForInvitations: Int, flowToHighlight: ObvAppTypes.ObvFlow) {
        self.badgeCountForLatestDiscussions = badgeCountForLatestDiscussions
        self.badgeCountForInvitations = badgeCountForInvitations
        self.flowToHighlight = flowToHighlight
    }
    
}

@MainActor
public protocol ObvSideBarViewDataSource {
    func getAsyncStreamOfObvSideBarViewModel(_ view: ObvSideBarView) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSideBarViewModel>)
    func finishAsyncStreamOfObvSideBarViewModel(_ view: ObvSideBarView, streamUUID: UUID)
    func getObvSideBarViewModel(_ view: ObvSideBarView) throws -> ObvSideBarViewModel?
}

// MARK: - ObvSideBarView

public struct ObvSideBarView: View {
    
    let actions: ObvSideBarViewActions
    let dataSource: ObvSideBarViewDataSource

    @State private var streamedViewModel = ObvSideBarViewModel(badgeCountForLatestDiscussions: 0, badgeCountForInvitations: 0, flowToHighlight: .latestDiscussions)

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvSideBarView")
    
    public struct Constants {
        fileprivate static let buttonImageFontSize: CGFloat = 20
        static let buttonWidth: CGFloat = buttonImageFontSize + 36
        static let paddingAroundButton: CGFloat = 25
        public static let idealColumnWidth: CGFloat = buttonWidth + 2*paddingAroundButton
    }
        
    private func onTap(_ flow: ObvAppTypes.ObvFlow) {
        Task {
            do {
                try await actions.userDidTapOnSidebarItem(self, flow)
            } catch {
                Self.logger.fault("Could not change flow: \(error)")
                assertionFailure()
            }
        }
    }
    
    private func requestViewModelStream() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvSideBarViewModel(self)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvSideBarViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    
    private func onAppear() {
        do {
            if let latestModel = try dataSource.getObvSideBarViewModel(self) {
                self.streamedViewModel = latestModel
            }
        } catch {
            Self.logger.fault("Could not refresh view model: \(error)")
        }
    }
    
        
    @Environment(\.colorScheme) var colorScheme
    
    /// Fixes a rendering glitch on iPadOS 18 (and earlier) and macOS 15.6 (and earlier),
    /// where a small miscolored rectangle
    /// appears at the bottom of the view if the background is not explicitly set.
    ///
    /// On macOS 15.6.1, an additional tweak in the `viewDidLoad` method of the hosting controller
    /// is required to fully resolve the issue.
    private var backgroundForPlatform: some ShapeStyle {
        if #available(iOS 26, *) {
            return .background
        } else {
            #if targetEnvironment(macCatalyst)
            return Color(UIColor.customPrivateColor)
            #else
            return Color(UIColor.secondarySystemBackground)
            #endif
        }
    }
    
    public var body: some View {
        
        VStack {
            List {
                
                SidebarButton(
                    action: { onTap(.latestDiscussions) },
                    title: String(localizedInThisBundle: "DISCUSSIONS"),
                    icon: .bubbleLeftAndBubbleRight,
                    isSelected: streamedViewModel.flowToHighlight == .latestDiscussions,
                    badgeValue: streamedViewModel.badgeCountForLatestDiscussions)
                .listRowBackground(Color.clear)
                
                SidebarButton(
                    action: { onTap(.contacts) },
                    title: String(localizedInThisBundle: "CONTACTS"),
                    icon: .person,
                    isSelected: streamedViewModel.flowToHighlight == .contacts,
                    badgeValue: 0)
                .listRowBackground(Color.clear)
                
                SidebarButton(
                    action: { onTap(.groups) },
                    title: String(localizedInThisBundle: "GROUPS"),
                    icon: .person3,
                    isSelected: streamedViewModel.flowToHighlight == .groups,
                    badgeValue: 0)
                .listRowBackground(Color.clear)
                
                SidebarButton(
                    action: { onTap(.invitations) },
                    title: String(localizedInThisBundle: "INVITATIONS"),
                    icon: .trayAndArrowDown,
                    isSelected: streamedViewModel.flowToHighlight == .invitations,
                    badgeValue: streamedViewModel.badgeCountForInvitations)
                .listRowBackground(Color.clear)
                
            }
            .listStyle(.sidebar)
            
            Spacer()
            
        }
        .background(backgroundForPlatform)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: onAppear)
        .task { await requestViewModelStream() }
        
    }
}


// MARK: - Internal view: Sidebar button

private struct SidebarButton: View {
    
    let action: () -> Void
    let title: String
    let icon: SystemIcon
    let isSelected: Bool
    let badgeValue: Int
    
    private var iconColor: Color {
        if colorScheme == .dark {
            return isSelected ? .white : .secondary
        } else {
            return isSelected ? .accentColor : .secondary
        }
    }
    
    private var buttonBorderShape: ButtonBorderShape {
        if #available(iOS 17, *) {
            return .roundedRectangle(radius: 8)
        } else {
            return .capsule
        }
    }
    
    private let imageSize: CGFloat = ObvSideBarView.Constants.buttonImageFontSize
    private let imageWeight: Font.Weight = .medium
    private let imageDesign: Font.Design = .default
    
    @Environment(\.colorScheme) var colorScheme

    private var imageFont: Font {
        if #available(iOS 16, *) {
            return .system(size: imageSize, weight: imageWeight, design: imageDesign)
        } else {
            return .system(size: imageSize)
        }
    }
    

    private var backgroundColorWhenSelected: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.07)
        case .dark:
            return Color.white.opacity(0.07)
        @unknown default:
            return Color.white.opacity(0.07)
        }
    }
    
    private var tintColor: Color {
        isSelected ? backgroundColorWhenSelected : .clear
    }
    
    var body: some View {
        HStack {
            
            Spacer(minLength: 0)
            
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Image(systemIcon: icon)
                        .font(imageFont)
                        .foregroundStyle(iconColor)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .frame(width: ObvSideBarView.Constants.buttonWidth)
            }
            .overlay(alignment: .topTrailing) {
                if badgeValue > 0 {
                    ObvBadgeNumberOfNewMessages(numberOfNewReceivedMessages: badgeValue)
                        .offset(x: -12, y: 4)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(buttonBorderShape)
            .tint(tintColor)
            .animation(nil, value: tintColor) // Don't animate highligted item change
            .help(title)
            
            Spacer(minLength: 0)

        }

    }
    
}


private extension UIColor {
    
    /// A private color used to prevent a rendering glitch in macOS 15.6,
    /// where a small miscolored rectangle would otherwise appear at the bottom of the sidebar.
    /// @note An additional fix in the `viewDidLoad` method of the hosting view controller is required.
    static var customPrivateColor: UIColor {
        return UIColor { traitCollection in
            if UITraitCollection.current.userInterfaceStyle == .dark {
                return UIColor.systemBackground
            } else {
                return UIColor.secondarySystemBackground
            }
        }
    }
    
}


// MARK: - Previews

#if DEBUG

private final class DataSourceAndActionsForPreviews {
    
    private var sidebarItemToHighlight: ObvAppTypes.ObvFlow = .latestDiscussions
    
}

extension DataSourceAndActionsForPreviews: ObvSideBarViewDataSource {
    
    func getAsyncStreamOfObvSideBarViewModel(_ view: ObvSideBarView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvSideBarViewModel>) {
        let stream = AsyncStream<ObvSideBarViewModel> { (continuation: AsyncStream<ObvSideBarViewModel>.Continuation) in
            Task {
                while true {
                    try? await Task.sleep(seconds: 2)
                    continuation.yield(.init(badgeCountForLatestDiscussions: 2, badgeCountForInvitations: 0, flowToHighlight: .latestDiscussions))
                    try? await Task.sleep(seconds: 2)
                    continuation.yield(.init(badgeCountForLatestDiscussions: 5, badgeCountForInvitations: 1, flowToHighlight: .invitations))
                    try? await Task.sleep(seconds: 2)
                    continuation.yield(.init(badgeCountForLatestDiscussions: 3, badgeCountForInvitations: 1, flowToHighlight: .latestDiscussions))
                    try? await Task.sleep(seconds: 2)
                    continuation.yield(.init(badgeCountForLatestDiscussions: 10, badgeCountForInvitations: 0, flowToHighlight: .latestDiscussions))
                    try? await Task.sleep(seconds: 2)
                    continuation.yield(.init(badgeCountForLatestDiscussions: 0, badgeCountForInvitations: 0, flowToHighlight: .latestDiscussions))
                }
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvSideBarViewModel(_ view: ObvSideBarView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    

    /// Called by the `ObvSideBarView` when it appears, to refresh its model immediately. This ensures the UI reflects the latest data without delay.
    func getObvSideBarViewModel(_ view: ObvSideBarView) throws -> ObvSideBarViewModel? {
        return nil
    }
    
}

extension DataSourceAndActionsForPreviews: ObvSideBarViewActions {
    
    func userDidTapOnSidebarItem(_ view: ObvSideBarView, _ item: ObvAppTypes.ObvFlow) async throws {
        sidebarItemToHighlight = item
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

@available(iOS 16.0, *)
#Preview {
    NavigationSplitView {
        ObvSideBarView(actions: dataSourceAndActionsForPreviews,
                       dataSource: dataSourceAndActionsForPreviews)
            .navigationSplitViewColumnWidth(ObvSideBarView.Constants.idealColumnWidth)
    } content: {
        Text(verbatim: "Content")
    } detail: {
        Text(verbatim: "Detail")
    }

}

#endif
