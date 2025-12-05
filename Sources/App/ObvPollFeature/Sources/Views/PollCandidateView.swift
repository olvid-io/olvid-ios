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
import ObvAccessibility

@available(iOS 17.0, *)
public protocol PollCandidateViewDataSource: VoteViewDataSource {
    func getInitialPollCandidateViewModel(candidateIdentifier: PollCandidateIdentifier) -> PollCandidateViewModel?
    func getAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, candidateIdentifier: PollCandidateIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<PollCandidateViewModel>)
    func finishAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, streamUUID: UUID)
}


public struct PollCandidateViewModel: Equatable, Sendable {
    
    public let candidateIdentifier: PollCandidateIdentifier
    public let identifiersOfVotes: [PollVoteViewModel.VoteIdentifier]
    
    public init(candidateIdentifier: PollCandidateIdentifier, identifiersOfVotes: [PollVoteViewModel.VoteIdentifier]) {
        self.candidateIdentifier = candidateIdentifier
        self.identifiersOfVotes = identifiersOfVotes
    }
    
}

// MARK: - PollCandidateView

/// When the user displays the details of a poll, she can tap a specific candidate to display the list of answers (votes) for that candidate.
/// This view is the list of those answers (votes) for that particluar candidate.
@available(iOS 17.0, *)
public struct PollCandidateView: View {
    
    private let pollCandidateIdentifier: PollCandidateIdentifier
    private let dataSource: PollCandidateViewDataSource
    private let avatarViewDataSource: ObvAvatarViewDataSource
    
    private let initialViewModel: PollCandidateViewModel?
    @State private var streamedViewModel: PollCandidateViewModel?
    
    private var viewModel: PollCandidateViewModel? {
        self.streamedViewModel ?? self.initialViewModel
    }
    
    init(pollCandidateIdentifier: PollCandidateIdentifier, dataSource: PollCandidateViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource) {
        self.pollCandidateIdentifier = pollCandidateIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        if let viewModel = dataSource.getInitialPollCandidateViewModel(candidateIdentifier: pollCandidateIdentifier) {
            self.initialViewModel = viewModel
        } else {
            self.initialViewModel = nil
        }
    }
    
    
    func onTaskForAsyncStreamOfPollCandidateViewModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfPollCandidateViewModel(self, candidateIdentifier: pollCandidateIdentifier)
            for await model in stream {
                withAnimation {
                    self.streamedViewModel = model
                }
            }
            dataSource.finishAsyncStreamOfPollCandidateViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    
    @ViewBuilder
    var content: some View {
        if let viewModel {
            List {
                Section {
                    ForEach(viewModel.identifiersOfVotes) { voteIdentifier in
                        HStack(alignment: .center, spacing: 4.0) {
                            VoteView(voteIdentifier: voteIdentifier, dataSource: dataSource, avatarViewDataSource: avatarViewDataSource)
                                .obvAccessibleComponent()
                        }
                    }
                    .padding(.vertical, 14)
                } header: {
                    Text("POLL_TITLE_\(viewModel.identifiersOfVotes.count)")
                        .textCase(.uppercase)
                }
            }
        } else {
            ProgressView()
        }
    }
    
    public var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .task(onTaskForAsyncStreamOfPollCandidateViewModel)
    }
}










// MARK: - CandidateView

public struct PollVoteViewModel: Sendable, Equatable, Hashable, Identifiable {
    
    public let identifier: VoteIdentifier
    public let name: String
    public let timestamp: Date
    public let avatarModel: ObvAvatarViewModel
    
    public var id: VoteIdentifier { identifier }
    
    public enum VoteIdentifier: Identifiable, Sendable, Equatable, Hashable {
        case pollVoteObjectID(NSManagedObjectID) // ObjectID of a PersistedPollVote
        case forPreviews(UUID)
        public var id: Data {
            switch self {
            case .pollVoteObjectID(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            case .forPreviews(let uuid):
                return uuid.uuidString.data(using: .utf8)!
            }
        }
    }
    
    public init(identifier: VoteIdentifier, name: String, timestamp: Date, avatarModel: ObvAvatarViewModel) {
        self.identifier = identifier
        self.name = name
        self.timestamp = timestamp
        self.avatarModel = avatarModel
    }
}


@MainActor
public protocol VoteViewDataSource {
    func getInitialPollVoteViewModel(voteIdentifier: PollVoteViewModel.VoteIdentifier) -> PollVoteViewModel?
    func getAsyncStreamOfPollVoteViewModel(_ view: VoteView, voteIdentifier: PollVoteViewModel.VoteIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<PollVoteViewModel>)
    func finishAsyncStreamOfPollVoteViewModel(_ view: VoteView, streamUUID: UUID)
}


public struct VoteView: View, ObvAccessibilityProvidableView {
    
    let voteIdentifier: PollVoteViewModel.VoteIdentifier
    let dataSource: VoteViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    
    private let initialViewModel: PollVoteViewModel?
    @State private var streamedViewModel: PollVoteViewModel?
    
    private var vote: PollVoteViewModel? {
        streamedViewModel ?? initialViewModel
    }
    
    private var relativeDateFormatter: DateFormatter {
        let relativeDateFormatter = DateFormatter()
        relativeDateFormatter.timeStyle = .none
        relativeDateFormatter.dateStyle = .medium
        relativeDateFormatter.doesRelativeDateFormatting = true
        return relativeDateFormatter
    }
    
