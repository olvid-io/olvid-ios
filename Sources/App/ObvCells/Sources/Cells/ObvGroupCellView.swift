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
import ObvDesignSystem
import ObvAppTypes

// MARK: - Internal view: GroupCellView


public struct ObvGroupCellViewModel: Sendable, Equatable {
    
    let groupIdentifier: ObvAppTypes.ObvGroupIdentifier? // Allowed to be nil to make it possible to create an empty model. The dataSource should return a value
    let avatarModel: ObvAvatarViewModel
    let title: String
    let listOfGroupMemberNames: String
    let showGreenShield: Bool
    let hasUpdatedDetails: HasUpdatedDetails
    let updateInProgress: Bool
    
    public enum GroupIdentifier: Sendable, Equatable, Hashable, Identifiable {
        case obvGroupIdentifier(ObvGroupIdentifier)
        case objectIDOfDisplayedContactGroup(NSManagedObjectID)
        public var objectID: NSManagedObjectID? {
            switch self {
            case .obvGroupIdentifier: return nil
            case .objectIDOfDisplayedContactGroup(let objectID): return objectID
            }
        }
        public var id: Data {
            switch self {
            case .obvGroupIdentifier(let groupIdentifier):
                switch groupIdentifier {
                case .groupV1(let obvGroupV1Identifier):
                    return obvGroupV1Identifier.id
                case .groupV2(let obvGroupV2Identifier):
                    return obvGroupV2Identifier.id
                }
            case .objectIDOfDisplayedContactGroup(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            }
        }
    }
    

    public init(groupIdentifier: ObvAppTypes.ObvGroupIdentifier?, avatarModel: ObvAvatarViewModel, title: String, listOfGroupMemberNames: String, showGreenShield: Bool, hasUpdatedDetails: HasUpdatedDetails, updateInProgress: Bool) {
        self.groupIdentifier = groupIdentifier
        self.avatarModel = avatarModel
        self.title = title
        self.listOfGroupMemberNames = listOfGroupMemberNames
        self.showGreenShield = showGreenShield
        self.hasUpdatedDetails = hasUpdatedDetails
        self.updateInProgress = updateInProgress
    }
    
    public enum HasUpdatedDetails: Sendable, Equatable {
        case noNewPublishedDetails
        case seenPublishedDetails
        case unseenPublishedDetails
    }
    
    static func emptyModel() -> Self {
        .init(groupIdentifier: nil,
              avatarModel: .init(characterOrIcon: .icon(.person3), colors: .init(foreground: .clear, background: .clear), photoURL: nil),
              title: " ",
              listOfGroupMemberNames: " ",
              showGreenShield: false,
              hasUpdatedDetails: .noNewPublishedDetails,
              updateInProgress: false)
    }
    
}


@MainActor
public protocol ObvGroupCellViewDataSource: AnyObject {
    
    func getAsyncStreamOfObvGroupCellViewModel(_ view: ObvGroupCellView, groupIdentifier: ObvGroupCellViewModel.GroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupCellViewModel>)
    func finishAsyncStreamOfObvGroupCellViewModel(_ view: ObvGroupCellView, streamUUID: UUID)

}


@MainActor
public protocol ObvGroupCellViewNavigation {
    func userDidPressOnObvGroupCellView(_ view: ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvGroupCellView.ExpectedNavigation) throws
}


// MARK: - GroupCellView

public struct ObvGroupCellView: View {
    
    static var counter = 0
    
    private let groupIdentifier: ObvGroupCellViewModel.GroupIdentifier
    private let dataSource: ObvGroupCellViewDataSource
    private let avatarViewDataSource: ObvAvatarViewDataSource
    private let navigation: any ObvGroupCellViewNavigation
    @Binding var highlightedGroupIdentifier: ObvGroupCellViewModel.GroupIdentifier?
    let expectedNavigationOnTap: ObvGroupCellView.ExpectedNavigation
    
