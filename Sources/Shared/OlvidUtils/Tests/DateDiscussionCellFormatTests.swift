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

import Testing
import Foundation
@testable import OlvidUtils


/// Tests for `Date.discussionCellFormat(relativeTo:)`, which decides how the discussions list and the CarPlay list show
/// the date of the latest message of a discussion.
///
/// `discussionCellFormat` builds its strings with `Date.formatted`, so their exact wording depends on the locale. These
/// tests therefore assert which *branch* was taken, by comparing against the same `formatted` call the branch uses.
/// That is the part that matters, and the part that was documented incorrectly: the doc comment used to promise a
/// "Yesterday" format that no branch produces.
///
/// All dates are derived from a reference through `Calendar.current`, the calendar the formatter itself uses, so these
/// tests hold whatever the time zone and first weekday of the machine running them.
struct DateDiscussionCellFormatTests {

    private static let calendar = Calendar.current

    /// Noon on a Wednesday, so that adding or removing a few hours cannot slip into another day, and so that the day
    /// before is in the same calendar week whether weeks start on Saturday, Sunday or Monday.
    private static func reference() throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
    }

    private static func date(_ days: Int, daysBefore reference: Date) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: -days, to: reference))
    }


    // MARK: - One test per branch

    @Test func aDateOnTheSameDayShowsTheTime() throws {
        let reference = try Self.reference()
        let earlierToday = try #require(Self.calendar.date(byAdding: .hour, value: -5, to: reference))

        #expect(Self.calendar.isDate(earlierToday, inSameDayAs: reference)) // Guards the premise of this test
        #expect(earlierToday.discussionCellFormat(relativeTo: reference) == earlierToday.formatted(date: .omitted, time: .shortened))
    }


    /// The documented absence of a "Yesterday" format: the day before shows as a weekday, exactly like any other day of
    /// the current week.
    @Test func yesterdayShowsTheAbbreviatedWeekdayRatherThanAWordingOfItsOwn() throws {
        let reference = try Self.reference()
        let yesterday = try Self.date(1, daysBefore: reference)

        #expect(Self.calendar.isDate(yesterday, inSameWeekAs: reference)) // Guards the premise of this test
        #expect(yesterday.discussionCellFormat(relativeTo: reference) == yesterday.formatted(.dateTime.weekday(.abbreviated)))
    }


    /// The trap the doc comment now spells out. `discussionCellFormat` compares calendar weeks, not a rolling seven
    /// days, so on the first day of the week the day before is *not* "this week": the most recent discussions show a
    /// bare numeric date all day.
    @Test func yesterdayShowsTheDayAndMonthWhenItFellInThePreviousCalendarWeek() throws {
        let reference = try Self.reference()
        let startOfThisWeek = try #require(Self.calendar.dateInterval(of: .weekOfYear, for: reference)).start
        let firstDayOfThisWeekAtNoon = try #require(Self.calendar.date(byAdding: .hour, value: 12, to: startOfThisWeek))
        let yesterday = try Self.date(1, daysBefore: firstDayOfThisWeekAtNoon)

        // Guards the premises of this test: one day apart, different weeks, same year
        #expect(!Self.calendar.isDate(yesterday, inSameWeekAs: firstDayOfThisWeekAtNoon))
        #expect(Self.calendar.isDate(yesterday, inSameYearAs: firstDayOfThisWeekAtNoon))

        #expect(yesterday.discussionCellFormat(relativeTo: firstDayOfThisWeekAtNoon) == yesterday.formatted(.dateTime.day().month(.defaultDigits)))
    }


    @Test func anEarlierDateInTheSameYearShowsTheDayAndMonth() throws {
        let reference = try Self.reference()
        let twoMonthsAgo = try Self.date(60, daysBefore: reference)

        #expect(Self.calendar.isDate(twoMonthsAgo, inSameYearAs: reference)) // Guards the premise of this test
        #expect(twoMonthsAgo.discussionCellFormat(relativeTo: reference) == twoMonthsAgo.formatted(.dateTime.day().month(.defaultDigits)))
    }


    @Test func aDateFromAnotherYearShowsTheYear() throws {
        let reference = try Self.reference()
        let lastYear = try Self.date(400, daysBefore: reference)

        #expect(!Self.calendar.isDate(lastYear, inSameYearAs: reference)) // Guards the premise of this test
        #expect(lastYear.discussionCellFormat(relativeTo: reference) == lastYear.formatted(.dateTime.day().month(.defaultDigits).year(.twoDigits)))
    }


    // MARK: - Properties that hold for every date

    /// There is no fifth format, in particular no "Yesterday". Checked day by day over more than a year, in both
    /// directions from the reference.
    @Test func everyDateFormatsAsOneOfTheFourDocumentedFormats() throws {
        let reference = try Self.reference()

        for days in -10...400 {
            let date = try Self.date(days, daysBefore: reference)
            let documentedFormats = [
                date.formatted(date: .omitted, time: .shortened),
                date.formatted(.dateTime.weekday(.abbreviated)),
                date.formatted(.dateTime.day().month(.defaultDigits)),
                date.formatted(.dateTime.day().month(.defaultDigits).year(.twoDigits)),
            ]
            let formatted = date.discussionCellFormat(relativeTo: reference)
            #expect(documentedFormats.contains(formatted), "\(formatted) is not one of the four documented formats, \(days) day(s) from the reference")
        }
    }


    /// The format only depends on the *calendar day* of the reference date. This is what lets the discussions list and
    /// the CarPlay list format relative to `ObvCurrentDayMonitor.shared.startOfCurrentDay` and refresh only when that
    /// day changes.
    @Test func theFormatDependsOnlyOnTheCalendarDayOfTheReference() throws {
        let reference = try Self.reference()
        let startOfReferenceDay = Self.calendar.startOfDay(for: reference)
        let lastInstantOfReferenceDay = try #require(Self.calendar.date(byAdding: .second, value: -1, to: Self.calendar.startOfNextDay(after: reference) ?? reference))

        for days in -10...400 {
            let date = try Self.date(days, daysBefore: reference)
            let formattedAtStartOfDay = date.discussionCellFormat(relativeTo: startOfReferenceDay)
            let formattedAtEndOfDay = date.discussionCellFormat(relativeTo: lastInstantOfReferenceDay)
            #expect(formattedAtStartOfDay == formattedAtEndOfDay, "The format changed within a single day, \(days) day(s) from the reference")
        }
    }


    /// `discussionCellFormat` is documented as `discussionCellFormat(relativeTo: .now)`, which is what the CarPlay data
    /// source still relies on.
    @Test func theConvenienceFormatIsRelativeToNow() throws {
        for days in [0, 1, 3, 60, 400] {
            let date = try Self.date(days, daysBefore: .now)
            #expect(date.discussionCellFormat == date.discussionCellFormat(relativeTo: .now))
        }
    }

}
