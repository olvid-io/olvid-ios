/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

extension VoteSentStatus {

    /// What a reader is told when their vote is refused.
    ///
    /// Here rather than beside the enum in `ObvPollFeature`: it is a toast, so it belongs on the side of the boundary that can show one, and the strings stay in the
    /// app's own catalogue.
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
        
        // The view itself lives in `ObvPollFeature`, so that the SwiftUI discussion screen draws the same poll rather than a second one written to match.
        let contentView = MessagePollContentView(viewModel: nil,
                                                 textColor: Color(uiColor: self.textColor),
                                                 progressColor: Color(uiColor: self.progressColor),
                                                 delegate: self)
        let hostingController = UIHostingController(rootView: contentView)
        hostingController.sizingOptions = .intrinsicContentSize
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
                                                                textColor: Color(uiColor: self.textColor),
                                                                progressColor: Color(uiColor: self.progressColor),
                                                                delegate: self)
            hostingController.view.invalidateIntrinsicContentSize()
        }
    }
}


extension MessagePollView: MessagePollContentViewDelegate {
    
    func userWantsToUpdatePollVote(_ MessagePollContentView: MessagePollContentView, pollCandidateUUID: UUID, voted: Bool, voteSentStatus: VoteSentStatus) async throws {
        guard let messageObjectID = self.currentConfiguration?.messageObjectID, let message = try PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }
        
        guard let poll = message.poll else { return }

        guard poll.candidates.contains(where: { $0.uuid == pollCandidateUUID }) else { return }

        // Asked of the poll rather than computed here, and the same arithmetic both discussion screens now use: see
        // `PersistedPoll.versionForTheNextVoteFromOwnedIdentity`, which takes the highest version of *every* vote the owned identity has cast on the poll — including a
        // vote they have withdrawn, which the accessors that filter on `voted` cannot see.
        let version = poll.versionForTheNextVoteFromOwnedIdentity

        Task {
            try? await self.delegate?.userWantsToUpdatePollVote(self, messageObjectID: messageObjectID, pollCandidateUUID: pollCandidateUUID, voted: voted, version: version, voteSentStatus: voteSentStatus)
        }
    }
    
    
    func userWantsToDisplayPollView() async throws {
        guard let messageObjectID = self.currentConfiguration?.messageObjectID else { return }
        guard let message = try? PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }
        guard let pollObjectID = message.poll?.typedObjectID else { return }
        Task {
            try? await self.delegate?.userWantsToDisplayPollView(self, pollObjectID: pollObjectID)
        }
    }
    
}
