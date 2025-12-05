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

@MainActor
public protocol PublishedDetailsValidationViewActionsProtocol {
    func userHasSeenPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws
}


public struct DifferencesBetweenTrustedAndPublished: OptionSet, Sendable {
    public let rawValue: Int
    public static let name = DifferencesBetweenTrustedAndPublished(rawValue: 1 << 0)
    public static let description = DifferencesBetweenTrustedAndPublished(rawValue: 1 << 1)
    public static let photo = DifferencesBetweenTrustedAndPublished(rawValue: 1 << 2)
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}


public struct PublishedDetailsValidationViewModel: Sendable, Equatable {
    
    public let groupIdentifier: ObvGroupIdentifier
    public let publishedName: String
    public let publishedDescription: String?
    public let publishedPhotoURL: URL?
    let circleColors: InitialCircleView.Model.Colors
    public let differences: DifferencesBetweenTrustedAndPublished
    let isKeycloakManaged: Bool
    
    public init(groupIdentifier: ObvGroupIdentifier, publishedName: String, publishedDescription: String?, publishedPhotoURL: URL?, circleColors: InitialCircleView.Model.Colors, differences: DifferencesBetweenTrustedAndPublished, isKeycloakManaged: Bool) {
        self.groupIdentifier = groupIdentifier
        self.publishedName = publishedName
        self.publishedDescription = publishedDescription
        self.publishedPhotoURL = publishedPhotoURL
        self.circleColors = circleColors
        self.differences = differences
        self.isKeycloakManaged = isKeycloakManaged
    }
    
    var description: LocalizedStringKey {
        switch (differences.contains(.name), differences.contains(.description), differences.contains(.photo)) {
        case (false, false, false):
            "THE_GROUP_NAME_DESCRIPTION_OR_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        case (false, false, true):
            "THE_GROUP_PHOTO_WAS_UPDATED_AS_FOLLOWS"
        case (false, true, false):
            "THE_GROUP_DESCRIPTION_WAS_UPDATED_AS_FOLLOWS"
        case (false, true, true):
            "THE_GROUP_DESCRIPTION_AND_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        case (true, false, false):
            "THE_GROUP_NAME_WAS_UPDATED_AS_FOLLOWS"
        case (true, false, true):
            "THE_GROUP_NAME_AND_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        case (true, true, false):
            "THE_GROUP_NAME_AND_DESCRIPTION_WERE_UPDATED_AS_FOLLOWS"
        case (true, true, true):
            "THE_GROUP_NAME_DESCRIPTION_AND_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        }
    }
    
    var accessibilityLabel: Text {
        return Text("VALIDATION_REQUIRED") + Text(verbatim: ",") + Text(description) + Text(verbatim: ",") + Text(publishedName) + Text(verbatim: ",") + Text(publishedDescription ?? "") + Text(verbatim: ",") + Text(differences.contains(.photo) ? "IMAGE" : "") + Text(verbatim: ",") + Text("TAP_TO_ACCEPT")
        
    }
    
}


/// This view is shown when the group has published details that need to be validated by the user.
public struct GroupPublishedDetailsValidationView: View {

    let model: PublishedDetailsValidationViewModel
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: PublishedDetailsValidationViewActionsProtocol
    
    public init(model: PublishedDetailsValidationViewModel, avatarViewDataSource: ObvAvatarViewDataSource, actions: PublishedDetailsValidationViewActionsProtocol) {
        self.model = model
        self.avatarViewDataSource = avatarViewDataSource
        self.actions = actions
    }

    @State private var publishedPhoto: UIImage?
    @State private var disabled: Bool = false
    
    
    private var profilePictureViewModelContentForPublishedDetails: ProfilePictureView.Model.Content {
        .init(text: nil,
              icon: .person3Fill,
              profilePicture: publishedPhoto,
              showGreenShield: model.isKeycloakManaged,
              showRedShield: false)
    }

    private var textViewModelForPublishedDetails: TextView.Model {
        .init(titlePart1: model.publishedName,
              titlePart2: nil,
              subtitle: model.publishedDescription,
              subsubtitle: nil)
    }

