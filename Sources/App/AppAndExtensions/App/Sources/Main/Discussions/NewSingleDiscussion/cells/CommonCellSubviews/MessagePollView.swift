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

import Foundation
import UIKit
import SwiftUI
import ObvUICoreData
import ObvAccessibility
import ObvPollFeature

protocol MessagePollViewDelegate: AnyObject {
    func userWantsToUpdatePollVote(_ messagePollView: MessagePollView,
                                   messageObjectID: TypeSafeManagedObjectID<PersistedMessage>,
                                   pollCandidateUUID: UUID,
                                   voted: Bool,
                                   version: Int,
                                   voteSentStatus: VoteSentStatus) async throws
    
    func userWantsToDisplayPollView(_ messagepollView: MessagePollView,
                                    pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws
}


// MARK: - MessagePollView

final class MessagePollView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {

    struct Configuration: Equatable, Hashable {
        let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
        let candidateVotes: [CandidateConfiguration]
    }
    
    struct CandidateConfiguration: Equatable, Hashable {
        let UUID: UUID
        let votes: [Bool]
    }
    
    private var currentConfiguration: Configuration?
    
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    private let textColor: UIColor
    private let progressColor: UIColor
    
    weak var delegate: MessagePollViewDelegate?
    
    private var hostingController: UIHostingController<MessagePollContentView>?
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side, bubbleColor: UIColor, textColor: UIColor, progressColor: UIColor) {
        self.expirationIndicatorSide = side
        self.textColor = textColor
        self.progressColor = progressColor
        super.init(frame: .zero)
        setupInternalViews(bubbleColor: bubbleColor)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ newConfiguration: Configuration) {
        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration
        refresh()
    }
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    private func setupInternalViews(bubbleColor: UIColor) {
        addSubview(bubble)
        bubble.backgroundColor = bubbleColor
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        let contentView = MessagePollContentView(viewModel: nil,
                                                 textColor: self.textColor,
                                                 progressColor: self.progressColor,
                                                 delegate: self)
        let hostingController = UIHostingController(rootView: contentView)
        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = .intrinsicContentSize
        }
        guard let hostingView = hostingController.view else { return }
        bubble.addSubview(hostingView)
        hostingView.backgroundColor = .clear
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            hostingView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            hostingView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            hostingView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)
        
        self.hostingController = hostingController
    }
    
    private func refresh() {
        if let hostingController, let messageObjectID = currentConfiguration?.messageObjectID, let message = try? PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext), let poll = message.poll {
            
            let totalNumberOfResponses = poll.totalNumberOfResponses
            
            let candidatesModel: [MessagePollCandidateViewModel] = poll.candidates
                .sorted(by: \.sortIndex)
                .compactMap { candidate in
                    
                    var hasVoted = !candidate.ownedVotes.isEmpty
                    
                    // If user votes None, we display other responses as False.
                    if poll.hasVoteNone {
                        if candidate.isNone {
                            hasVoted = true
                        } else {
                            hasVoted = false
                        }
                    }
                    
                    let totalPercent = totalNumberOfResponses > 0 ? Double(poll.numberOfResponses(for: candidate)) / Double(totalNumberOfResponses) * 100.0 : 0
                    
                    guard let candidateUUID = candidate.uuid else { return nil }
                    
                    return MessagePollCandidateViewModel(uuid: candidateUUID,
                                                         text: candidate.text,
                                                         hasVoted: hasVoted,
                                                         totalPercent: totalPercent)
                }
            
            let viewModel = MessagePollViewModel(question: poll.question,
                                                 multipleChoice: poll.multipleChoice,
                                                 candidates: candidatesModel,
                                                 expirationDate: poll.expiration,
                                                 totalNumberOfResponses: totalNumberOfResponses)
            hostingController.rootView = MessagePollContentView(viewModel: viewModel,
                                                                textColor: self.textColor,
                                                                progressColor: self.progressColor,
                                                                delegate: self)
            hostingController.view.invalidateIntrinsicContentSize()
        }
    }
}


extension MessagePollView: MessagePollContentViewDelegate {
    
    func userWantsToUpdatePollVote(_ MessagePollContentView: MessagePollContentView, pollCandidateUUID: UUID, voted: Bool, voteSentStatus: VoteSentStatus) async throws {
        guard let messageObjectID = self.currentConfiguration?.messageObjectID, let message = try PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }
        
        guard let poll = message.poll else { return }
        
        guard let pollCandidate = poll.candidates.first(where: { $0.uuid == pollCandidateUUID }) else { return }
        
        let currentVote = pollCandidate.votes.filter { $0 is PersistedPollVoteSent }.first
        var currentVoteVersion = Int(currentVote?.version ?? -1)
        // If poll is not with multiple choice, and user already has a vote, we take his past vote version
        
