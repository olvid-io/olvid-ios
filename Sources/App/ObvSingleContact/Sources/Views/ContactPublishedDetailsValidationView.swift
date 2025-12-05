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
import ObvDesignSystem
import ObvTypes
import ObvCircleAndTitlesView



struct ContactPublishedDetailsValidationViewModel: Sendable, Equatable {
    let contactIdentifier: ObvContactIdentifier
    let trustedDetails: ObvIdentityDetails
    let publishedDetails: ObvIdentityDetails
    let avatarModelFromPublishedDetails: ObvAvatarViewModel
}


@MainActor
protocol ContactPublishedDetailsValidationViewActions {
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: ContactPublishedDetailsValidationView, contactIdentifier: ObvContactIdentifier, publishedDetails: ObvIdentityDetails) async throws
}


struct ContactPublishedDetailsValidationView: View {
    
    let viewModel: ContactPublishedDetailsValidationViewModel
    let avatarViewDataSource: ObvAvatarViewDataSource
    let internalActions: ContactPublishedDetailsValidationViewActions
    
    @State private var disabled: Bool = false

    private var differences: ObvIdentityDetails.Differences {
        viewModel.trustedDetails.differencesWith(viewModel.publishedDetails)
    }

    var description: LocalizedStringKey {
        switch (differences.contains(.firstName), differences.contains(.lastName), differences.contains(.photo)) {
        case (false, false, false):
            "THE_CONTACT_NAME_DESCRIPTION_OR_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        case (false, false, true):
            "THE_CONTACT_PHOTO_WAS_UPDATED_AS_FOLLOWS"
        case (false, true, false):
            "THE_CONTACT_LAST_NAME_WAS_UPDATED_AS_FOLLOWS"
        case (false, true, true):
            "THE_CONTACT_LAST_NAME_AND_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        case (true, false, false):
            "THE_CONTACT_FIRST_NAME_WAS_UPDATED_AS_FOLLOWS"
        case (true, false, true):
            "THE_CONTACT_FIRST_NAME_AND_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        case (true, true, false):
            "THE_CONTACT_FIRST_NAME_AND_LAST_NAME_WERE_UPDATED_AS_FOLLOWS"
        case (true, true, true):
            "THE_CONTACT_FIRST_NAME_LAST_NAME_AND_PHOTO_WERE_UPDATED_AS_FOLLOWS"
        }
    }


    private func okButtonTapped() {
        disabled = true
        Task {
            defer { disabled = false }
            try await internalActions.userWantsToReplaceTrustedDetailsByPublishedDetails(self, contactIdentifier: viewModel.contactIdentifier, publishedDetails: viewModel.publishedDetails)
        }
    }
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: viewModel.publishedDetails.coreDetails.firstName,
              titlePart2: viewModel.publishedDetails.coreDetails.lastName,
              subtitle: viewModel.publishedDetails.getDisplayNameWithStyle(.positionAtCompany),
              subsubtitle: nil)
    }

    var body: some View {
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
                        Text(description)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .top])
                    .padding(.bottom, 4)

                    Divider()
                    
                    HStack {
                        ObvAvatarView(model: viewModel.avatarModelFromPublishedDetails,
                                      style: .circle,
                                      size: .custom(frameSize: .init(width: 60, height: 60)),
                                      dataSource: avatarViewDataSource)
                        TextView(model: textViewModel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    HStack {
                        Text("TO_REFLECT_THESE_CHANGES_ON_YOUR_DEVICE_YOU_NEED_TO_ACCEPT_THEM")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding([.horizontal])
                    .padding(.top, 4)

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
                    .padding([.horizontal, .bottom])
                    
                }

            }
            
        }
    }
    
}



// MARK: - Previews

#if DEBUG

private final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
        
}

extension DataSourceAndActionsForPreviews: ContactPublishedDetailsValidationViewActions {
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: ContactPublishedDetailsValidationView, contactIdentifier: ObvContactIdentifier, publishedDetails: ObvIdentityDetails) async throws {
        print("User wants to replace trusted details by published details")
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    ContactPublishedDetailsValidationView(
        viewModel: .sampleData,
        avatarViewDataSource: dataSourceAndActionsForPreviews,
        internalActions: dataSourceAndActionsForPreviews)
    .padding()
    .background(Color(UIColor.systemGroupedBackground))
}


#endif
