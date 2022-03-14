/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import CoreData

final class MessageReactionsListHostingViewController: UIHostingController<MessageReactionsListView>, MessageReactionsListViewModelDelegate {

    fileprivate let model: MessageReactionsListViewModel

    init?(message: PersistedMessage) {
        assert(Thread.isMainThread)
        assert(message.managedObjectContext == ObvStack.shared.viewContext)

        self.model = MessageReactionsListViewModel(messageInViewContext: message)
        let view = MessageReactionsListView(model: model)
        super.init(rootView: view)
        self.model.delegate = self
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismiss() {
        self.dismiss(animated: true)
    }

}

fileprivate protocol MessageReactionsListViewModelDelegate: AnyObject {
    func dismiss()
}


final fileprivate class MessageReactionsListViewModel: ObservableObject {

    private(set) var messageInViewContext: PersistedMessage
    @Published var changed: Bool // This allows to "force" the refresh of the view
    private var observationTokens = [NSObjectProtocol]()

    fileprivate weak var delegate: MessageReactionsListViewModelDelegate?

    init(messageInViewContext: PersistedMessage) {
        self.messageInViewContext = messageInViewContext
        self.changed = true
        observeReactionsChanges()
    }

    var reactions: [MessageReaction] {
        var messageReactions: [MessageReaction] = messageInViewContext.reactions.compactMap {
            MessageReaction(reaction: $0)
        }
        messageReactions.sort()
        return messageReactions
    }

    var reactionAndCount: [ReactionAndCount] {
        ReactionAndCount.of(reactions: messageInViewContext.reactions)
    }

    func userWantsToDeleteItsReaction() {
        ObvMessengerInternalNotification.userWantsToUpdateReaction(messageObjectID: messageInViewContext.typedObjectID, emoji: nil).postOnDispatchQueue()
    }

    private func observeReactionsChanges() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main) { [weak self] notification in
            guard let _self = self else { return }
            guard (notification.object as? NSManagedObjectContext) == ObvStack.shared.viewContext else { return }
            guard let refreshedObject = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> else { return }
            let refreshedMessages = refreshedObject
                .compactMap({ $0 as? PersistedMessage })
                .filter({ $0.typedObjectID == _self.messageInViewContext.typedObjectID })
            guard !refreshedMessages.isEmpty else { return }
            _self.changed.toggle()
            if _self.messageInViewContext.reactions.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                    _self.delegate?.dismiss()
                }
            }
        })
    }
}

fileprivate enum MessageReactionSender: Equatable, Hashable {
    case contact(_: PersistedObvContactIdentity)
    case owned(_: PersistedObvOwnedIdentity)
}

fileprivate extension PersistedMessageReaction {

    var sender: MessageReactionSender? {
        if self is PersistedMessageReactionSent {
            guard let ownedIdentity = message?.discussion.ownedIdentity else { return nil }
            return .owned(ownedIdentity)
        } else if let receivedReaction = self as? PersistedMessageReactionReceived {
            guard let contactIdentity = receivedReaction.contact else { return nil }
            return .contact(contactIdentity)
        } else {
            assertionFailure()
            return nil
        }
    }

}


fileprivate class MessageReaction: Identifiable, Hashable, Comparable {

    var id: Int { hashValue }

    let emoji: String
    let date: Date
    let sender: MessageReactionSender

    func hash(into hasher: inout Hasher) {
        hasher.combine(sender)
        hasher.combine(emoji)
        hasher.combine(date)
    }

    init?(reaction: PersistedMessageReaction) {
        self.emoji = reaction.emoji
        self.date = reaction.timestamp
        guard let sender = reaction.sender else {
            return nil
        }
        self.sender = sender
    }

    static func == (lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }

    static func < (lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        switch (lhs.sender, rhs.sender) {
        case (.owned, .owned): assertionFailure(); return false
        case (.owned, .contact): return true
        case (.contact, .owned): return false
        case (let .contact(l), let .contact(r)):
            if lhs.emoji != rhs.emoji { return lhs.emoji < rhs.emoji }
            if l.cryptoId != r.cryptoId { return l.cryptoId < r.cryptoId }
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            assert(lhs == rhs)
            return false
        }
    }


}


struct MessageReactionsListView: View {