    public init(groupIdentifier: ObvGroupCellViewModel.GroupIdentifier,
                expectedNavigationOnTap: ObvGroupCellView.ExpectedNavigation,
                dataSource: ObvGroupCellViewDataSource,
                avatarViewDataSource: ObvAvatarViewDataSource,
                navigation: any ObvGroupCellViewNavigation,
                highlightedGroupIdentifier: Binding<ObvGroupCellViewModel.GroupIdentifier?>) {
        self.groupIdentifier = groupIdentifier
        self.expectedNavigationOnTap = expectedNavigationOnTap
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.navigation = navigation
        self._highlightedGroupIdentifier = highlightedGroupIdentifier
    }

    @State private var streamedViewModel: ObvGroupCellViewModel?

    private var viewModel: ObvGroupCellViewModel? {
        self.streamedViewModel
    }

    private func onTaskForAsyncStreamOfObvGroupCellViewModel() async {
        do {
            Self.counter += 1
            //print("😎 counter: \(Self.counter)")
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvGroupCellViewModel(self, groupIdentifier: self.groupIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvGroupCellViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    private func buttonTapped() {
        guard let groupIdentifier = streamedViewModel?.groupIdentifier else {
            assertionFailure("The data source must return a non-nil value for the groupIdentifier")
            return
        }
        do {
            try navigation.userDidPressOnObvGroupCellView(self, groupIdentifier: groupIdentifier, expectedNavigation: expectedNavigationOnTap)
        } catch {
            assertionFailure()
        }
    }
    
    public var body: some View {
        GroupCellButton(viewModel: viewModel ?? .emptyModel(),
                        avatarViewDataSource: avatarViewDataSource,
                        action: buttonTapped,
                        isHiglihted: highlightedGroupIdentifier == groupIdentifier)
        .task(onTaskForAsyncStreamOfObvGroupCellViewModel)
    }
    
}

extension ObvGroupCellView {
 
    public enum ExpectedNavigation {
        case groupDiscussion
        case groupDetails
    }
    
}

extension ObvGroupCellView {
    
    public struct Constant {
        
        /// Horizontal spacing between the trailing of the avatar, and the leading of the text.
        /// Makes it possible to properly align the leading edge of the divider between cells with
        /// the leading of the text.
        public static let horizontalSpacingBetweenAvatarAndText: CGFloat = 8
    }
    
}



private struct GroupCellButton: View {
    
    let viewModel: ObvGroupCellViewModel
    let avatarViewDataSource: ObvAvatarViewDataSource
    let action: () -> Void
    let isHiglihted: Bool

    public var body: some View {
        Button(action: action) {
            HStack {
                GroupCellButtonContentView(viewModel: viewModel, avatarViewDataSource: avatarViewDataSource)
                ObvChevronRight(isHiglihted: isHiglihted)
            }
            .contentShape(Rectangle()) // Makes the entire HStack tappable
        }
        .buttonStyle(.plain)
    }
    
}


// MARK: Internal view: GroupCellInternalView

private struct GroupCellButtonContentView: View {
    
    let viewModel: ObvGroupCellViewModel
    let avatarViewDataSource: ObvAvatarViewDataSource

    var body: some View {
        HStack(alignment: .center) {
            
            HStack(spacing: ObvGroupCellView.Constant.horizontalSpacingBetweenAvatarAndText) {
            
                //
                // Avatar
                //
                ObvAvatarView(model: viewModel.avatarModel,
                              style: .circle,
                              size: .normal,
                              dataSource: avatarViewDataSource)
                
                //
                // Texts
                //
                
                VStack(alignment: .leading, spacing: 4) {
                    
                    //
                    // First line
                    //
                    if #available(iOS 16, *) {
                        TitleView(viewModel: viewModel)
                            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] } // In case the cell is included in a List (not required for a LazyVStack)
                    } else {
                        TitleView(viewModel: viewModel)
                    }

                    //
                    // Second line
                    //
                    // List of group member names
                    if !viewModel.listOfGroupMemberNames.trimmingWhitespacesAndNewlines().isEmpty {
                        Text(viewModel.listOfGroupMemberNames)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }

                }
                
            }
                        
            //
            // Unseen details badge
            //

            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline) {
                    if viewModel.updateInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        switch viewModel.hasUpdatedDetails {
                        case .noNewPublishedDetails:
                            EmptyView()
                        case .seenPublishedDetails:
                            Image(systemIcon: .personTextRectangle)
                                .foregroundStyle(.secondary)
                        case .unseenPublishedDetails:
                            Image(systemIcon: .personTextRectangle)
                                .foregroundColor(.red)
                        }
                    }
                }
            }

        }

    }
    
}



