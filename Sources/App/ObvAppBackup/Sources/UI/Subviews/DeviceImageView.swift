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

struct DeviceImageView: View {
    let platform: OlvidPlatform
    var body: some View {
        Image(systemIcon: platform.deviceIcon)
            .font(.system(size: 20))
            .frame(width: 48, height: 48)
            .background(Color(.systemFill))
            .clipShape(RoundedRectangle(cornerSize: .init(width: 12, height: 12)))
    }
}

#Preview {
    DeviceImageView(platform: .iPhone)
}
