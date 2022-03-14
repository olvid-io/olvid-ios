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

import UIKit


struct ReactionAndCount: Equatable, Hashable, Comparable, Identifiable {

    var id: String { emoji }

    let emoji: String
    let count: Int

    static func < (lhs: ReactionAndCount, rhs: ReactionAndCount) -> Bool {
        return lhs.emoji < rhs.emoji
    }

    static func of(reactions: [PersistedMessageReaction]?) -> [ReactionAndCount] {
        guard let reactions = reactions else { return [] }
        var reactionsCount = [String: Int]()
        for reaction in reactions {
            let count = reactionsCount[reaction.emoji] ?? 0
            reactionsCount[reaction.emoji] = count + 1
        }
        var result = [ReactionAndCount]()
        for (emoji, count) in reactionsCount {
            result += [ReactionAndCount(emoji: emoji, count: count)]
        }
        result.sort()
        return result
    }
}


final class MultipleReactionsView: ViewForOlvidStack {
    
    
    func setReactions(to reactions: [ReactionAndCount],
                      messageID: TypeSafeManagedObjectID<PersistedMessage>?) {
        assert(!reactions.isEmpty)
        guard currentReactions != reactions else { return }
        currentReactions = reactions
        self.messageID = messageID
        prepareReactionViews(count: reactions.count)
        for index in 0..<reactions.count {
            let reaction = reactions[index]
            let reactionView = reactionViews[index]
            reactionView.set(emoji: reaction.emoji, count: reaction.count)
        }
        self.setNeedsLayout()
    }
    
    
    private func prepareReactionViews(count: Int) {
        let numberOfReactionViewsToAdd = max(0, count - reactionViews.count)
        for _ in 0..<numberOfReactionViewsToAdd {
            let view = ReactionView()
            stack.addArrangedSubview(view)
        }
        for view in stack.arrangedSubviews[0..<count] {
            view.showInStack = true
        }
        for view in stack.arrangedSubviews[count...] {
            view.showInStack = false
        }
    }
    
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
        setupTapGesture()
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private let backgroundBubble = UIView()
    private let bubble = UIView()
    private let stack = OlvidHorizontalStackView(gap: 8, side: .bothSides, debugName: "Stack of reactions", showInStack: true)
    private var currentReactions = [ReactionAndCount]()
    private var messageID: TypeSafeManagedObjectID<PersistedMessage>?

    private var reactionViews: [ReactionView] {
        stack.arrangedSubviews.compactMap({ $0 as? ReactionView })
    }

    weak var delegate: ReactionsDelegate?

    private func setupInternalViews() {
        
        addSubview(backgroundBubble)
        backgroundBubble.translatesAutoresizingMaskIntoConstraints = false
        backgroundBubble.backgroundColor = .systemBackground
        backgroundBubble.layer.cornerRadius = MessageCellConstants.cornerRadiusForInformationsViews
        
        backgroundBubble.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = AppTheme.shared.colorScheme.newReceivedCellBackground // Always, even for reactions on received message cells
        bubble.layer.cornerRadius = MessageCellConstants.cornerRadiusForInformationsViews - 2
        
        bubble.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        let constraints = [
            backgroundBubble.topAnchor.constraint(equalTo: self.topAnchor, constant: -12),
            backgroundBubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            backgroundBubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundBubble.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4),
            bubble.topAnchor.constraint(equalTo: backgroundBubble.topAnchor, constant: 2),
            bubble.trailingAnchor.constraint(equalTo: backgroundBubble.trailingAnchor, constant: -2),
            bubble.bottomAnchor.constraint(equalTo: backgroundBubble.bottomAnchor, constant: -2),
            bubble.leadingAnchor.constraint(equalTo: backgroundBubble.leadingAnchor, constant: 2),
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 6),
        ]
        NSLayoutConstraint.activate(constraints)

        let sizeConstraints = [
            bubble.heightAnchor.constraint(equalToConstant: 24),
            backgroundBubble.heightAnchor.constraint(equalToConstant: 28),
        ]
        NSLayoutConstraint.activate(sizeConstraints)
        
        self.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    }

    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(reactionViewWasTapped(sender:)))
        bubble.addGestureRecognizer(tapGesture)
    }

    @objc private func reactionViewWasTapped(sender: UIGestureRecognizer) {
        guard let messageID = self.messageID else { return }
        delegate?.userTappedOnReactionView(messageID: messageID)
    }

}



fileprivate final class ReactionView: ViewForOlvidStack {
    
    private let emoji = UILabel()
    private let count = UILabel()
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    func set(emoji: String, count: Int) {
        self.emoji.text = emoji
        if count > 1 {
            self.count.text = "\(count)"
        } else {
            self.count.text = ""
        }
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupInternalViews() {
        
        addSubview(emoji)
        emoji.translatesAutoresizingMaskIntoConstraints = false
        emoji.font = UIFont.systemFont(ofSize: 12)
        
        addSubview(count)
        count.translatesAutoresizingMaskIntoConstraints = false
        count.font = fontForCountLabel
        count.textColor = AppTheme.shared.colorScheme.secondaryLabel

        NSLayoutConstraint.activate([
            emoji.topAnchor.constraint(equalTo: self.topAnchor),
            emoji.trailingAnchor.constraint(equalTo: count.leadingAnchor),
            emoji.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            emoji.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            count.topAnchor.constraint(equalTo: self.topAnchor),
            count.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            count.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])

    }
 
    
    private var fontForCountLabel: UIFont {
        let systemFont = UIFont.systemFont(ofSize: 12, weight: .bold)
        let font: UIFont
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: 0)
        } else {
            font = systemFont
        }
        return font
    }

}
