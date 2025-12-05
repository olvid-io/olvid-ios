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
import CoreData
import ObvAppTypes
import ObvDesignSystem
import ObvSystemIcon
import ObvAppCoreConstants
import OSLog


public struct ObvDiscussionCellViewModel: Sendable, Equatable {
    let avatarModel: ObvAvatarViewModel
    let title: String
    let date: Date?
    let message: Message?
    let numberOfNewReceivedMessages: Int
    let showGreenShield: Bool
    let showRedShield: Bool
    let aNewReceivedMessageDoesMentionOwnedIdentity: Bool
    let shouldMuteNotifications: Bool
    let isArchived: Bool
    let isPinned: Bool
    let isMuted: Bool
    
    public init(avatarModel: ObvAvatarViewModel, title: String, date: Date?, message: Message?, numberOfNewReceivedMessages: Int, showGreenShield: Bool, showRedShield: Bool, aNewReceivedMessageDoesMentionOwnedIdentity: Bool, shouldMuteNotifications: Bool, isArchived: Bool, isPinned: Bool, isMuted: Bool) {
        self.avatarModel = avatarModel
        self.title = title
        self.date = date
        self.message = message
        self.numberOfNewReceivedMessages = numberOfNewReceivedMessages
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
        self.aNewReceivedMessageDoesMentionOwnedIdentity = aNewReceivedMessageDoesMentionOwnedIdentity
        self.shouldMuteNotifications = shouldMuteNotifications
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.isMuted = isMuted
    }
    
    public struct Message: Sendable, Equatable {
        let body: AttributedString
        let kind: Kind
        
        public init(body: AttributedString, kind: Kind) {
            self.body = body
            self.kind = kind
        }

        public enum Kind: Sendable, Equatable {
            case sent(status: SentStatus, messageHasMoreThanOneRecipient: Bool)
            case received
            case system
        }

        public enum SentStatus: Sendable, CaseIterable {
            case sentFromAnotherOwnedDevice
            case hasNoRecipient
            case couldNotBeSentToOneOrMoreRecipients
            case fullyDeliveredAndFullyRead
            case fullyDeliveredAndPartiallyRead
            case fullyDeliveredAndNotRead
            case partiallyDeliveredAndPartiallyRead
            case partiallyDeliveredNotRead
            case sent
            case processing
            case unprocessed
        }

    }
    
    static func emptyModel() -> Self {
        .init(avatarModel: .init(characterOrIcon: .character(" "), colors: .init(foreground: .clear, background: .clear), photoURL: nil),
              title: "",
              date: nil,
              message: .init(body: "", kind: .received),
              numberOfNewReceivedMessages: 0,
              showGreenShield: false,
              showRedShield: false,
              aNewReceivedMessageDoesMentionOwnedIdentity: false,
              shouldMuteNotifications: false,
              isArchived: false,
              isPinned: false,
              isMuted: false)
    }

}

@MainActor
public protocol DiscussionCellViewDataSource: AnyObject {

    func getInitialObvDiscussionCellViewModel(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) -> ObvDiscussionCellViewModel?
    func getAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionCellViewModel>)
    func finishAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, streamUUID: UUID)
    
    func getAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel.DiscussionIdentifier?>)
    func finishAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView, streamUUID: UUID)
}


@MainActor
protocol DiscussionCellViewActionsProtocol: AnyObject {
    func userWantsToNavigateToDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) throws
    func userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
    func userWantsToDeleteDiscussionButAsYetToConfirm(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
    func userWantsToArchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
    func userWantsToUnarchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
    func userWantsToMuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier, duration: ObvMuteDurationOption) async throws
    func userWantsToUnmuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
}

/// Expected to be implemented by the parent view
@MainActor
protocol DiscussionCellViewInternalActionsProtocol {
    func userTappedPinDiscussionButton(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier)
}


// MARK: - Main view: DiscussionCellView

public struct DiscussionCellView: View {
    