    @ObservedObject fileprivate var model: MessageReactionsListViewModel

    var body: some View {
        MessageReactionsListInnerView(reactions: model.reactions,
                                  reactionsAndCount: model.reactionAndCount,
                                  userWantsToDeleteItsReaction: model.userWantsToDeleteItsReaction)
    }
}


struct MessageReactionsListInnerView: View {

    fileprivate let reactions: [MessageReaction]
    let reactionsAndCount: [ReactionAndCount]
    let userWantsToDeleteItsReaction: () -> Void

    fileprivate init(reactions: [MessageReaction], reactionsAndCount: [ReactionAndCount], userWantsToDeleteItsReaction: @escaping () -> Void) {
        self.reactions = reactions
        self.reactionsAndCount = reactionsAndCount
        self.userWantsToDeleteItsReaction = userWantsToDeleteItsReaction
    }

    var body: some View {
        VStack(alignment: .center) {
            List {
                ForEach(reactions) { reaction in
                    MessageReactionView(reaction: reaction,
                                        userWantsToDeleteItsReaction: userWantsToDeleteItsReaction)
                }
            }
            Spacer()
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(reactionsAndCount) { reactionAndCount in
                            HStack(spacing: 2.0) {
                                Text(reactionAndCount.emoji)
                                Text(String(reactionAndCount.count))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                        }
                    }
                    .frame(minWidth: geo.size.width)
                }
            }
            .frame(height: 50)
        }
    }
}


fileprivate struct MessageReactionView: View {

    let reaction: MessageReaction
    let userWantsToDeleteItsReaction: () -> Void

    var body: some View {
        HStack {
            switch reaction.sender {
            case .owned(let ownedIdentity):
                let singleIdentity = SingleIdentity(ownedIdentity: ownedIdentity, editionMode: .none)
                OwnedMessageSender(model: singleIdentity, date: reaction.date)
            case .contact(let contactIdentity):
                let singleContactIdentity = SingleContactIdentity(persistedContact: contactIdentity, observeChangesMadeToContact: true)
                ContactMessageSender(model: singleContactIdentity,
                                     date: reaction.date)
            }
            Spacer()
            if case .owned = reaction.sender {
                Button {
                    userWantsToDeleteItsReaction()
                } label: {
                    Image(systemIcon: .heartSlashFill)
                }
                // Avoid to execute the action when the user tap on every elements of the HStack
                .buttonStyle(BorderlessButtonStyle())
            }
            Text(reaction.emoji)
        }
    }

    fileprivate static let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()
}


fileprivate struct ContactMessageSender: View {
    @ObservedObject var model: SingleContactIdentity
    let date: Date
    var firstName: String { model.getFirstName(for: .customOrTrusted) }
    var lastName: String { model.getLastName(for: .customOrTrusted) }
    var body: some View {
        CircleAndTitlesView(titlePart1: firstName,
                            titlePart2: lastName,
                            subtitle: MessageReactionView.dateFormater.string(from: date),
                            subsubtitle: nil,
                            circleBackgroundColor: model.identityColors?.background,
                            circleTextColor: model.identityColors?.text,
                            circledTextView: model.circledTextView([firstName, lastName]),
                            imageSystemName: "person",
                            profilePicture: model.getProfilPicture(for: .customOrTrusted),
                            changed: $model.changed,
                            showGreenShield: model.showGreenShield,
                            showRedShield: model.showRedShield,
                            editionMode: .none,
                            displayMode: .small)
    }
}


fileprivate struct OwnedMessageSender: View {
    @ObservedObject var model: SingleIdentity
    let date: Date
    var body: some View {
        CircleAndTitlesView(titlePart1: CommonString.Word.You,
                            titlePart2: "",
                            subtitle: MessageReactionView.dateFormater.string(from: date),
                            subsubtitle: nil,
                            circleBackgroundColor: model.identityColors?.background,
                            circleTextColor: model.identityColors?.text,
                            circledTextView: model.circledTextView([model.firstName, model.lastName]),
                            imageSystemName: "person",
                            profilePicture: model.profilePicture,
                            changed: $model.changed,
                            showGreenShield: model.showGreenShield,
                            showRedShield: model.showRedShield,
                            editionMode: .none,
                            displayMode: .small)
    }
}