    private var relativeTimeFormatter: DateFormatter {
        let relativeDateFormatter = DateFormatter()
        relativeDateFormatter.timeStyle = .short
        relativeDateFormatter.dateStyle = .none
        relativeDateFormatter.doesRelativeDateFormatting = true
        return relativeDateFormatter
    }
    
    init(voteIdentifier: PollVoteViewModel.VoteIdentifier, dataSource: VoteViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource) {
        self.voteIdentifier = voteIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        if let viewModel = dataSource.getInitialPollVoteViewModel(voteIdentifier: voteIdentifier) {
            self.initialViewModel = viewModel
        } else {
            self.initialViewModel = nil
        }
    }
    
    public var accessibilityAttributes: ObvAccessibilityAttributes {
        if let vote {
            return .init(label: vote.name,
                         value: relativeDateFormatter.string(from: vote.timestamp) + " " + relativeTimeFormatter.string(from: vote.timestamp),
                         actions: nil,
                         hint: nil,
                         traits: [.isStaticText])
        } else {
            return .init(label: String(localizedInThisBundle: "LOADING_IN_PROGRESS"),
                         value: nil,
                         actions: nil,
                         hint: nil,
                         traits: [.isStaticText])
        }
    }
    
    private func onTaskForAsyncStreamOfPollCandidateVoteViewModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfPollVoteViewModel(self, voteIdentifier: voteIdentifier)
            for await model in stream {
                withAnimation {
                    self.streamedViewModel = model
                }
            }
            dataSource.finishAsyncStreamOfPollVoteViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    @ViewBuilder
    var content: some View {
        if let vote {
            HStack(alignment: .center, spacing: 4.0) {
                ObvAvatarView(model: vote.avatarModel,
                              style: .squircle,
                              size: .small,
                              dataSource: avatarViewDataSource)
                
                Text(vote.name)
                    .padding(.horizontal, 8.0)
                Spacer()
                Text(vote.timestamp, formatter: relativeDateFormatter)
                    .foregroundStyle(Color.secondary)
                Text(vote.timestamp, style: .time)
            }
        } else {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
    }
    
    public var body: some View {
        content
            .task(onTaskForAsyncStreamOfPollCandidateVoteViewModel)
    }
    
}










// MARK: - Previews for VoteView

#if DEBUG

private final class VoteViewDataSourceForPreviews: VoteViewDataSource, ObvAvatarViewDataSource {
    
    func getInitialPollVoteViewModel(voteIdentifier: PollVoteViewModel.VoteIdentifier) -> PollVoteViewModel? {
        // return PollVoteViewModel.sampleDatasForIdentifier(voteIdentifier)
        return nil // We test the async stream
    }
    
    func getAsyncStreamOfPollVoteViewModel(_ view: VoteView, voteIdentifier: PollVoteViewModel.VoteIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<PollVoteViewModel>) {
        let stream = AsyncStream(PollVoteViewModel.self) { (continuation: AsyncStream<PollVoteViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 2)
                guard let model = PollVoteViewModel.sampleDatasForIdentifier(voteIdentifier) else { return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfPollVoteViewModel(_ view: VoteView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


private let voteViewDataSourceForPreviews = VoteViewDataSourceForPreviews()

#Preview("VoteView") {
    if #available(iOS 17.0, *) {
        VoteView(voteIdentifier: PollVoteViewModel.VoteIdentifier.sampleDatas[0],
                 dataSource: voteViewDataSourceForPreviews,
                 avatarViewDataSource: voteViewDataSourceForPreviews)
    }
}

// MARK: - Previews for PollCandidateView

@available(iOS 17, *)
private final class PollCandidateViewDataSourceForPreviews: PollCandidateViewDataSource, ObvAvatarViewDataSource {
    
    func getInitialPollCandidateViewModel(candidateIdentifier: PollCandidateIdentifier) -> PollCandidateViewModel? {
        //let model = PollCandidateViewModel.sampleData
        return nil // Testing the stream
    }
    
    func getAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, candidateIdentifier: PollCandidateIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<PollCandidateViewModel>) {
        let stream = AsyncStream(PollCandidateViewModel.self) { (continuation: AsyncStream<PollCandidateViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 2)
                let model = PollCandidateViewModel.sampleData
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func getInitialPollVoteViewModel(voteIdentifier: PollVoteViewModel.VoteIdentifier) -> PollVoteViewModel? {
        //let model = PollVoteViewModel.sampleDatasForIdentifier(voteIdentifier)
        return nil // Testing the stream
    }
    
    func getAsyncStreamOfPollVoteViewModel(_ view: VoteView, voteIdentifier: PollVoteViewModel.VoteIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<PollVoteViewModel>) {
        let stream = AsyncStream(PollVoteViewModel.self) { (continuation: AsyncStream<PollVoteViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 2)
                guard let model = PollVoteViewModel.sampleDatasForIdentifier(voteIdentifier) else { return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfPollVoteViewModel(_ view: VoteView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

@available(iOS 17, *)
private let pollCandidateViewDataSourceForPreviews = PollCandidateViewDataSourceForPreviews()

#Preview("PollCandidateView") {
    if #available(iOS 17.0, *) {
        PollCandidateView(
            pollCandidateIdentifier: PollCandidateIdentifier.sampleDatas[0],
            dataSource: pollCandidateViewDataSourceForPreviews,
            avatarViewDataSource: pollCandidateViewDataSourceForPreviews)
    }
}

#endif

