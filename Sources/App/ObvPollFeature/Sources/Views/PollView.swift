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
import Charts
import ObvDesignSystem
import ObvAppCoreConstants
import ObvAccessibility
import ObvTypes


@MainActor
@available(iOS 17.0, *)
public protocol PollViewDataSourceProtocol: AnyObject, PollCandidateViewDataSource, VoterWhoDidNotVoteYetViewDataSource {
    func getInitialPollViewModel(pollIdentifier: PollIdentifier, candidatesSortOrder: PollViewModel.CandidatesSortOrder) -> PollViewModel?
    func getAsyncStreamOfPollViewModel(_ view: PollView, pollIdentifier: PollIdentifier, candidatesSortOrder: PollViewModel.CandidatesSortOrder) async throws -> (streamUUID: UUID, stream: AsyncStream<PollViewModel>)
    func changeSortOrderOfAsyncStreamOfPollViewModel(to newSortOrder: PollViewModel.CandidatesSortOrder, streamUUID: UUID)
    func finishAsyncStreamOfPollViewModel(_ view: PollView, streamUUID: UUID)
}


public struct PollViewModel: Sendable, Equatable {
    
    let question: String
    let candidates: [PollViewCandidateModel]
    let identifiersOfVotersWhoDidNotVoteYet: [VoterWhoDidNotVoteYetViewModel.VoterIdentifier]
    let totalNumberOfResponses: Int
    let candidatesWithResponses: [PollViewCandidateModel]
    
    public init(question: String, candidates: [PollViewCandidateModel], identifiersOfVotersWhoDidNotVoteYet: [VoterWhoDidNotVoteYetViewModel.VoterIdentifier]) {
        self.question = question
        self.candidates = candidates
        self.identifiersOfVotersWhoDidNotVoteYet = identifiersOfVotersWhoDidNotVoteYet
        self.totalNumberOfResponses = candidates.reduce(0) { $0 + $1.numberOfResponses }
        self.candidatesWithResponses = candidates
            .filter { $0.numberOfResponses > 0 }
            .sorted(by: { $0.pollSortIndex < $1.pollSortIndex })
    }
    
    func isTopCandidate(for candidate: PollViewCandidateModel) -> Bool {
        let maxNumberOfResponses = candidates.reduce(0) { max($0, $1.numberOfResponses) }
        return candidate.numberOfResponses >= maxNumberOfResponses
    }
    
    public enum CandidatesSortOrder: Int, CaseIterable, Sendable {
        case pollOrder = 0
        case numberOfResponses = 1
        
        var title: Text {
            switch self {
            case .pollOrder:
                Text("POLL_ANSWERS_SORT_DEFAULT")
            case .numberOfResponses:
                Text("POLL_ANSWERS_SORT_NUMBER")
            }
        }
        
        static let allCasesOrdered = [CandidatesSortOrder.pollOrder, .numberOfResponses]
    }
    
}


public enum PollIdentifier: Equatable, Hashable, Sendable {
    case persistedPollObjectID(NSManagedObjectID)
    case forPreviews
}

// MARK: - PollView

