/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvSettings
import ObvUICoreData

struct ReactionContextView: View {
    
    let contextMessageId: TypeSafeManagedObjectID<PersistedMessage>
    let actions: ReactionContextViewActionProtocol
    
    static private var MAX_EMOJIS_COUNT: Int {
        ObvMessengerConstants.targetEnvironmentIsMacCatalyst ? 8 : 5
    }
    
    @State private var showReactionsBackground = false

    @State private var emojis: [String] = {
        ObvMessengerPreferredEmojisListObservable().emojis.count >= ReactionContextView.MAX_EMOJIS_COUNT
        ? Array(ObvMessengerPreferredEmojisListObservable().emojis[0..<ReactionContextView.MAX_EMOJIS_COUNT])
        : ObvMessengerPreferredEmojisListObservable().emojis
    }()
    
    @State private var addDisplayed: Bool = false
    @State private var addRotation: Double = -45
    
    @State private var emojisDisplayed: [String: Bool] = [:]
    @State private var emojisRotation: [String: Double] = [:]
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 25)
            .fill(Color(UIColor.tertiarySystemBackground))
            .scaleEffect(showReactionsBackground ? 1 : 0, anchor: .bottomTrailing)
            .animation(
                .interpolatingSpring(stiffness: 170, damping: 15).delay(0.05),
                value: showReactionsBackground
            )
    }
    
    private var addButton: some View {
        Button(
            action: {
                Task {
                    await actions.userWantsToOpenEmojiPicker(for: contextMessageId)
                }
            },
            label: {
                Image(systemIcon: .plus)
                    .font(.system(size: 20.0))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color(UIColor.systemFill)))
                    .scaleEffect(addDisplayed ? 1 : 0)
                    .rotationEffect(.degrees(addRotation))
            }
        )
        
    }
    
    private var emojiList: some View {
        
        HStack(spacing: 10.0) {
            
            if !emojis.isEmpty {
                
                ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                    Text(emoji)
                        .font(.system(size: 33.0))
                        .scaleEffect((emojisDisplayed[emoji] ?? false) ? 1 : 0)
                        .rotationEffect(.degrees(emojisRotation[emoji] ?? 0))
                        .onTapGesture {
                            Task {
                                await actions.userDidSelectEmoji(to: contextMessageId, emoji: emoji)
                            }
                        }
                }
                                 
            } else {
                
                Text("ADD_TO_CONFIGURE_PREFERRED_EMOJIS_LIST")
                    .font(Font.system(.callout, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(addDisplayed ? 1 : 0)
                    .onTapGesture {
                        Task {
                            await actions.userWantsToOpenEmojiPicker(for: contextMessageId)
                        }
                    }
                    .frame(height: 40.0)
                
            }
            
            addButton
            
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 2.0)
    }
    
    var body: some View {
        ZStack {
            background
            emojiList
        }
        .onAppear {
            setupEmojisState()
            showReactionsBackground = true
            animateEmojis()
        }
    }
    
    private func setupEmojisState() {
        emojis.forEach { emoji in
            emojisDisplayed[emoji] = false
            emojisRotation[emoji] = -45
        }
    }
    
    private func animateEmojis() {
        
        let delay = 0.05
        emojis.enumerated().forEach { index, emoji in
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 15).delay(0.1 + (delay * Double(index)))) {
                emojisDisplayed[emoji]?.toggle()
                emojisRotation[emoji] = (emojisRotation[emoji] ?? 0) == -45 ? 0 : -45
            }
        }
        
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 15).delay(0.1 + (delay * Double(emojis.count)))) {
            addDisplayed.toggle()
            addRotation = addRotation == -45 ? 0 : -45
        }
    }
}


/// This ``UIHostingController`` won't stay long in memory. We only use it to get access to the ``ReactionContextView``.
final class ReactionContextHostingViewController: UIHostingController<ReactionContextView> {
    
    init(messageId: TypeSafeManagedObjectID<PersistedMessage>, delegate: ReactionContextViewActionProtocol) {
        let view = ReactionContextView(contextMessageId: messageId, actions: delegate)
        super.init(rootView: view)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.clear
    }

}


protocol ReactionContextViewActionProtocol: AnyObject {
    func userDidSelectEmoji(to messageId: TypeSafeManagedObjectID<PersistedMessage>, emoji: String) async
    func userWantsToOpenEmojiPicker(for messageId: TypeSafeManagedObjectID<PersistedMessage>) async
}