// MARK: Internal view: TitleView

private struct TitleView: View {
    
    let viewModel: ObvGroupCellViewModel

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
            Spacer()
        }
    }
    
}



#if DEBUG

private final class DataSourceAndActionsForPreviews {
    
}


extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


extension DataSourceAndActionsForPreviews: ObvGroupCellViewDataSource {
    
    func getAsyncStreamOfObvGroupCellViewModel(_ view: ObvGroupCellView, groupIdentifier: ObvGroupCellViewModel.GroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupCellViewModel>) {
        let stream = AsyncStream<ObvGroupCellViewModel> { (continuation: AsyncStream<ObvGroupCellViewModel>.Continuation) in
            Task {
                while true {
                    do {
                        try? await Task.sleep(seconds: 2)
                        let viewModel = viewModelForPreviews
                        continuation.yield(viewModel)
                    }
                    do {
                        try? await Task.sleep(seconds: 2)
                        let viewModel = ObvGroupCellViewModel(
                            groupIdentifier: .groupV2(.sampleData),
                            avatarModel: .sampleData,
                            title: viewModelForPreviews.title,
                            listOfGroupMemberNames: "Alice",
                            showGreenShield: false,
                            hasUpdatedDetails: .noNewPublishedDetails,
                            updateInProgress: true)
                        continuation.yield(viewModel)
                    }
                    do {
                        try? await Task.sleep(seconds: 2)
                        let viewModel = ObvGroupCellViewModel(
                            groupIdentifier: .groupV2(.sampleData),
                            avatarModel: .sampleData,
                            title: viewModelForPreviews.title,
                            listOfGroupMemberNames: "Alice",
                            showGreenShield: false,
                            hasUpdatedDetails: .unseenPublishedDetails,
                            updateInProgress: false)
                        continuation.yield(viewModel)
                    }
                    do {
                        try? await Task.sleep(seconds: 2)
                        let viewModel = ObvGroupCellViewModel(
                            groupIdentifier: .groupV2(.sampleData),
                            avatarModel: .sampleData,
                            title: viewModelForPreviews.title,
                            listOfGroupMemberNames: "Alice",
                            showGreenShield: false,
                            hasUpdatedDetails: .seenPublishedDetails,
                            updateInProgress: true)
                        continuation.yield(viewModel)
                    }
                }
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvGroupCellViewModel(_ view: ObvGroupCellView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


extension DataSourceAndActionsForPreviews: ObvGroupCellViewNavigation {
    
    func userDidPressOnObvGroupCellView(_ view: ObvGroupCellView, groupIdentifier: ObvGroupIdentifier, expectedNavigation: ObvGroupCellView.ExpectedNavigation) throws {
        print("User did press on ObvGroupCellView")
    }

}


@MainActor
private let viewModelForPreviews = ObvGroupCellViewModel.sampleData

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()


#Preview {
    List {
        ObvGroupCellView(groupIdentifier: .obvGroupIdentifier(.sampleData),
                         expectedNavigationOnTap: .groupDetails,
                         dataSource: dataSourceAndActionsForPreviews,
                         avatarViewDataSource: dataSourceAndActionsForPreviews,
                         navigation: dataSourceAndActionsForPreviews,
                         highlightedGroupIdentifier: .constant(.none))
    }
}

#endif