/// Main view that displays the details of an ongoing poll. It shows a pie chart, the poll question, the list of votes (answers),
/// and the list of the voters who did not vote yet.
@available(iOS 17.0, *)
public struct PollView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    let pollIdentifier: PollIdentifier
    let router: PollRouter
    var dataSource: PollViewDataSourceProtocol { router.dataSource }
    var avatarViewDataSource: ObvAvatarViewDataSource { router.avatarViewDataSource }
    
    var initialViewModel: PollViewModel?
    @State private var streamedViewModel: PollViewModel?
    @State private var currentStreamUUID: UUID?
    
    private var viewModel: PollViewModel? {
        self.streamedViewModel ?? self.initialViewModel
    }

    @State private var sortOrder: PollViewModel.CandidatesSortOrder = .pollOrder
    
    private func onTaskForAsyncStreamOfPollViewModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfPollViewModel(self, pollIdentifier: pollIdentifier, candidatesSortOrder: sortOrder)
            self.currentStreamUUID = streamUUID
            for await model in stream {
                withAnimation {
                    self.streamedViewModel = model
                }
            }
            dataSource.finishAsyncStreamOfPollViewModel(self, streamUUID: streamUUID)
            self.currentStreamUUID = nil
        } catch {
            assertionFailure()
        }
    }

    private func onChangeOfSortOrder(_ oldSortOrder: PollViewModel.CandidatesSortOrder, _ newSortOrder: PollViewModel.CandidatesSortOrder) {
        guard let currentStreamUUID else { assertionFailure(); return }
        dataSource.changeSortOrderOfAsyncStreamOfPollViewModel(to: newSortOrder, streamUUID: currentStreamUUID)
    }

    func color(for candidate: PollViewCandidateModel) -> Color {
        let colorIndex = candidate.pollSortIndex % Color.pollColors.count
        return Color.pollColors[colorIndex]
    }
    
    func chartForegroundStyleScale() -> [Color] {
        
        guard let viewModel else { return [] }
        
        var resultColors = [Color]()
        viewModel.candidatesWithResponses.forEach { candidate in
            let color = color(for: candidate)
            resultColors.append(color)
        }
        return resultColors
    }
        
    init(pollIdentifier: PollIdentifier,
         router: PollRouter) {
        self.pollIdentifier = pollIdentifier
        self.router = router
        if let viewModel = dataSource.getInitialPollViewModel(pollIdentifier: pollIdentifier, candidatesSortOrder: sortOrder) {
            self.initialViewModel = viewModel
        } else {
            self.initialViewModel = nil
        }
    }
    
    @ViewBuilder
    var pieChart: some View {
        if let viewModel = self.viewModel {
            //let _ = Self._printChanges() // Use to print changes to observable
            Chart(viewModel.candidatesWithResponses) { candidate in
                SectorMark(angle: .value("Count", candidate.numberOfResponses),
                           innerRadius: viewModel.isTopCandidate(for: candidate) ? .ratio(0.5) : .ratio(0.55),
                           outerRadius: viewModel.isTopCandidate(for: candidate) ? .ratio(1) : .ratio(0.9),
                           angularInset: 1)
                .annotation(position: .overlay) {
                    if candidate.totalPercent >= 5 {
                        Text(verbatim: "\(Int(candidate.totalPercent))%")
                            .foregroundStyle(Color(UIColor.secondarySystemGroupedBackground))
                            .font(.callout)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 2, x:0, y: 0)
                .cornerRadius(5)
                .foregroundStyle(by: .value("Responses", candidate.text))
            }
            .chartLegend(.hidden)
            .chartForegroundStyleScale(range: chartForegroundStyleScale())
            .accessibilityHidden(true)
        }
    }
      
    
    @ViewBuilder
    var content: some View {
        if let viewModel {
            List {
                
                // Pie Chart
                
                if !viewModel.candidatesWithResponses.isEmpty {
                    if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                        pieChart
                            .listRowBackground(Color.clear)
                    } else {
                        pieChart
                            .scaledToFit()
                            .listRowBackground(Color.clear)
                    }
                }
                
                // The poll's question
                
                Section {
                    Text(viewModel.question)
                        .padding(.vertical, 14)
                }
                
                // The list of candidates
                
                if !viewModel.candidatesWithResponses.isEmpty {
                    Section {
                        ForEach(viewModel.candidates) { candidate in
                            CandidateView(
                                model: candidate,
                                color: color(for: candidate),
                                avatarViewDataSource: avatarViewDataSource) {
                                    router.navigateTo(.candidateInfos(title: candidate.text, pollCandidateIdentifier: candidate.identifier))
                                }
                                .obvAccessibleComponent()
                                .contentShape(Rectangle())
                            .onTapGesture {
                                router.navigateTo(.candidateInfos(title: candidate.text, pollCandidateIdentifier: candidate.identifier))
                            }
                        }
                    } header: {
                        HStack(alignment: .lastTextBaseline, spacing: 2.0) {
                            Text("POLL_TITLE_\(viewModel.totalNumberOfResponses)")
                                .textCase(.uppercase)
                            Spacer()
                            Menu {
                                ForEach(PollViewModel.CandidatesSortOrder.allCasesOrdered, id: \.rawValue) { sortOrder in
                                    Button(action: {
                                        withAnimation {
                                            self.sortOrder = sortOrder
                                        }
                                    }) {
                                        HStack {
                                            sortOrder.title
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("POLL_SORT_TITLE")
                                        .font(.callout)
                                    Image(systemIcon: .chevronUpChevronDown)
                                }
                                .foregroundStyle((Color(uiColor: .label)))
                            }
                        }
                    }
                    .textCase(nil) //https://developer.apple.com/forums/thread/655524
                }
                
                if !viewModel.identifiersOfVotersWhoDidNotVoteYet.isEmpty {
                    Section {
                        ForEach(viewModel.identifiersOfVotersWhoDidNotVoteYet) { voterIdentifier in
                            VoterWhoDidNotVoteYetView(voterIdentifier: voterIdentifier,
                                                      dataSource: dataSource,
                                                      avatarViewDataSource: avatarViewDataSource)
                                .obvAccessibleComponent()
                        }
                        .padding(.vertical, 14)
                    } header: {
                        Text("POLL_WAITING_ANSWERS")
                    }
                    
                }
                
                
            }
            
        } else {
            ProgressView()
        }
    }
    
    public var body: some View {
        //        let _ = Self._printChanges() // Use to print changes to observable
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(Text("POLL_TITLE"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("POLL_CLOSE")
                    }
                }
            }
            .task(onTaskForAsyncStreamOfPollViewModel)
            .onChange(of: sortOrder, onChangeOfSortOrder)
    }
    
}


