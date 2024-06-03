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
  

import Foundation
import MobileCoreServices
import ObvTypes
import ObvUI
import OlvidUtils
import os.log
import QuickLookThumbnailing
import SwiftUI
import CoreData
import ObvUICoreData
import UI_SystemIcon
import ObvSettings


final class ShareViewModel: ObservableObject, DiscussionsHostingViewControllerDelegate, ObvErrorMaker {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: "ShareViewController"))
    static var errorDomain = "ShareViewModel"
    
    enum ThumbnailValue {
        case loading
        case symbol(_ symbol: SystemIcon)
        case image(_ image: UIImage)
    }
    
    struct Thumbnail: Identifiable {
        let index: Int
        let value: ThumbnailValue
        var id: Int { index }
    }
    
    @Published private(set) var text: String = ""
    @Published private(set) var selectedDiscussions: [PersistedDiscussion] = []
    @Published var thumbnails: [Thumbnail]? = nil
    @Published private(set) var selectedOwnedIdentity: PersistedObvOwnedIdentity
    @Published private(set) var messageIsSending: Bool = false
    @Published private(set) var bodyTextHasBeenSet: Bool = false
    @Published var isAuthenticated: Bool = false

    private var viewIsClosing: Bool = false
    private(set) var hardlinks: [HardLinkToFyle?]? = nil

    let allOwnedIdentities: [PersistedObvOwnedIdentity]

    weak var delegate: ShareViewModelDelegate?
    
    private let viewContext: NSManagedObjectContext
    
    init(allOwnedIdentities: [PersistedObvOwnedIdentity]) throws {
        let contexts = Set(allOwnedIdentities.compactMap({ $0.managedObjectContext }))
        guard contexts.count == 1, let context = contexts.first else {
            throw Self.makeError(message: "Unexpected number of contexts. Expecting 1, got \(contexts.count)")
        }
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            throw Self.makeError(message: "Unexpected concurrency type for the context")
        }
        self.viewContext = context
        self.allOwnedIdentities = allOwnedIdentities
        // Select an appropriate owned identity
        if let firstOwnedIdentity = allOwnedIdentities.first {
            let nonHiddenCryptoId = LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStoredSynchronously()?.nonHiddenCryptoId
            if let nonHiddenCryptoId {
                self.selectedOwnedIdentity = allOwnedIdentities.first(where: { $0.cryptoId == nonHiddenCryptoId }) ?? firstOwnedIdentity
            } else {
                self.selectedOwnedIdentity = firstOwnedIdentity
            }
        } else {
            throw Self.makeError(message: "The array of owned identities cannot be empty")
        }
    }

    @MainActor
    func setSelectedOwnedIdentity(to ownedIdentity: PersistedObvOwnedIdentity) async throws {
        guard selectedOwnedIdentity != ownedIdentity else { return }
        selectedOwnedIdentity = ownedIdentity
        try await setSelectedDiscussions(to: [])
    }
    
    @MainActor
    func setSelectedDiscussions(to discussions: [PersistedDiscussion]) async throws {
        let discussionsToConsider = discussions.filter({ $0.ownedIdentity != nil })
        let concernOwnedIdentities = Set(discussionsToConsider.compactMap({ $0.ownedIdentity }))
        
        if concernOwnedIdentities.count > 1 {
            // We shouldn't be able to receive discussions from multiple owned identities here
            throw Self.makeError(message: "Can only set discussions from distinct owned identities")
        }
        
        if let concernOwnedIdentity = concernOwnedIdentities.first {
            /* When using the share extension via Siri (where the user selects a specific discussion to share with),
             * the chosen discussion will already be determined. We then pick the owned identity associated
             * with that discussion.
             */
            selectedOwnedIdentity = concernOwnedIdentity
        }
        self.selectedDiscussions = discussionsToConsider
    }

    func setBodyTexts(_ bodyTexts: [String]) {
        assert(!self.bodyTextHasBeenSet)
        for bodyText in bodyTexts {
            text.append(bodyText)
        }
        DispatchQueue.main.async {
            self.bodyTextHasBeenSet = true
        }
    }

    func setHardlinks(_ hardlinks: [HardLinkToFyle?]) {
        self.hardlinks = hardlinks
        var thumbnails = [Thumbnail]()
        for index in 0..<hardlinks.count {
            thumbnails += [Thumbnail(index: index, value: .loading)]
        }
        DispatchQueue.main.async {
            withAnimation {
                self.thumbnails = thumbnails
            }
        }
        Task {
            for index in 0..<hardlinks.count {
                guard let hardlink = hardlinks[index] else { assertionFailure(); continue }
                let symbolOrImage = await createThumbnail(hardlink: hardlink)
                DispatchQueue.main.async {
                    withAnimation {
                        self.thumbnails?[index] = Thumbnail(index: index, value: symbolOrImage)
                    }
                }
            }
        }
    }

    var userCanSendsMessages: Bool {
        guard !messageIsSending else { return false }
        return !selectedDiscussions.isEmpty
    }

    var discussionsModel: DiscussionsViewModel {
        let frcModel = PersistedDiscussion.getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with: selectedOwnedIdentity.cryptoId)
        let discussions = (try? viewContext.fetch(frcModel.fetchRequest)) ?? []
        let allDiscussionViewModels: [DiscussionViewModel] = discussions.compactMap { discussion in
            let isSelected = selectedDiscussions.contains(discussion)
            return DiscussionViewModel(persistedDiscussion: discussion,
                                       selected: isSelected,
                                       style: ObvMessengerSettings.Interface.identityColorStyle)
        }
        let discussionsViewModel = DiscussionsViewModel(discussions: allDiscussionViewModels)
        discussionsViewModel.delegate = self
        return discussionsViewModel
    }

    var isDisabled: Bool {
        // Disable the view until authentication was performed
        // Disable the view until bodyTexts have been set
        !self.isAuthenticated || !self.bodyTextHasBeenSet
    }

    var textBinding: Binding<String> {
        .init {
            self.text
        } set: {
            guard !self.isDisabled else { return }
            self.text = $0
        }

    }

    func userWantsToCloseView() {
        guard !viewIsClosing else { return }
        viewIsClosing = true
        delegate?.closeView()
    }

    func viewIsDisappeared() {
        guard !viewIsClosing else { return } // Avoid to execute twice closeView if the user has tap close button
        guard !messageIsSending else { return } // Avoid to execute twice closeView if the user wants to send the message
        delegate?.closeView()
    }

    func userWantsToSendMessages(to discussions: [PersistedDiscussion]) {
        guard !messageIsSending else { return }
        self.messageIsSending = true
        Task {
            await delegate?.userWantsToSendMessages(to: discussions)
        }
    }

    private func createThumbnail(hardlink: HardLinkToFyle?) async -> ThumbnailValue {
        guard let hardlink = hardlink else { return .symbol(.paperclip) }
        guard let hardlinkURL = hardlink.hardlinkURL else { return .symbol(.paperclip) }
        let scale = await UIScreen.main.scale
        let size = CGSize(width: 80, height: 80)
        let request = QLThumbnailGenerator.Request(fileAt: hardlinkURL, size: size, scale: scale, representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        do {
            let thumbnail = try await generator.generateBestRepresentation(for: request)
            return .image(thumbnail.uiImage)
        } catch {
            return .symbol(hardlink.contentType.systemIcon)
        }
    }
}

extension ShareViewModel: OwnedIdentityChooserViewControllerDelegate {
    func userUsedTheOwnedIdentityChooserViewControllerToChoose(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: viewContext) else {
            os_log("Could not find owned identity", log: Self.log, type: .error)
            return
        }
        do {
            try await setSelectedOwnedIdentity(to: ownedIdentity)
        } catch {
            os_log("when processUserWantsToSwitchToOtherOwnedIdentity: %@", log: Self.log, type: .error)
        }
    }
    
    func userWantsToEditCurrentOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId) async { }
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityEdition: Bool { false }
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityCreation: Bool { false }
    
    var ownedIdentityChooserViewControllerExplanationString: String? { nil }
}