    let discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier
    let dataSource: DiscussionCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: DiscussionCellViewActionsProtocol
    let internalActions: DiscussionCellViewInternalActionsProtocol
    let initialViewModel: ObvDiscussionCellViewModel?

    static var count = 0
    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DiscussionCellView")

    init(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier, dataSource: DiscussionCellViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, actions: DiscussionCellViewActionsProtocol, internalActions: DiscussionCellViewInternalActionsProtocol) {
        self.discussionIdentifier = discussionIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.actions = actions
        self.internalActions = internalActions
        Self.count += 1
        Self.logger.debug("DiscussionCellView count: \(Self.count)")
        if let receivedModel = dataSource.getInitialObvDiscussionCellViewModel(discussionIdentifier: discussionIdentifier) {
            self.initialViewModel = receivedModel
        } else {
            self.initialViewModel = nil
        }
  }

    @State private var streamedViewModel: ObvDiscussionCellViewModel?
    
    private var viewModel: ObvDiscussionCellViewModel? {
        self.streamedViewModel ?? self.initialViewModel
    }
    
    /// Used under macOS to highlight the discussion cell corresponding to the discussion opened by the user
    @State private var userActivityDiscussionIdentifierViewModel: ObvDiscussionsListViewModel.DiscussionIdentifier?