// MARK: - CandidateView

public enum PollCandidateIdentifier: Equatable, Sendable, Identifiable, Hashable {
    case pollCandidateObjectID(NSManagedObjectID)
    case forPreviews(pollIdentifier: PollIdentifier, candidateUUID: UUID)
    public var id: Data {
        switch self {
        case .pollCandidateObjectID(let objectID):
            return objectID.uriRepresentation().dataRepresentation
        case .forPreviews(pollIdentifier: _, candidateUUID: let candidateUUID):
            return candidateUUID.uuidString.data(using: .utf8)!
        }
    }
}


public struct PollViewCandidateModel: Sendable, Equatable, Hashable, Identifiable {
    
    let identifier: PollCandidateIdentifier
    let text: String
    let isVotedByOwnedIdentity: IsVotedByOwnedIdentity
    let numberOfResponses: Int
    let totalNumberOfResponses: Int
    let totalPercent: Double
    let pollSortIndex: Int // The sort index in the poll
    
    public var id: PollCandidateIdentifier { identifier }
    
    public enum IsVotedByOwnedIdentity: Sendable, Equatable, Hashable {
        case no
        case yes(avatarModelOfOwnedIdentity: ObvAvatarViewModel)
    }
    
    public init(identifier: PollCandidateIdentifier, text: String, isVotedByOwnedIdentity: IsVotedByOwnedIdentity, numberOfResponses: Int, totalNumberOfResponses: Int, pollSortIndex: Int) {
        self.identifier = identifier
        self.text = text
        self.isVotedByOwnedIdentity = isVotedByOwnedIdentity
        self.numberOfResponses = numberOfResponses
        self.totalNumberOfResponses = totalNumberOfResponses
        self.totalPercent = Double(numberOfResponses) * 100.0 / Double(totalNumberOfResponses)
        self.pollSortIndex = pollSortIndex
    }
    
}


/// The `PollView` shows the list of all candidates. Each candidate is shown by one instance of this `CandidateView`.
private struct CandidateView: ObvAccessibilityProvidableView {
    
    let candidate: PollViewCandidateModel
    let color: Color
    let avatarViewDataSource: ObvAvatarViewDataSource
    let accessibilityAction: () -> ()
    
    init(model: PollViewCandidateModel, color: Color, avatarViewDataSource: ObvAvatarViewDataSource, accessibilityAction: @escaping () -> ()) {
        self.candidate = model
        self.color = color
        self.avatarViewDataSource = avatarViewDataSource
        self.accessibilityAction = accessibilityAction
    }
    
    var accessibilityAttributes: ObvAccessibilityAttributes {
        .init(label: candidate.text,
              value: String(localizedInThisBundle: "POLL_ANSWERS_\(candidate.numberOfResponses)"),
              actions: [String(localizedInThisBundle: "ACCESSIBILITY_ACTION_SHOW"): self.accessibilityAction],
              hint: String(localizedInThisBundle: "ACCESSIBILITY_DOUBLE_TOUCH_SHOW"),
              traits: [.isButton])
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            Circle()
                .foregroundStyle(color)
                .frame(width: 12.0, height: 12.0)
            Text(candidate.text)
            switch candidate.isVotedByOwnedIdentity {
            case .no:
                EmptyView()
            case .yes(let avatarModelOfOwnedIdentity):
                ObvAvatarView(model: avatarModelOfOwnedIdentity,
                              style: .squircle,
                              size: .custom(frameSize: CGSize(width: 16.0, height: 16.0)),
                              dataSource: avatarViewDataSource)

            }
            Spacer()
            Text("POLL_ANSWERS_\(candidate.numberOfResponses)")
                .foregroundStyle(Color(uiColor: UIColor.secondaryLabel))
            Image(systemIcon: .chevronRight)
                .imageScale(.small)
                .foregroundStyle(Color(uiColor: UIColor.secondaryLabel))
        }
        .padding(.vertical, 14)
    }
    
}


