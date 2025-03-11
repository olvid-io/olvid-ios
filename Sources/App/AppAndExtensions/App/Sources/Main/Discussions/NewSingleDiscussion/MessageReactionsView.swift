/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


import CoreData
import Foundation
import ObvUI
import ObvUICoreData
import SwiftUI
import ObvSystemIcon
import ObvSettings
import ObvTypes


protocol MessageReactionsListHostingViewControllerDelegate: AnyObject {
    func userWantsToUpdateReaction(_ messageReactionsListHostingViewController: MessageReactionsListHostingViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
}


final class MessageReactionsListHostingViewController: UIHostingController<MessageReactionsListView> {

    fileprivate let model: MessageReactionsListViewModel
    private weak var delegate: MessageReactionsListHostingViewControllerDelegate?

    init?(message: PersistedMessage, delegate: MessageReactionsListHostingViewControllerDelegate) {
        assert(Thread.isMainThread)
        assert(message.managedObjectContext == ObvStack.shared.viewContext)

        self.delegate = delegate
        self.model = MessageReactionsListViewModel(messageInViewContext: message)
        let view = MessageReactionsListView(model: model)
        super.init(rootView: view)
        self.model.delegate = self
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()

        // In case there is a navigation controller (which is the case under macOS), add a close button
        let closeAction = UIAction { [weak self] _ in self?.dismiss() }
        let closeButton = UIBarButtonItem(systemItem: .cancel, primaryAction: closeAction)
        navigationItem.rightBarButtonItem = closeButton
        
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


}

extension MessageReactionsListHostingViewController: MessageReactionsListViewModelDelegate {
    
    func dismiss() {
        self.dismiss(animated: true)
    }

