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
import ObvTypes
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvCarPlay
import ObvDesignSystem
import ObvSystemIcon

@MainActor
final class CarPlayDiscussionsListViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var discussionsListViewModelStreamManagerForStreamUUID = [UUID: DiscussionsListViewModelStreamManager]()
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}

extension CarPlayDiscussionsListViewAppDataSource: CarPlayDiscussionsListViewDataSource {
    func getAsyncStreamOfCarPlayDiscussionsListViewModel(ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<CarPlayDiscussionsListViewModel>) {
        let manager = DiscussionsListViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        discussionsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfCarPlayDiscussionsListViewModel(streamUUID: UUID) {
        guard let manager = discussionsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    
}

extension CarPlayDiscussionsListViewAppDataSource {
    
    /// Produces the stream of `CarPlayDiscussionsListViewModel` shown in the CarPlay discussions list.
    /// Streams pinned and unpinned discussions that are not archived and not deleted.
    private final class DiscussionsListViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<CarPlayDiscussionsListViewModel, PersistedDiscussion, PersistedMessageReceived>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            // Note that `createModel()` expects the frc to contain two sections (so the splitPinnedDiscussionsIntoSections must be set to true here)
            let predicate = PersistedDiscussion.getPredicateForUnarchivedNotDeletedDiscussionsForOwnedIdentity(ownedCryptoId: ownedCryptoId)
            let frc1 = PersistedDiscussion.getFetchedResultsControllerWithPinnedDiscussionsSplitIntoSections(predicate: predicate, within: context)
            let frc2 = PersistedMessageReceived.getNewReceivedMessagesFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedMessageReceived]) throws -> CarPlayDiscussionsListViewModel {
            
            guard let sections = frc1.sections else {
                assertionFailure()
                throw ObvError.noSections
            }
            
            var pinnedDiscussions = [CarPlayDiscussionViewModel]()
            var unpinnedDiscussions = [CarPlayDiscussionViewModel]()

            for section in sections {
                guard let discussions = section.objects as? [PersistedDiscussion] else { assertionFailure(); continue }
                guard let sectionIdentifier = PersistedDiscussion.PinnedSectionKeyPathValue(rawValue: section.name) else { assertionFailure(); continue }
                switch sectionIdentifier {
                case .pinned:
                    pinnedDiscussions = discussions.compactMap { try? CarPlayDiscussionViewModel(persistedDiscussion: $0, newMessages: fetchedObjects2, isPinned: true) }
                case .unpinned:
                    unpinnedDiscussions = discussions.compactMap { try? CarPlayDiscussionViewModel(persistedDiscussion: $0, newMessages: fetchedObjects2, isPinned: false) }
                }
            }
            
            let model = CarPlayDiscussionsListViewModel(ownedCryptoId: ownedCryptoId,
                                                        discussions: pinnedDiscussions + unpinnedDiscussions)
            
            return model
            
        }

        enum ObvError: Error {
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
            case noSections
        }

        
    }
}