    private var circleAndTitlesViewModelContentForPublishedDetails: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModelForPublishedDetails,
              profilePictureViewModelContent: profilePictureViewModelContentForPublishedDetails)
    }

    private var circleAndTitlesViewModelForPublishedDetails: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContentForPublishedDetails,
              colors: model.circleColors,
              displayMode: .normal,
              editionMode: .none)
    }
    
    private func onTask() async {
        guard let publishedPhotoURL = model.publishedPhotoURL else { return }
        await fetchPublishedPhoto(publishedPhotoURL: publishedPhotoURL)
    }
    
    private func onChangeOfPublishedPhotoURL(newPublishedPhotoURL: URL?) {
        self.publishedPhoto = nil
        guard let newPublishedPhotoURL else { return }
        Task {
            await fetchPublishedPhoto(publishedPhotoURL: newPublishedPhotoURL)
        }
    }
    
    private func okButtonTapped() {
        disabled = true
        Task {
            defer { disabled = false }
            try await actions.userWantsToReplaceTrustedDetailsByPublishedDetails(self, publishedDetails: model)
        }
    }
    
    private func fetchPublishedPhoto(publishedPhotoURL: URL) async {
        // Quick and dirty: we enforce a `.normal` avatar size as this is coherent with the `.normal` display mode chosen in circleAndTitlesViewModelForPublishedDetails.
        guard let publishedPhoto = try? await avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: publishedPhotoURL, avatarSize: .normal) else { return }
        withAnimation {
            self.publishedPhoto = publishedPhoto
        }
    }
    
    private func onAppear() {
        Task {
            do {
                try await actions.userHasSeenPublishedDetails(self, publishedDetails: model)
            } catch {
                assertionFailure()
            }
        }
    }

    public var body: some View {
        VStack {
            
            HStack(alignment: .firstTextBaseline) {
                Text("VALIDATION_REQUIRED")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                Image(systemIcon: .personTextRectangle)
                    .foregroundStyle(.red)
                Spacer()
            }

            ObvCardView(padding: 0) {
                
                VStack {
                    
                    HStack(spacing: 0) {
                        Text(model.description)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                    Divider()
                    
                    HStack(spacing: 0) {
                        CircleAndTitlesView(model: circleAndTitlesViewModelForPublishedDetails)
                        Spacer(minLength: 0)
                    }
                    
                    Divider()

                    HStack {
                        Text("TO_REFLECT_THESE_CHANGES_ON_YOUR_DEVICE_YOU_NEED_TO_ACCEPT_THEM")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        Spacer()
                        if disabled {
                            ProgressView()
                        }
                        Button(action: okButtonTapped) {
                            Text("ACCEPT")
                        }
                        .buttonStyle(.borderedProminent)

                    }
                    
                }
                .padding()
                
            }
            
        }
        .disabled(disabled)
        .task(self.onTask)
        .onChange(of: model.publishedPhotoURL) { newPublishedPhotoURL in
            onChangeOfPublishedPhotoURL(newPublishedPhotoURL: newPublishedPhotoURL)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .onAppear(perform: onAppear)
    }
    
}















// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: PublishedDetailsValidationViewActionsProtocol {
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        try await Task.sleep(seconds: 2)
    }
            
    func userHasSeenPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {}
    
}

private final class DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.groupPictureForURL[photoURL]
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.groupPictureForURL[photoURL]
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    
}


private let dataSourceForPreviews = DataSourceForPreviews()
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let modelsForPreviews: [PublishedDetailsValidationViewModel] = [
    .init(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
          publishedName: "The published name",
          publishedDescription: "The published description",
          publishedPhotoURL: PreviewsHelper.photoURL[0],
          circleColors: ObvCircleAndTitlesView.InitialCircleView.Model.Colors(background: .red, foreground: .blue),
          differences: [.photo],
          isKeycloakManaged: false),
    .init(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
          publishedName: "The new published name",
          publishedDescription: "The new published description",
          publishedPhotoURL: PreviewsHelper.photoURL[1],
          circleColors: ObvCircleAndTitlesView.InitialCircleView.Model.Colors(background: .red, foreground: .blue),
          differences: [.photo, .name, .description],
          isKeycloakManaged: false),
]




#Preview {
    GroupPublishedDetailsValidationView(model: modelsForPreviews[0],
                                        avatarViewDataSource: dataSourceForPreviews,
                                        actions: actionsForPreviews)
}


private struct TestingUpdateView: View {
    
    @State var model: PublishedDetailsValidationViewModel = modelsForPreviews[0]
    
    private func onTask() async {
        try! await Task.sleep(seconds: 3)
        withAnimation {
            self.model = modelsForPreviews[1]
        }
    }

    var body: some View {
        GroupPublishedDetailsValidationView(model: model,
                                            avatarViewDataSource: dataSourceForPreviews,
                                       actions: actionsForPreviews)
        .task(onTask)
    }
    
}

#Preview("Testing update") {
    TestingUpdateView()
}

#endif
