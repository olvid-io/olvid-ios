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

import SwiftUI


/// The day a message opens, shown above it, as a small capsule centred over the discussion.
///
/// **The look is the new design's and not the legacy screen's**, which is the one part of this screen that departs from it deliberately: `DateSupplementaryView`
/// draws a 28pt rounded bold title across the width of a section, where this is a compact chip. What is transcribed is the *wording* — see ``title(of:)`` — since
/// that is a product decision and not a decoration.
///
/// A single unit, on purpose: the design has a chevron beside the label, opening a picker of the days of the discussion, and it is to become a button. Neither the
/// chevron nor the picker is here yet, and nothing about this shape has to change when they arrive.
///
/// Drawn **inside the cell of the first message of the day**, and not inserted as a row of its own. It therefore moves with its message without anything having to
/// keep the two in step, and it costs the list neither an identifier nor a place in the scroll. A picker
/// is no reason to make a separator addressable.
struct DateSeparatorView: View {

    /// The start of the day being named. Formatted here, and never in the data source: "Today" would otherwise be baked into a model that outlives the day.
    let day: Date

    var body: some View {
        Text(verbatim: Self.title(of: day))
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(UIColor.label))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Self.horizontalInsetOfTheCapsule)
            .padding(.vertical, Self.verticalInsetOfTheCapsule)
            // A *fill* rather than a solid colour, so that the capsule sits on whatever is behind it — and the faintest of the four, chosen by eye against the
            // design: the label is what has to be read, and the capsule only has to hold it.
            .background(Color(UIColor.quaternarySystemFill), in: Capsule())
            // Centred *after* the capsule, so that it hugs its label rather than spanning the row.
            .frame(maxWidth: .infinity, alignment: .center)
            // The air a section header has in `DiscussionLayout`: `interSectionSpacing` above and `interItemSpacing` below, both 10pt. The row this sits in already
            // contributes 4pt of its own above, which is what the 6 is.
            .padding(.top, 6)
            .padding(.bottom, 10)
    }


    private static let horizontalInsetOfTheCapsule: CGFloat = 12

    private static let verticalInsetOfTheCapsule: CGFloat = 6


    /// How the legacy screen words a day, transcribed from `getSectionTitle(at:)`: today and yesterday by name, a day of the current month by its weekday and its
    /// number, an older day of the current year without its year, and anything older with it. Capitalized, as it is there.
    ///
    /// The wording is transcribed even though the drawing is not: what a day is called is the same decision on both screens, and a reader moving between them
    /// should not find two vocabularies.
    private static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) || calendar.isDateInYesterday(day) {
            return todayOrYesterday.string(from: day).capitalized
        }
        guard calendar.isDate(day, equalTo: Date.now, toGranularity: .year) else {
            return anOlderDay.string(from: day).capitalized
        }
        if calendar.isDate(day, equalTo: Date.now, toGranularity: .month) {
            return [theWeekday.string(from: day).capitalized, theDayOfTheMonth.string(from: day)].joined(separator: " ")
        }
        return aDayOfThisYear.string(from: day).capitalized
    }


    // MARK: The formatters, transcribed from `NewSingleDiscussionViewController`
    //
    // `DateFormatter` rather than a `Date.FormatStyle` as the rest of this screen uses, for one reason: `doesRelativeDateFormatting` is what gives a localized
    // "Today" and "Yesterday", and no format style has an equivalent of it.
    //
    // Statics because building a `DateFormatter` is expensive and this runs while the list is drawn.

    private static let todayOrYesterday: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .none
        df.dateStyle = .short
        return df
    }()

    private static let theWeekday: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEEE")
        return df
    }()

    private static let theDayOfTheMonth: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("d")
        return df
    }()

    private static let aDayOfThisYear: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = false
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEE d MMMM")
        return df
    }()

    private static let anOlderDay: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = false
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEE d MMMM yyyy")
        return df
    }()

}


#if DEBUG

/// Every wording, over the background of a discussion — which the capsule is drawn against and must stay legible on.
#Preview {
    DateSeparatorsForPreviews()
}


/// The same, in the appearance the design was drawn in.
#Preview {
    DateSeparatorsForPreviews()
        .preferredColorScheme(.dark)
}


private struct DateSeparatorsForPreviews: View {

    var body: some View {
        VStack(spacing: 0) {
            DateSeparatorView(day: Date.now)
            DateSeparatorView(day: Date.now.addingTimeInterval(-86_400))
            DateSeparatorView(day: Date.now.addingTimeInterval(-5 * 86_400))
            DateSeparatorView(day: Date.now.addingTimeInterval(-60 * 86_400))
            DateSeparatorView(day: Date.now.addingTimeInterval(-500 * 86_400))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(UIColor.systemBackground))
    }

}

#endif
