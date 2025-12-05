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

/// These actions are expected to be implemented by the view that embedds the `ObvButtonsForListOfDevicesView`.
@MainActor
protocol ObvButtonsForListOfDevicesViewActions {
    func userWantsToSearchForMissingDevices() -> Void
    func userWantsToClearAllDevices() -> Void
}


// MARK: - ObvButtonsForListOfDevicesView

struct ObvButtonsForListOfDevicesView: View {
    
    let actions: ObvButtonsForListOfDevicesViewActions
    
    var body: some View {
        VStack {
            SearchForMissingDevicesButton(action: actions.userWantsToSearchForMissingDevices)
            ClearAllDevicesButton(action: actions.userWantsToClearAllDevices)
        }
    }
    
}


// MARK: - Internal view

private struct ClearAllDevicesButton: View {

    let action: () -> Void
    
    private let verticalPadding: CGFloat = 4.0
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label(title: { Text("CLEAR_ALL_DEVICES") }, icon: { Image(systemIcon: .trash) })
                    .padding(.vertical, verticalPadding)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
            .tint(.red)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Label(title: { Text("CLEAR_ALL_DEVICES") }, icon: { Image(systemIcon: .trash) })
                    Spacer(minLength: 0)
                }
                .padding(.vertical, verticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
    
}


// MARK: - Internal view

private struct SearchForMissingDevicesButton: View {

    let action: () -> Void
    
    private let verticalPadding: CGFloat = 4.0
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label(title: { Text("SEARCH_FOR_NEW_DEVICES") }, icon: { Image(systemIcon: .magnifyingglass) })
                    .padding(.vertical, verticalPadding)
            }
            .buttonStyle(.glass)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Label(title: { Text("SEARCH_FOR_NEW_DEVICES") }, icon: { Image(systemIcon: .magnifyingglass) })
                    Spacer(minLength: 0)
                }
                .padding(.vertical, verticalPadding)
            }
            .buttonStyle(.bordered)
        }
    }
    
}



#if DEBUG

// MARK: - Previews

private struct ActionsForPreviews: ObvButtonsForListOfDevicesViewActions {
    
    func userWantsToSearchForMissingDevices() {
        print("User wants to search for missing devices")
    }
    
    func userWantsToClearAllDevices() {
        print("User wants to clear all devices")
    }
    
}


private let actionsForPreviews = ActionsForPreviews()

#Preview {
    ObvButtonsForListOfDevicesView(actions: actionsForPreviews)
        .padding(.horizontal)
}


#endif