        if !poll.multipleChoice, let ownedVotedCandidate = poll.candidatesVotedByOwnedIdentity.first {
            let currentVote = ownedVotedCandidate.ownedVotes.first
            currentVoteVersion = max(currentVoteVersion, Int(currentVote?.version ?? -1))
        }
        
        Task {
            try await self.delegate?.userWantsToUpdatePollVote(self, messageObjectID: messageObjectID, pollCandidateUUID: pollCandidateUUID, voted: voted, version: currentVoteVersion + 1, voteSentStatus: voteSentStatus)
        }
    }
    
    
    func userWantsToDisplayPollView() async throws {
        guard let messageObjectID = self.currentConfiguration?.messageObjectID else { return }
        guard let message = try? PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }
        guard let pollObjectID = message.poll?.typedObjectID else { return }
        Task {
            try await self.delegate?.userWantsToDisplayPollView(self, pollObjectID: pollObjectID)
        }
    }
    
}


// MARK: - MessagePollContentView and models

private struct MessagePollViewModel: Sendable, Hashable, Equatable {
    
    let question: String
    let multipleChoice: Bool
    let candidates: [MessagePollCandidateViewModel]
    let expirationDate: Date?
    let totalNumberOfResponses: Int
    
    var expirationDateFormatted: String {
        guard let expirationDate else { return "" }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        return dateFormatter.string(from: expirationDate)
    }
    
}


private struct MessagePollCandidateViewModel: Sendable, Hashable, Equatable, Identifiable {
    let uuid: UUID
    let text: String
    let hasVoted: Bool
    let totalPercent: Double
    
    var id: UUID { uuid }
}


enum VoteSentStatus {
    case canBeSent
    case pollFinished
    case blockedByNone
    
    var toastMessage: String {
        switch self {
        case .canBeSent:
            return ""
        case .pollFinished:
            return String(localized: "POLL_FINISHED_TOAST")
        case .blockedByNone:
            return String(localized: "POLL_NONE_SELECTED_TOAST")
        }
    }
}


protocol MessagePollContentViewDelegate: AnyObject {
    func userWantsToUpdatePollVote(_ MessagePollContentView: MessagePollContentView,
                                   pollCandidateUUID: UUID,
                                   voted: Bool,
                                   voteSentStatus: VoteSentStatus) async throws
    
    func userWantsToDisplayPollView() async throws
}


struct MessagePollContentView: View {
    
    private let viewModel: MessagePollViewModel?
    private let textColor: Color
    private let progressColor: Color
    
    private weak var delegate: MessagePollContentViewDelegate?
    
    fileprivate init(viewModel: MessagePollViewModel?, textColor: UIColor, progressColor: UIColor, delegate: MessagePollContentViewDelegate?) {
        self.viewModel = viewModel
        self.textColor = Color(uiColor: textColor)
        self.progressColor = Color(uiColor: progressColor)
        self.delegate = delegate
    }
    
    private func updateVote(for candidate: MessagePollCandidateViewModel, voted: Bool) {
        Task {
            
            let hasVotedToNone: Bool = self.viewModel?.candidates.contains { $0.uuid == .uuidOfPollCandidateNone && $0.hasVoted } ?? false
                                           
            var voteStatus: VoteSentStatus = .canBeSent
            if let expirationDate = viewModel?.expirationDate, Date.now >= expirationDate {
                voteStatus = .pollFinished
            } else if candidate.uuid != .uuidOfPollCandidateNone, hasVotedToNone {
                voteStatus = .blockedByNone
            }
            try await delegate?.userWantsToUpdatePollVote(self, pollCandidateUUID: candidate.uuid, voted: voted, voteSentStatus: voteStatus)
        }
    }
    