fileprivate extension CarPlayDiscussionViewModel {
    
    init(persistedDiscussion: PersistedDiscussion, newMessages: [PersistedMessageReceived], isPinned: Bool) throws {
        
        let conversationIdentifier = try persistedDiscussion.discussionIdentifier.description
        let title = persistedDiscussion.title        
        let image = CarPlayDiscussionViewModel.generateImage(for: persistedDiscussion)
        let unreadMessages = newMessages.filter({ $0.discussion == persistedDiscussion })
        
        let unreadSpokableMessages = unreadMessages.filter { $0.isSpokable }
        
        let unreadUnspokableMessages = unreadMessages.filter { !$0.isSpokable }
        
        var subtitles: [String] = []
        
        let polls = unreadUnspokableMessages.filter { $0.isPoll }
        let ephemeralWithUserActionMessages = unreadUnspokableMessages.filter { $0.readingRequiresUserAction }
        
        if !polls.isEmpty {
            subtitles.append(String(localized: "CARPLAY_SUBTITLE_POLLS_\(polls.count)"))
        }
        
        if !ephemeralWithUserActionMessages.isEmpty {
            subtitles.append(String(localized: "CARPLAY_SUBTITLE_EPHEMERALS_\(ephemeralWithUserActionMessages.count)"))
        }
        
        let subtitle: String?
        if !subtitles.isEmpty {
            let reason = String(localized:"CARPLAY_SUBTITLE_UNSPOKABLE_MESSAGES")
            subtitle = reason + ": " + subtitles.joined(separator: ", ")
        } else {
            subtitle = nil
        }
        
        let unread = unreadSpokableMessages.count > 0

        self.init(conversationIdentifier: conversationIdentifier,
                  title: title,
                  subtitle: subtitle,
                  latestMessageDate: persistedDiscussion.sortDate,
                  image: image,
                  unread: unread,
                  isPinned: isPinned)
        
    }

    
    private static func generateImage(for persistedDiscussion: PersistedDiscussion) -> UIImage? {
        // CPMessageListItem recommends at least 40pt; 60pt renders well on all current CarPlay displays.
        let circleDiameter: CGFloat = 60.0
        let foregroundColor = persistedDiscussion.circledInitialsConfiguration?.foregroundColor(appTheme: AppTheme.shared) ?? .white
        let backgroundColor = persistedDiscussion.circledInitialsConfiguration?.backgroundColor(appTheme: AppTheme.shared) ?? .systemGray4
        if let photoURL = try? persistedDiscussion.displayPhotoURL,
           let baseImage = UIImage(contentsOfFile: photoURL.path) {
            return CarPlayDiscussionViewModel.makeCircularImage(from: baseImage,
                                                                diameter: circleDiameter)
        } else {
            let kind = try? persistedDiscussion.kind
            return CarPlayDiscussionViewModel.defaultAvatar(forKind: kind,
                                                            title: persistedDiscussion.title,
                                                            diameter: circleDiameter,
                                                            isLocked: persistedDiscussion.status == .locked,
                                                            foregroundColor: foregroundColor,
                                                            backgroundColor: backgroundColor)
        }
    }
    
 
    private static func makeCircularImage(from image: UIImage?, diameter: CGFloat) -> UIImage? {
        guard let image else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))
            UIBezierPath(ovalIn: rect).addClip()
            image.draw(in: rect)
        }
    }

    
    private static func defaultAvatar(forKind kind: PersistedDiscussion.Kind?, title: String, diameter: CGFloat, isLocked: Bool, foregroundColor: UIColor, backgroundColor: UIColor) -> UIImage? {
        switch kind {
        case .some(.oneToOne):
            return makeInitialsAvatar(initials: initials(from: title), diameter: diameter, foregroundColor: foregroundColor, backgroundColor: backgroundColor)
        case .some(.groupV1), .some(.groupV2), .none:
            if isLocked {
                return CarPlayDiscussionViewModel.makeIconAvatar(icon: .lock(.fill, .none),
                                                                 diameter: diameter,
                                                                 foregroundColor: .secondaryLabel,
                                                                 backgroundColor: .secondarySystemBackground)
            } else {
                return makeIconAvatar(icon: .person3Fill, diameter: diameter, foregroundColor: foregroundColor, backgroundColor: backgroundColor)
            }
        }
    }

    private static func initials(from title: String) -> String {
        let components = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let first = components.first?.first
        let letters: [Character] = [first].compactMap { $0 }
        return String(letters)
    }
        
    private static func makeInitialsAvatar(initials: String, diameter: CGFloat, foregroundColor: UIColor, backgroundColor: UIColor) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))
            // Background circle
            let bgColor = backgroundColor
            bgColor.setFill()
            UIBezierPath(ovalIn: rect).fill()
            // Draw initials
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let fontSize = diameter * 0.5
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: foregroundColor,
                .paragraphStyle: paragraph
            ]
            let text = initials.isEmpty ? "?" : initials
            let textSize = (text as NSString).size(withAttributes: attrs)
            let textRect = CGRect(
                x: (diameter - textSize.width) / 2.0,
                y: (diameter - textSize.height) / 2.0,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
    
    private static func makeIconAvatar(icon: SystemIcon, diameter: CGFloat, foregroundColor: UIColor, backgroundColor: UIColor) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))
            // Background circle
            let bgColor = backgroundColor
            bgColor.setFill()
            UIBezierPath(ovalIn: rect).fill()
            // Draw SF Symbol centered
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: diameter * 0.3, weight: .semibold)
            let symbol = UIImage(systemIcon: icon, withConfiguration: symbolConfig)?.withTintColor(foregroundColor, renderingMode: .alwaysOriginal)
            if let symbol {
                let symSize = symbol.size
                let symRect = CGRect(
                    x: (diameter - symSize.width) / 2.0,
                    y: (diameter - symSize.height) / 2.0,
                    width: symSize.width,
                    height: symSize.height
                )
                symbol.draw(in: symRect)
            }
        }
    }

}