    @State private var showingMuteActionSheet = false

    
    private func onTaskForAsyncStreamOfObvDiscussionCellViewModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvDiscussionCellViewModel(self, discussionIdentifier: discussionIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvDiscussionCellViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    
    private func onTaskForUserActivityDiscussionIdentifier() async {
        do {
            let (streamUUID, stream) = try dataSource.getAsyncStreamOfUserActivityDiscussionIdentifier(self)
            for await receivedModel in stream {
                withAnimation {
                    self.userActivityDiscussionIdentifierViewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfUserActivityDiscussionIdentifier(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }


    private func userTappedPinDiscussionButton() {
        internalActions.userTappedPinDiscussionButton(discussionIdentifier: discussionIdentifier)
    }

    
    private func userTappedArchiveDiscussionButton() {
        guard let viewModel else { return }
        Task {
            do {
                if viewModel.isArchived {
                    try await actions.userWantsToUnarchiveDiscussion(discussionIdentifier: discussionIdentifier)
                } else {
                    try await actions.userWantsToArchiveDiscussion(discussionIdentifier: discussionIdentifier)
                }
            } catch {
                assertionFailure()
            }
        }
    }

    
    private func userTappedDeleteDiscussionButton() {
        Task {
            do {
                try await actions.userWantsToDeleteDiscussionButAsYetToConfirm(discussionIdentifier: discussionIdentifier)
            } catch {
                // This happens when the user cancels
            }
        }
    }

    
    private func userTappedMarKAllAsReadButton() {
        Task {
            do {
                try await actions.userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier: discussionIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }

    
    private var muteActionSheetButtons: [ActionSheet.Button] {
        var buttons = [ActionSheet.Button]()
        buttons += ObvMuteDurationOption.allCases.map { duration in
            return Alert.Button.default(
                Text(duration.description),
                action: {
                    Task {
                        try? await actions.userWantsToMuteDiscussion(discussionIdentifier: self.discussionIdentifier, duration: duration)
                    }
                })
        }
        buttons += [.cancel()]
        return buttons
    }

    
    private func userWantsToUnmuteDiscussion() {
        Task {
            try? await actions.userWantsToUnmuteDiscussion(discussionIdentifier: self.discussionIdentifier)
        }
    }
    
    
    private var isPinned: Bool {
        viewModel?.isPinned ?? false
    }
    
    private func isUserActivity(_ discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) -> Bool {
        return userActivityDiscussionIdentifierViewModel == discussionIdentifier
    }
        
    
    @ViewBuilder
    private func leadingSwipeActions(viewModel: ObvDiscussionCellViewModel) -> some View {
        Button(action: userTappedMarKAllAsReadButton) {
            Label { Text("MARK_ALL_AS_READ") } icon: { Image(systemIcon: .envelopeOpen) }
        }
        Divider()
        if viewModel.isMuted {
            Button(action: userWantsToUnmuteDiscussion) {
                Label { Text("UNMUTE_DISCUSSION") } icon: { Image(systemIcon: .bellBadge) }
            }
            .tint(.cyan)
        } else {
            Button(action: { showingMuteActionSheet.toggle() }) {
                Label { Text("MUTE_DISCUSSION") } icon: { Image(systemIcon: .bellBadgeSlash) }
            }
            .tint(.cyan)
        }
        Button(action: userTappedPinDiscussionButton) {
            Label { Text(viewModel.isPinned ? "UNPIN_DISCUSSION" : "PIN_DISCUSSION") } icon: { Image(systemIcon:  viewModel.isPinned ? .pinSlashFill : .pinFill) }
        }
        .tint(viewModel.isPinned ? .orange : .green)
    }
    
    
    @ViewBuilder
    private func trailingSwipeActions(viewModel: ObvDiscussionCellViewModel) -> some View {
        Divider()
        Button(action: userTappedArchiveDiscussionButton) {
            Label { Text(viewModel.isArchived ? "UNARCHIVE_DISCUSSION" : "ARCHIVE_DISCUSSION") } icon: { Image(systemIcon: viewModel.isArchived ? .trayAndArrowUp : .archiveboxFill) }
        }
        .tint(viewModel.isArchived ? .green : .orange)
        Button(action: userTappedDeleteDiscussionButton) {
            Label { Text("DELETE_DISCUSSION") } icon: { Image(systemIcon: .trashFill) }
        }
        .tint(.red)
    }

    
    public var body: some View {
        DiscussionCellInternalView(discussionIdentifier: discussionIdentifier, viewModel: viewModel ?? .emptyModel(), dataSource: dataSource, avatarViewDataSource: avatarViewDataSource, actions: actions)
            .discussionCellBackground(isPinnedDiscussion: isPinned, isUserActivityDiscussion: isUserActivity(discussionIdentifier))
            .task(onTaskForAsyncStreamOfObvDiscussionCellViewModel)
            .task(onTaskForUserActivityDiscussionIdentifier)
            .actionSheet(isPresented: $showingMuteActionSheet) {
                ActionSheet(title: Text("MUTE_NOTIFICATIONS"),
                            buttons: muteActionSheetButtons)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if let viewModel {
                    leadingSwipeActions(viewModel: viewModel)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let viewModel {
                    trailingSwipeActions(viewModel: viewModel)
                }
            }
            .contextMenu {
                if let viewModel {
                    leadingSwipeActions(viewModel: viewModel)
                    trailingSwipeActions(viewModel: viewModel)
                }
            }
    }
}


// MARK: - Internal view: DiscussionCellInternalView


private struct DiscussionCellInternalView: View {
    
    let discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier
    let viewModel: ObvDiscussionCellViewModel
    let dataSource: DiscussionCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: DiscussionCellViewActionsProtocol

    private func cellTapped() {
        do {
            try actions.userWantsToNavigateToDiscussion(discussionIdentifier: discussionIdentifier)
        } catch {
            assertionFailure()
        }
    }
        
    
    /// Note that the following strange view hierarchy seems required to easily apply a distinct `.buttonStyle()` under iPhone and iPad/Mac
    var body: some View {
        Button(action: cellTapped) {
            DiscussionCellInternalViewButtonContent(discussionIdentifier: discussionIdentifier,
                                                    viewModel: viewModel,
                                                    avatarViewDataSource: avatarViewDataSource,
                                                    actions: actions)
        }
    }
    
}


private struct DiscussionCellInternalViewButtonContent: View {
    
    let discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier
    let viewModel: ObvDiscussionCellViewModel
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: DiscussionCellViewActionsProtocol

    var body: some View {
        HStack(alignment: .top) {
            
            //
            // Avatar
            //
            ObvAvatarView(model: viewModel.avatarModel, style: .circle, size: .normal, dataSource: avatarViewDataSource)
            
            VStack(alignment: .leading, spacing: 4) {
                
                //
                // First line
                //
                if #available(iOS 16, *) {
                    // Under iOS16+, we align the leading edge of the separator (required, as it otherwise automatically aligns on the character in the avatar view)
                    TitleView(viewModel: viewModel)
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                } else {
                    // Under iOS15, the separators are hidden (see `ObvDiscussionsListView`)
                    TitleView(viewModel: viewModel)
                }
                
                //
                // Second line
                //
                HStack(alignment: .center) {
                    // Preview of message's body
                    TextOfMessage(message: viewModel.message)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .font(.body)
                    Spacer()
                    // Badges
                    HStack(alignment: .firstTextBaseline) {
                        // Badge for mentions
                        if viewModel.aNewReceivedMessageDoesMentionOwnedIdentity {
                            BadgeForMentions()
                        }
                        // Badge for pinned discussions
                        if viewModel.isPinned {
                            BadgeForPinned()
                        }
                        // Badage for muted notifications, number of new messages, etc.
                        if viewModel.isArchived {
                            BadgeForArchive()
                        }
                        if viewModel.shouldMuteNotifications {
                            BadgeForMutedNotifications()
                        } else {
                            if viewModel.numberOfNewReceivedMessages > 0 {
                                ObvBadgeNumberOfNewMessages(numberOfNewReceivedMessages: viewModel.numberOfNewReceivedMessages)
                            } else {
                                // This hidden view prevents animation glitches due to the change in height when the BadgeNumberOfNewMessages really appears
                                ObvBadgeNumberOfNewMessages(numberOfNewReceivedMessages: 0)
                                    .opacity(0)
                                    .frame(width: 0)
                            }
                        }
                    }
                }
            }
        }
    }
    
}


private struct TitleView: View {
    
    let viewModel: ObvDiscussionCellViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // Title
            Text(viewModel.title)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .font(.system(.headline, design: .rounded))
            // Green shield
            if viewModel.showGreenShield {
                Image(systemIcon: .checkmarkShieldFill)
                    .foregroundColor(.green)
            }
            // Red shield
            if viewModel.showRedShield {
                Image(systemIcon: .exclamationmarkShieldFill)
                    .foregroundColor(.red)
            }
            Spacer()
            // Date
            if let date = viewModel.date {
                Text(date.discussionCellFormat)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
    
}


// MARK: - Internal view

private struct TextOfMessage: View {
    
    let message: ObvDiscussionCellViewModel.Message?
    
    private func iconForMessageKind(for sentStatus: ObvDiscussionCellViewModel.Message.SentStatus, messageHasMoreThanOneRecipient: Bool) -> any SymbolIcon {
        switch sentStatus {
        case .sentFromAnotherOwnedDevice:
            return SystemIcon.iphoneGen3CircleFill
        case .hasNoRecipient:
            return SystemIcon.circle
        case .couldNotBeSentToOneOrMoreRecipients:
            return SystemIcon.exclamationmarkCircle
        case .fullyDeliveredAndFullyRead:
            return messageHasMoreThanOneRecipient ? CustomIcon.checkmarkDoubleCircleFill : CustomIcon.checkmarkCircleFill
        case .fullyDeliveredAndPartiallyRead:
            return messageHasMoreThanOneRecipient ? CustomIcon.checkmarkDoubleCircleHalfFill : CustomIcon.checkmarkCircleFill
        case .fullyDeliveredAndNotRead:
            return messageHasMoreThanOneRecipient ? CustomIcon.checkmarkDoubleCircle : CustomIcon.checkmarkCircle
        case .partiallyDeliveredAndPartiallyRead:
            return CustomIcon.checkmarkCircleFill
        case .partiallyDeliveredNotRead:
            return CustomIcon.checkmarkCircle
        case .sent:
            return CustomIcon.checkmark
        case .processing:
            return SystemIcon.hare
        case .unprocessed:
            return SystemIcon.hourglass
        }
    }
    
    
    private let noIllustrativeMessage: AttributedString = {
        var subtitle = AttributedString(localizedInThisBundle: "BODY_WHEN_NO_ILLUSTRATIVE_MESSAGE_AVAILABLE")
        subtitle.font = .italic(forTextStyle: .subheadline)
        return subtitle
    }()
    

    var body: some View {
        if let message {
            switch message.kind {
            case .system:
                Text(message.body).font(.subheadline)
            case .received:
                Text(message.body).font(.subheadline)
            case .sent(status: let sentStatus, messageHasMoreThanOneRecipient: let messageHasMoreThanOneRecipient):
                let icon = iconForMessageKind(for: sentStatus, messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient)
                Text(Image(symbolIcon: icon)).font(.caption).baselineOffset(1) + Text(verbatim: " ") + Text(message.body).font(.subheadline)
            }
        } else {
            Text(noIllustrativeMessage).font(.subheadline)
        }
    }
    
}


// MARK: - Internal view: various badges

private struct BadgeForMentions: View {
    var body: some View {
        Image(systemIcon: AppTheme.shared.icons.mentionnedIcon)
            .font(.caption)
            .foregroundColor(.red)
    }
}


private struct BadgeForMutedNotifications: View {
    var body: some View {
        Image(systemIcon: AppTheme.shared.icons.muteIcon)
            .font(.caption)
            .foregroundColor(.gray)
    }
}


private struct BadgeForArchive: View {
    var body: some View {
        Image(systemIcon: AppTheme.shared.icons.archivebox)
            .font(.caption)
            .foregroundColor(.gray)
    }
}


private struct BadgeForPinned: View {
    var body: some View {
        Image(systemIcon: .pinFill)
            .font(.caption)
            .rotationEffect(.degrees(30), anchor: .center)
            .foregroundColor(.yellow)
    }
}


/// Allows to define a view modifiter that adapts to the platform type and to the pinned/unpinned attribute of a discussion to apply an appropriate
/// background to a `DiscussionCellView`.
private struct DiscussionCellBackground: ViewModifier {
    
    private let isPinnedDiscussion: Bool
    private let isUserActivityDiscussion: Bool
    
    init(isPinnedDiscussion: Bool, isUserActivityDiscussion: Bool) {
        self.isUserActivityDiscussion = isUserActivityDiscussion
        self.isPinnedDiscussion = isPinnedDiscussion
    }
    
    private var trailingPadding: CGFloat {
        if isPhone {
            return 0
        } else {
            return ObvAppCoreConstants.targetEnvironmentIsMacCatalyst ? 12 : 6
        }
    }
    
    private var leadingPadding: CGFloat {
        if isPhone {
            return 0
        } else {
            return ObvAppCoreConstants.targetEnvironmentIsMacCatalyst ? 12 : 6
        }
    }
    
    private var verticalPadding: CGFloat {
        isPhone ? 0 : 2
    }
    
    private var rectangleBackgroundColor: Color {
        if isPhone {
            return isPinnedDiscussion ? Color(.quaternarySystemFill) : Color(.systemBackground)
        } else {
            return isUserActivityDiscussion ? .blue : .clear
        }
    }
    
    private var foregroundColor: Color {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .primary
        } else {
            return isUserActivityDiscussion ? .white : .primary
        }
    }
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    private var cornerSize: CGSize {
        isPhone ? .zero : CGSize(width: 12, height: 12)
    }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerSize:cornerSize, style: .continuous)
                    .foregroundStyle(rectangleBackgroundColor)
                    .padding(.vertical, verticalPadding)
                    .padding(.trailing, trailingPadding)
                    .padding(.leading, leadingPadding)
            )
            .foregroundStyle(foregroundColor)
    }

}


extension View {
    
    /// View modifier that adapts to the platform type and to the pinned/unpinned attribute of a discussion to apply an appropriate
    /// background to a `DiscussionCellView`.
    public func discussionCellBackground(isPinnedDiscussion: Bool, isUserActivityDiscussion: Bool) -> some View {
        self.modifier(DiscussionCellBackground(isPinnedDiscussion: isPinnedDiscussion, isUserActivityDiscussion: isUserActivityDiscussion))
    }
    
}
