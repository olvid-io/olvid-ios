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
  
import ObvUI
import SwiftUI


struct TextView: View {

    let titlePart1: String?
    let titlePart2: String?
    let subtitle: String?
    let subsubtitle: String?

    private var titlePart1Count: Int { titlePart1?.count ?? 0 }
    private var titlePart2Count: Int { titlePart2?.count ?? 0 }
    private var subtitleCount: Int { subtitle?.count ?? 0 }
    private var subsubtitleCount: Int { subsubtitle?.count ?? 0 }

    /// This variable allows to control when an animation is performed on `titlePart1`.
    ///
    /// We do not want to animate a text made to the text of `titlePart1`, which is the reason why we cannot simply
    /// set an .animation(...) on the view `Text(titlePart1)`. Instead, we use another version of the animation
    /// modifier where we can provide a `value` that is used to determine when the animation should be active.
    /// We want it to be active when the *other* strings of this view change.
    ///
    /// For example, when the `subtitle` goes from empty to
    /// one character, we want `titlePart1` to move to the top in an animate way. As one can see, in that specific case,
    /// the value of `animateTitlePart1OnChange` will change when `subtitle` (or any of the other strings apart from
    /// `titlePart1`) changes. This is the reason why we use exactly this value for controling the animation of `titlePart1`.
    private var animateTitlePart1OnChange: Int {
        titlePart2Count + subtitleCount + subsubtitleCount
    }

    private var animateTitlePart2OnChange: Int {
        titlePart1Count + subtitleCount + subsubtitleCount
    }

    private var animateSubtitleOnChange: Int {
        titlePart1Count + titlePart2Count + subsubtitleCount
    }

    private var animateSubsubtitleOnChange: Int {
        titlePart1Count + titlePart2Count + subtitleCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if titlePart1 != nil || titlePart2 != nil {
                HStack(spacing: 0) {
                    if let titlePart1 = self.titlePart1, !titlePart1.isEmpty {
                        Group {
                            Text(titlePart1)
                                .font(.system(.headline, design: .rounded))
                                .lineLimit(1)
                                .animation(.spring(), value: animateTitlePart1OnChange)
                        }
                    }
                    if let titlePart1 = self.titlePart1, let titlePart2 = self.titlePart2, !titlePart1.isEmpty, !titlePart2.isEmpty {
                        Text(" ")
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                    }
                    if let titlePart2 = self.titlePart2, !titlePart2.isEmpty {
                        Text(titlePart2)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.heavy)
                            .lineLimit(1)
                            .animation(.spring(), value: animateTitlePart2OnChange)
                    }
                }
                .layoutPriority(0)
            }
            if let subtitle = self.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .lineLimit(1)
                    .animation(.spring(), value: animateSubtitleOnChange)
            }
            if let subsubtitle = self.subsubtitle, !subsubtitle.isEmpty {
                Text(subsubtitle)
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .lineLimit(1)
                    .animation(.spring(), value: animateSubsubtitleOnChange)
            }
        }
    }
}