// MARK: - WaitingAnswerView

public struct VoterWhoDidNotVoteYetViewModel: Sendable, Equatable, Hashable, Identifiable {
    
    let identifier: VoterIdentifier
    let name: String
    let avatarModel: ObvAvatarViewModel
    
    public init(identifier: VoterIdentifier, name: String, avatarModel: ObvAvatarViewModel) {
        self.identifier = identifier
        self.name = name
        self.avatarModel = avatarModel
    }
    
    public var id: VoterIdentifier { self.identifier }
    
    public enum VoterIdentifier: Equatable, Hashable, Identifiable, Sendable {
        case contactObjectID(NSManagedObjectID) // NSManagedObjectID of a PersistedObvContactIdentity
        case forPreviews(cryptoId: ObvCryptoId)
        public var id: Data {
            switch self {
            case .contactObjectID(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            case .forPreviews(let cryptoId):
                return cryptoId.getIdentity()
            }
        }

    }
    
}

@MainActor
public protocol VoterWhoDidNotVoteYetViewDataSource {
    func getInitialVoterWhoDidNotVoteYetViewModel(voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) -> VoterWhoDidNotVoteYetViewModel?
    func getAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<VoterWhoDidNotVoteYetViewModel>)
    func finishAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, streamUUID: UUID)
}


public struct VoterWhoDidNotVoteYetView: ObvAccessibilityProvidableView {
    
    private let voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier
    private let dataSource: VoterWhoDidNotVoteYetViewDataSource
    private let avatarViewDataSource: ObvAvatarViewDataSource
    
    init(voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier, dataSource: VoterWhoDidNotVoteYetViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource) {
        self.voterIdentifier = voterIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        if let viewModel = dataSource.getInitialVoterWhoDidNotVoteYetViewModel(voterIdentifier: voterIdentifier) {
            self.initialViewModel = viewModel
        } else {
            self.initialViewModel = nil
        }
    }
    
    private let initialViewModel: VoterWhoDidNotVoteYetViewModel?
    @State private var streamedViewModel: VoterWhoDidNotVoteYetViewModel?
    
    private var voter: VoterWhoDidNotVoteYetViewModel? {
        streamedViewModel ?? initialViewModel
    }

