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
import ObvTypes
import ObvCircleAndTitlesView
import ObvDesignSystem
import ObvAppTypes


public struct OwnedIdentityAsGroupMemberViewModel: Sendable, Equatable {
    
    let ownedCryptoId: ObvCryptoId
    let isKeycloakManaged: Bool
    let profilePictureInitial: String?
    let circleColors: InitialCircleView.Model.Colors
    let identityDetails: ObvIdentityDetails
    let isAdmin: Bool
    let customDisplayName: String?
    let customPhotoURL: URL?
    
//    var isAdmin: Bool {
//        permissions.contains(.groupAdmin)
//    }

    public init(ownedCryptoId: ObvCryptoId, isKeycloakManaged: Bool, profilePictureInitial: String?, circleColors: InitialCircleView.Model.Colors, identityDetails: ObvIdentityDetails, isAdmin: Bool, customDisplayName: String?, customPhotoURL: URL?) {
        self.ownedCryptoId = ownedCryptoId
        self.isKeycloakManaged = isKeycloakManaged
        self.profilePictureInitial = profilePictureInitial
        self.circleColors = circleColors
        self.identityDetails = identityDetails
        self.isAdmin = isAdmin
        self.customDisplayName = customDisplayName
        self.customPhotoURL = customPhotoURL
    }

}


@MainActor
public protocol OwnedIdentityAsGroupMemberViewDataSource {
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>)
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvGroupIdentifier, streamUUID: UUID)
}


public struct OwnedIdentityAsGroupMemberView: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let dataSource: OwnedIdentityAsGroupMemberViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource

    public init(groupIdentifier: ObvGroupIdentifier, dataSource: OwnedIdentityAsGroupMemberViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource) {
        self.groupIdentifier = groupIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
    }
    
    @State private var model: OwnedIdentityAsGroupMemberViewModel?
    @State private var streamUUID: UUID?

    @State private var profilePicture: (url: URL, image: UIImage?)?

    private var avatarSize: ObvDesignSystem.ObvAvatarSize {
        ObvDesignSystem.ObvAvatarSize.normal
    }

    private func updateProfilePictureIfRequired(model: OwnedIdentityAsGroupMemberViewModel, photoURL: URL?) async {
        guard self.profilePicture?.url != photoURL else { return }
        guard let photoURL else {
            withAnimation {
                self.profilePicture = nil
            }
            return
        }
        self.profilePicture = (photoURL, nil)
        do {
            let image = try await avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: photoURL, avatarSize: avatarSize)
            guard self.profilePicture?.url == photoURL else { return } // The fetched photo is outdated
            withAnimation {
                self.profilePicture = (photoURL, image)
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    private func onAppear() {
        Task {
            do {
                
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(self, groupIdentifier: groupIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(self, groupIdentifier: groupIdentifier, streamUUID: previousStreamUUID)
                }
                self.streamUUID = streamUUID
                for await model in stream {
                    if self.model == nil {
                        self.model = model
                    } else {
                        withAnimation { self.model = model }
                    }
                    Task { await updateProfilePictureIfRequired(model: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func onDisappear() {
        if let streamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(self, groupIdentifier: groupIdentifier, streamUUID: streamUUID)
            self.streamUUID = nil
        }
    }

    public var body: some View {
        InternalView(model: model,
                     profilePicture: profilePicture,
                     avatarSize: avatarSize)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }
    
    private struct InternalView: View {
        
        let model: OwnedIdentityAsGroupMemberViewModel?
        let profilePicture: (url: URL, image: UIImage?)?
        let avatarSize: ObvDesignSystem.ObvAvatarSize

        private func profilePictureViewModelContent(model: OwnedIdentityAsGroupMemberViewModel) -> ProfilePictureView.Model.Content {
            .init(text: model.profilePictureInitial,
                  icon: .person,
                  profilePicture: profilePicture?.image,
                  showGreenShield: model.isKeycloakManaged,
                  showRedShield: false)
        }

        private func profilePictureViewModel(model: OwnedIdentityAsGroupMemberViewModel) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModelContent(model: model),
                  colors: model.circleColors,
                  circleDiameter: avatarSize.frameSize.width)
        }

        private func textViewModel(model: OwnedIdentityAsGroupMemberViewModel) -> TextView.Model {
            let coreDetails = model.identityDetails.coreDetails
            let badge = String(localizedInThisBundle: "YOU")
            if let customDisplayName = model.customDisplayName, !customDisplayName.isEmpty {
                return .init(titlePart1: nil,
                             titlePart2: customDisplayName,
                             subtitle: coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                             subsubtitle: coreDetails.getDisplayNameWithStyle(.positionAtCompany),
                             badge: badge)
            } else {
                return .init(titlePart1: coreDetails.firstName,
                             titlePart2: coreDetails.lastName,
                             subtitle: coreDetails.position,
                             subsubtitle: coreDetails.company,
                             badge: badge)
            }
        }

        var body: some View {
            if let model {
                HStack {
                    ProfilePictureView(model: profilePictureViewModel(model: model))
                    TextView(model: textViewModel(model: model))
                    Spacer()
                    VStack {
                        if model.isAdmin {
                            Text("ADMIN")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tint(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                PlaceholderForUserCell(avatarSize: avatarSize)
            }
        }
    }
}





// MARK: - Previews

#if DEBUG

@MainActor
private final class DataSourceForPreviews {}

extension DataSourceForPreviews: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvGroupIdentifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

}

extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

#Preview {
    OwnedIdentityAsGroupMemberView(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                                   dataSource: dataSourceForPreviews,
                                   avatarViewDataSource: dataSourceForPreviews)
}

#endif