    fileprivate struct CandidateToggleView: ObvAccessibilityProvidableView {
        let viewModel: MessagePollViewModel
        let candidate: MessagePollCandidateViewModel
        let onChange: (Bool) -> ()
        let textColor: Color
        let progressColor: Color
        
        var accessibilityAttributes: ObvAccessibilityAttributes {
            
            var traits: [AccessibilityTraits] = [.isButton]
            var value: String = "\(Int(candidate.totalPercent))%"
            
            if candidate.hasVoted {
                traits.append(.isSelected)
                value += ", " + String(localized: "ACCESSIBILITY_POLL_HAS_VOTED")
            }
            
            return .init(label: candidate.text,
                         value: value,
                         actions: nil,
                         hint: nil,
                         traits: traits)
        }
        
        init(for candidate: MessagePollCandidateViewModel,
             viewModel: MessagePollViewModel,
             textColor: Color,
             progressColor: Color,
             onChange: @escaping (Bool) -> ()) {
            self.candidate = candidate
            self.viewModel = viewModel
            self.onChange = onChange
            self.textColor = textColor
            self.progressColor = progressColor
        }
        
        func color(for candidate: MessagePollCandidateViewModel) -> Color? {
            
            if let index = viewModel.candidates.firstIndex(of: candidate) {
                let colorIndex = index % Color.pollColors.count
                return Color.pollColors[colorIndex]
            }
            
            return nil
        }
        
        var body: some View {
            Button(action: {
                onChange(!candidate.hasVoted)
            }) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .stroke(textColor, lineWidth: 1)
                        if candidate.hasVoted {
                            Image(systemIcon: .checkmarkCircleFill)
                                .resizable()
                                .foregroundStyle(textColor)
                        }
                    }
                    .frame(width: 20, height: 20)
                    VStack(alignment: .leading) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true) // Used to force text to display in multiline
                            Spacer()
                            Text(verbatim: "\(Int(candidate.totalPercent))%")
                                .font(.footnote)
                                .foregroundStyle(textColor.opacity(0.75))
                        }
                        
                        ProgressView(value: candidate.totalPercent, total: 100.0)
                            .progressViewStyle(LargerProgressViewStyle(tintColor: color(for: candidate) ?? progressColor, backgroundColor: textColor.opacity(0.3)))
                            .frame(height: 8.0)
                    }
                }
            }
        }
    }
    
    var body: some View {
        
        if let viewModel {
            VStack(alignment: .leading, spacing: 0.0) {
                Text(viewModel.question)
                    .fontWeight(.bold)
                
                Text(viewModel.multipleChoice ? "poll_message_multiple_choice" : "poll_message_no_multiple_choice")
                    .font(.footnote)
                    .foregroundStyle(textColor.opacity(0.75))
                    .padding(.top, 4.0)
                    .padding(.bottom, 8.0)
                
                ForEach(viewModel.candidates) { candidate in
                    CandidateToggleView(for: candidate, viewModel: viewModel, textColor: textColor, progressColor: progressColor) { newValue in
                        updateVote(for: candidate, voted: newValue)
                    }
                    .obvAccessibleComponent()
                    .padding(.vertical, 8.0)
                }
                
                if let expirationDate = viewModel.expirationDate {
                    if expirationDate <= Date.now {
                        (
                            Text(Image(systemIcon: .clock))
                            + Text(" ") +
                            Text("poll_message_expiration_date_expired")
                        )
                        .padding(.vertical, 8.0)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.75))
                    } else {
                        (
                            Text(Image(systemIcon: .clock))
                            + Text(" ") +
                            Text("poll_message_expiration_date")
                            + Text(" ")
                            + Text(viewModel.expirationDateFormatted)
                        )
                        .padding(.vertical, 8.0)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.75))
                    }
                }
                
                if viewModel.totalNumberOfResponses > 0 {
                    (Text("poll_message_voters_count") + Text(verbatim: " (\(viewModel.totalNumberOfResponses))"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 8.0)
                } else {
                    Text("poll_message_voters_count")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 8.0)
                }
            }
            .font(.body)
            .foregroundStyle(textColor)
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    try await delegate?.userWantsToDisplayPollView()
                }
            }
        } else {
            ProgressView()
                .tint(textColor)
                .padding()
        }
    }
    
}


private struct LargerProgressViewStyle: ProgressViewStyle {
    
    var tintColor: Color
    var backgroundColor: Color
    
    init(tintColor: Color, backgroundColor: Color) {
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
    }
    
    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0
        
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(backgroundColor)
                
                Capsule()
                    .fill(tintColor)
                    .frame(width: fractionCompleted * geometry.size.width)
                
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}


#if DEBUG

private let candidatesForPreviews: [MessagePollCandidateViewModel] = [
    .init(uuid: UUID(), text: "15 Juin", hasVoted: true, totalPercent: 8),
    .init(uuid: UUID(), text: "16 Juin", hasVoted: true, totalPercent: 28),
    .init(uuid: UUID(), text: "17 Juin", hasVoted: false, totalPercent: 64),
    .init(uuid: UUID(), text: "18 Juin", hasVoted: false, totalPercent: 0),
]
#Preview {
    MessagePollContentView(viewModel: MessagePollViewModel(question: "Bla bla bla bla bla ?",
                                                           multipleChoice: false,
                                                           candidates: candidatesForPreviews,
                                                           expirationDate: Date() + 1000,
                                                           totalNumberOfResponses: 45),
                           textColor: UIColor.label,
                           progressColor: UIColor.label.withAlphaComponent(0.5),
                           delegate: nil)
}

#endif