    func userWantsToUpdateReaction(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
    }
    
}


fileprivate protocol MessageReactionsListViewModelDelegate: AnyObject {
    func dismiss()
    func userWantsToUpdateReaction(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
}


final fileprivate class MessageReactionsListViewModel: ObservableObject {

    private(set) var messageInViewContext: PersistedMessage
    @Published var changed: Bool // This allows to "force" the refresh of the view
    private var observationTokens = [NSObjectProtocol]()
    @ObservedObject var preferredEmojisList = ObvMessengerPreferredEmojisListObservable()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    fileprivate weak var delegate: MessageReactionsListViewModelDelegate?

    init(messageInViewContext: PersistedMessage) {
        self.messageInViewContext = messageInViewContext
        self.changed = true
        observeReactionsChanges()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
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

    @MainActor
    func userWantsToDeleteItsReaction() {
        guard let ownedCryptoId = messageInViewContext.discussion?.ownedIdentity?.cryptoId else { assertionFailure(); return }
        guard let delegate else { assertionFailure(); return }
        let messageObjectID = messageInViewContext.typedObjectID
        Task {
            try? await delegate.userWantsToUpdateReaction(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: nil)
        }
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

    func successHaptic() {
        notificationGenerator.notificationOccurred(.success)
    }

}

fileprivate enum MessageReactionSender: Equatable, Hashable {
    case contact(_: PersistedObvContactIdentity)
    case owned(_: PersistedObvOwnedIdentity)
}

fileprivate extension PersistedMessageReaction {

    var sender: MessageReactionSender? {
        if self is PersistedMessageReactionSent {
            guard let ownedIdentity = message?.discussion?.ownedIdentity else { return nil }
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
        guard let emoji = reaction.emoji else {
            return nil
        }
        self.emoji = emoji
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

    var isOwnedReaction: Bool {
        switch sender {
        case .contact:
            return false
        case .owned:
            return true
        }
    }

}


struct MessageReactionsListView: View {

    @ObservedObject fileprivate var model: MessageReactionsListViewModel

    var body: some View {
        MessageReactionsListInnerView(reactions: model.reactions,
                                      reactionsAndCount: model.reactionAndCount,
                                      preferredEmojiList: model.preferredEmojisList,
                                      userWantsToDeleteItsReaction: model.userWantsToDeleteItsReaction,
                                      successHaptic: model.successHaptic)
    }
}


struct MessageReactionsListInnerView: View {

    fileprivate let reactions: [MessageReaction]
    let reactionsAndCount: [ReactionAndCount]
    let userWantsToDeleteItsReaction: () -> Void
    let successHaptic: () -> Void

    @ObservedObject var preferredEmojiList: ObvMessengerPreferredEmojisListObservable

    fileprivate init(reactions: [MessageReaction],
                     reactionsAndCount: [ReactionAndCount],
                     preferredEmojiList: ObvMessengerPreferredEmojisListObservable,
                     userWantsToDeleteItsReaction: @escaping () -> Void,
                     successHaptic: @escaping () -> Void) {
        self.reactions = reactions
        self.reactionsAndCount = reactionsAndCount
        self.preferredEmojiList = preferredEmojiList
        self.userWantsToDeleteItsReaction = userWantsToDeleteItsReaction
        self.successHaptic = successHaptic
    }

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .center, spacing: 0) {
                List {
                    Section {
                        ForEach(0..<reactions.count, id: \.self) { index in
                            MessageReactionView(index: index,
                                                reactions: reactions,
                                                userWantsToDeleteItsReaction: userWantsToDeleteItsReaction,
                                                successHaptic: successHaptic,
                                                preferredEmojiList: preferredEmojiList)
                        }
                    } footer: {
                        VStack(alignment: .leading) {
                            HStack(alignment: .firstTextBaseline) {
                                FixedWidthImage(systemIcon: .handTap)
                                Text("HOW_TO_ADD_MESSAGE_REACTION")
                                Spacer()
                            }
                            if reactions.contains(where: { !$0.isOwnedReaction }) {
                                HStack(alignment: .firstTextBaseline) {
                                    FixedWidthImage(systemIcon: .star)
                                    Text("HOW_TO_ADD_REACTION_TO_PREFFERED")
                                    Spacer()
                                }
                            }
                            if reactions.contains(where: { $0.isOwnedReaction }) {
                                HStack(alignment: .firstTextBaseline) {
                                    FixedWidthImage(systemIcon: .heartSlashFill)
                                    Text("HOW_TO_REMOVE_OWN_REACTION")
                                    Spacer()
                                }
                            }
                        }
                    }
                }
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
                .frame(height: 50)
            }
        }
    }

}


fileprivate struct FixedWidthImage: View {
    
    let systemIcon: SystemIcon
    
    var body: some View {
        Image(systemIcon: systemIcon)
            .frame(width: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }
    
}


fileprivate struct MessageReactionView: View {

    let index: Int
    let reactions: [MessageReaction]
    let userWantsToDeleteItsReaction: () -> Void
    let successHaptic: () -> Void
    @ObservedObject var preferredEmojiList: ObvMessengerPreferredEmojisListObservable

    var reaction: MessageReaction {
        reactions[index]
    }

    var body: some View {
        HStack {
            switch reaction.sender {
            case .owned(let ownedIdentity):
                let singleIdentity = SingleIdentity(ownedIdentity: ownedIdentity)
                OwnedMessageSender(model: singleIdentity, date: reaction.date)
            case .contact(let contactIdentity):
                let singleContactIdentity = SingleContactIdentity(persistedContact: contactIdentity, observeChangesMadeToContact: true)
                ContactMessageSender(model: singleContactIdentity,
                                     date: reaction.date)
            }
            Spacer()
            Button {
                switch reaction.sender {
                case .contact:
                    if preferredEmojiList.emojis.contains(reaction.emoji) {
                        withAnimation {
                            preferredEmojiList.emojis.removeAll { $0 == reaction.emoji }
                        }
                    } else {
                        withAnimation {
                            preferredEmojiList.emojis.append(reaction.emoji)
                        }
                    }
                    successHaptic()
                case .owned:
                    userWantsToDeleteItsReaction()
                }
            } label: {
                switch reaction.sender {
                case .contact:
                    if preferredEmojiList.emojis.contains(reaction.emoji) {
                        Image(systemIcon: .starFill)
                    } else {
                        Image(systemIcon: .star)
                    }
                case .owned:
                    Image(systemIcon: .heartSlashFill)
                }
            }
            // Avoid to execute the action when the user tap on every elements of the HStack
            .buttonStyle(BorderlessButtonStyle())
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
    
    private var firstName: String { model.getFirstName(for: .customOrTrusted) }
    private var lastName: String { model.getLastName(for: .customOrTrusted) }
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: firstName,
              titlePart2: lastName,
              subtitle: MessageReactionView.dateFormater.string(from: date),
              subsubtitle: nil)
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: model.circledText([firstName, lastName]),
              icon: .person,
              profilePicture: model.getProfilPicture(for: .customOrTrusted),
              showGreenShield: model.showGreenShield,
              showRedShield: model.showRedShield)
    }
    
    private var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModel,
              profilePictureViewModelContent: profilePictureViewModelContent)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: model.identityColors?.background,
              foreground: model.identityColors?.text)
    }
    
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContent,
              colors: initialCircleViewModelColors,
              displayMode: .small,
              editionMode: .none)
    }
    
    var body: some View {
        CircleAndTitlesView(model: circleAndTitlesViewModel)
    }
}


fileprivate struct OwnedMessageSender: View {
    
    @ObservedObject var model: SingleIdentity
    let date: Date
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: CommonString.Word.You,
              titlePart2: "",
              subtitle: MessageReactionView.dateFormater.string(from: date),
              subsubtitle: "")
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: model.circledText([model.firstName, model.lastName]),
              icon: .person,
              profilePicture: model.profilePicture,
              showGreenShield: model.showGreenShield,
              showRedShield: model.showRedShield)
    }
    
    private var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModel,
              profilePictureViewModelContent: profilePictureViewModelContent)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: model.identityColors?.background,
              foreground: model.identityColors?.text)
    }
    
    var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContent,
              colors: initialCircleViewModelColors,
              displayMode: .small,
              editionMode: .none)
    }
    
    var body: some View {
        CircleAndTitlesView(model: circleAndTitlesViewModel)
    }
}