    public var accessibilityAttributes: ObvAccessibilityAttributes {
        if let voter {
            return .init(label: voter.name,
                         value: String(localizedInThisBundle: "ACCESSIBILITY_POLL_ANSWERS_WAITING"),
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
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfVoterWhoDidNotVoteYetViewModel(self, voterIdentifier: voterIdentifier)
            for await model in stream {
                withAnimation {
                    self.streamedViewModel = model
                }
            }
            dataSource.finishAsyncStreamOfVoterWhoDidNotVoteYetViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    @ViewBuilder
    var content: some View {
        if let voter {
            HStack(alignment: .center, spacing: 12.0) {
                ObvAvatarView(model: voter.avatarModel,
                              style: .squircle,
                              size: .small,
                              dataSource: avatarViewDataSource)
                Text(voter.name)
                Spacer(minLength: 0)
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
            .task(onTask)
    }
    
}





// MARK: - Previews

#if DEBUG

private final class VoterWhoDidNotVoteYetViewDataSourceForPreviews: VoterWhoDidNotVoteYetViewDataSource, ObvAvatarViewDataSource {
    
    func getInitialVoterWhoDidNotVoteYetViewModel(voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) -> VoterWhoDidNotVoteYetViewModel? {
        // let model = VoterWhoDidNotVoteYetViewModel.sampleDatasForIdentifier(voterIdentifier)
        return nil // Testing the stream
    }
    
    func getAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<VoterWhoDidNotVoteYetViewModel>) {
        let stream = AsyncStream(VoterWhoDidNotVoteYetViewModel.self) { (continuation: AsyncStream<VoterWhoDidNotVoteYetViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 2)
                guard let model = VoterWhoDidNotVoteYetViewModel.sampleDatasForIdentifier(voterIdentifier) else { return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, streamUUID: UUID) {
        // Nothing to do
    }
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }

}

private let voterWhoDidNotVoteYetViewDataSourceForPreviews = VoterWhoDidNotVoteYetViewDataSourceForPreviews()

#Preview("VoterWhoDidNotVoteYetView") {
    VoterWhoDidNotVoteYetView(
        voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier.sampleDatas[0],
        dataSource: voterWhoDidNotVoteYetViewDataSourceForPreviews,
        avatarViewDataSource: voterWhoDidNotVoteYetViewDataSourceForPreviews)
}

@available(iOS 17, *)
private final class PollViewDataSourceProtocolForPreviews: PollViewDataSourceProtocol, ObvAvatarViewDataSource {
    
    private var continuationForPollViewModel: AsyncStream<PollViewModel>.Continuation?
    private var candidatesSortOrder: PollViewModel.CandidatesSortOrder = .pollOrder
    
    func getInitialPollViewModel(pollIdentifier: PollIdentifier, candidatesSortOrder: PollViewModel.CandidatesSortOrder) -> PollViewModel? {
        self.candidatesSortOrder = candidatesSortOrder
        //let model = PollViewModel.sampleData
        return nil // Testing the stream
    }
    
    func getAsyncStreamOfPollViewModel(_ view: PollView, pollIdentifier: PollIdentifier, candidatesSortOrder: PollViewModel.CandidatesSortOrder) throws -> (streamUUID: UUID, stream: AsyncStream<PollViewModel>) {
        let stream = AsyncStream(PollViewModel.self) { (continuation: AsyncStream<PollViewModel>.Continuation) in
            continuationForPollViewModel = continuation
            self.candidatesSortOrder = candidatesSortOrder
            Task {
                try? await Task.sleep(seconds: 1)
                let model = PollViewModel.sampleDatas(candidatesSortOrder: candidatesSortOrder)
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func changeSortOrderOfAsyncStreamOfPollViewModel(to newSortOrder: PollViewModel.CandidatesSortOrder, streamUUID: UUID) {
        self.candidatesSortOrder = newSortOrder
        let model = PollViewModel.sampleDatas(candidatesSortOrder: candidatesSortOrder)
        continuationForPollViewModel?.yield(model)
    }
    
    func finishAsyncStreamOfPollViewModel(_ view: PollView, streamUUID: UUID) {
        // Nothing to finish
    }
    
    func getInitialPollCandidateViewModel(candidateIdentifier: PollCandidateIdentifier) -> PollCandidateViewModel? {
        // TODO
        return nil
    }
    
    func getAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, candidateIdentifier: PollCandidateIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<PollCandidateViewModel>) {
        let stream = AsyncStream(PollCandidateViewModel.self) { (continuation: AsyncStream<PollCandidateViewModel>.Continuation) in
            // TODO
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, streamUUID: UUID) {
        // Nothing to finish
    }
    
    func getInitialVoterWhoDidNotVoteYetViewModel(voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) -> VoterWhoDidNotVoteYetViewModel? {
        // let model = VoterWhoDidNotVoteYetViewModel.sampleDatasForIdentifier(voterIdentifier)
        return nil // Testing the stream
    }
    
    func getAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<VoterWhoDidNotVoteYetViewModel>) {
        let stream = AsyncStream(VoterWhoDidNotVoteYetViewModel.self) { (continuation: AsyncStream<VoterWhoDidNotVoteYetViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1)
                guard let model = VoterWhoDidNotVoteYetViewModel.sampleDatasForIdentifier(voterIdentifier) else { return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, streamUUID: UUID) {
        // Nothing to finish
    }
    
    func getInitialPollVoteViewModel(voteIdentifier: PollVoteViewModel.VoteIdentifier) -> PollVoteViewModel? {
        let model = PollVoteViewModel.sampleDatasForIdentifier(voteIdentifier)
        return model
    }
    
    func getAsyncStreamOfPollVoteViewModel(_ view: VoteView, voteIdentifier: PollVoteViewModel.VoteIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<PollVoteViewModel>) {
        let stream = AsyncStream(PollVoteViewModel.self) { (continuation: AsyncStream<PollVoteViewModel>.Continuation) in
            guard let model = PollVoteViewModel.sampleDatasForIdentifier(voteIdentifier) else { return }
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfPollVoteViewModel(_ view: VoteView, streamUUID: UUID) {
        // Nothing to finish
    }
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

@available(iOS 17, *)
private let pollViewDataSourceProtocolForPreviews = PollViewDataSourceProtocolForPreviews()

@available(iOS 17, *)
@MainActor
private let pollRouterForPreviews = PollRouter(dataSource: pollViewDataSourceProtocolForPreviews, avatarViewDataSource: pollViewDataSourceProtocolForPreviews)

#Preview("PollView") {
    if #available(iOS 17, *) {
        PollView(pollIdentifier: PollIdentifier.forPreviews,
                 router: pollRouterForPreviews)
    }
}

#endif
