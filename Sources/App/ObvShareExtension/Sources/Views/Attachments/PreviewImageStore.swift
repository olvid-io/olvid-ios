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

import UIKit
import ImageIO
import AVFoundation
import QuickLookThumbnailing
import os
import OSLog
import ObvAppCoreConstants

/// The previews the share extension is holding, and the only thing that decodes one.
///
/// It replaced an `NSCache` on 2026-09-02, after three runs on an iPhone 13 measured what that cache was really doing.
/// Three findings shaped every decision below, and each is a measurement rather than a judgement:
///
/// **One. The limit is 120 MB, `ActiveHard`, fatal**, and how many decodes overlap is the one number that predicts
/// whether the extension lives: one in flight peaked at 68–76 MB, two at **96 MB every single time** — the warning
/// threshold — and three at over 120, where the kernel kills. Three was not bad luck but the structural case: a page
/// appearing decoded its own picture while the pager prefetched *both* its neighbours. So the rule that matters most
/// here is not how much is held but **how much is being built at once**, and this type decodes strictly one at a time.
///
/// **Two. The old cache retained nothing at all.** Every insert was followed by an eviction of that same image *in the
/// same millisecond*; the resident set was never above zero. So no swipe back was ever instant, every revisit decoded
/// again — one file was decoded four times in ten seconds — and the prefetch was pure waste, paying a bitmap and its
/// working set for an entry discarded before anyone could read it. Worse, it was a loop: overlapping decodes reached
/// 96 MB, the warning purged the cache, and the empty cache forced the next page change to decode everything again.
/// A dictionary this type owns cannot be emptied behind its back, which is the whole reason it is a dictionary.
///
/// **Three. A decode's working set is roughly 1.8–2.6× the bitmap it produces** — 12.8 MB of picture cost 23 MB of
/// footprint, reproducibly. That is why the *transient* is bounded here by serialising, and the *resident* by a window:
/// they are two different quantities and only one of them is what kills.
///
/// What it therefore guarantees: at most ``sizeOfTheWindow`` pictures are held, at most ``bytesPerPreview`` each, and
/// at most **one** decode is running. Nothing else in the module decodes a preview.
@MainActor
public final class PreviewImageStore: ObservableObject {

    public static let shared = PreviewImageStore()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PreviewMemory")

    private init() {}


    // MARK: - The rules, as numbers

    /// How many pictures may be held: the page on screen and the one either side.
    ///
    /// Three is what a swipe can reach. A fourth would be held for a gesture that cannot happen in one movement.
    static let sizeOfTheWindow = 3

    /// The most a single picture may weigh.
    ///
    /// **This is not what an iPhone needs — it is what an iPad cannot be allowed to ask for.** Sized to what is drawn
    /// (``fittedSize(aspectRatio:in:)``), a portrait photograph on an iPhone 13 comes to 6.9 MB and a landscape one to
    /// 3.1 MB, so this ceiling never engages there. On an iPad the page box can be 1000×1200pt, which at 2× is 19 MB —
    /// *worse* than the flat 2048 cap this replaces. So the ceiling exists for the platform that would otherwise be
    /// made worse by right-sizing, and on the platform this bug was reported on it is inert.
    ///
    /// Three of these plus one decode's working set is about 34 MB, against a 120 MB limit and a 96 MB warning.
    static let bytesPerPreview = 8 * 1_024 * 1_024

    /// The shape assumed for a photograph whose own shape is unknown, because its header could not be read.
    ///
    /// **It must agree with what the placeholder reserves**, which is `ImageView.placeholderView`'s
    /// `aspectRatio(media.aspectRatio ?? 16/9)`. The placeholder sizes the box, so a picture of unknown shape is drawn
    /// fitted into *this* ratio whatever the file turns out to be — and a store that assumed something else would size
    /// the decode for a box that is never used. Two constants that must match are one constant.
    ///
    /// It is **not** the right answer for every kind, which is why it is reached through ``Page/Kind/assumedAspectRatio``
    /// rather than used directly. See that property.
    nonisolated static let assumedAspectRatio: CGFloat = 16 / 9


    // MARK: - What the store needs to know about a page

    /// One page of the pager, as far as previewing is concerned.
    struct Page: Hashable {

        let url: URL
        let kind: Kind

        /// The file's own dimensions, already read from its header by `SharedState.HardLink.pixelSize` — so knowing the
        /// shape of every shared photograph costs no decode. Nil for a video or a document, whose shape is not known
        /// until something has rendered them.
        let sourcePixelSize: CGSize?

        enum Kind: Hashable {
            /// ImageIO, downsampled at decode time.
            case photo
            /// A frame of the film, from AVFoundation.
            case video
            /// Whatever QuickLook can make of the file.
            case document

            /// The shape to assume when the file's own is not known, or nil to ask for the whole page box.
            ///
            /// **The distinction is what the renderer does with the box it is given, not what kind of file it is.**
            ///
            /// `AVAssetImageGenerator` and `QLThumbnailGenerator` both fit the source *inside* the box while preserving
            /// its own proportions, so handing either of them the whole box returns exactly what will be drawn,
            /// whatever shape the file turns out to be. Naming a ratio can only be wrong there, and it was: a portrait
            /// A4 asked for against a 16:9 box came back 426×603 where 1074×1519 is drawn, and a portrait video came
            /// back 339×603 where 963×1713 is drawn — **upscaled 2.5× and 2.84×**, both measured. Asking for the whole
            /// box gives 1.00× on both. It also reproduces, to within a rounding error, the size the code this
            /// replaced had arrived at for documents by hand — `screenWidth × screenWidth · 1.5`, 7.8 MB against 7.8 MB
            /// — and its comment says why it got there: a square request *"meant a portrait A4 came back around
            /// 141×200 pt and was then drawn at roughly screen width: a two-to-three-times upscale, which is why PDFs
            /// looked soft."*
            ///
            /// ImageIO is the exception, because `kCGImageSourceThumbnailMaxPixelSize` is a single scalar on the long
            /// edge rather than a box — so a shape is genuinely needed. For a photograph it is known from the header at
            /// no cost, and a ratio is assumed only when that header could not be read, where it matches the 16:9 box
            /// `ImageView.placeholderView` reserves. That case over-asks slightly and can never undersize, which is
            /// the safe direction.
            ///
            /// Getting this wrong is invisible in a memory log — every number stays correct and the picture is merely
            /// soft — which is why both faults were found by comparing the size asked for against the size drawn.
            var assumedAspectRatio: CGFloat? {
                switch self {
                case .photo: return PreviewImageStore.assumedAspectRatio
                case .video, .document: return nil
                }
            }
        }

        /// The shape of the file, when it is known from its header. Nil for anything that has to be rendered before
        /// its proportions can be read.
        var aspectRatio: CGFloat? {
            guard let sourcePixelSize, sourcePixelSize.width > 0, sourcePixelSize.height > 0 else { return nil }
            return sourcePixelSize.width / sourcePixelSize.height
        }

        /// The shape to size the request against: the file's own if it is known, else whatever this kind is drawn in.
        var shapeToSizeAgainst: CGFloat? {
            aspectRatio ?? kind.assumedAspectRatio
        }

    }


    // MARK: - State

    /// The pictures held. **The only strong reference to any preview in this process.**
    private var pictures = [URL: CGImage]()

    /// The pixels each held picture was asked for, so a change of geometry can discard **only** what actually needs
    /// building again. Forgetting everything on any change was too blunt: it turned a wobbling measurement into a
    /// decode of the whole window, once per wobble.
    private var askedFor = [URL: CGSize]()

    /// The window last acted on, so being told the same thing twice costs nothing and cannot start anything.
    private var lastWindow: [URL]?

    /// What the window was last derived from, so the store can work it out again on its own when something other than
    /// the reader's position changes — see ``pictureIsCovered(_:forPageWith:)``.
    private var centre: Int?
    private var pages: [Page?] = []

    /// Pages whose picture is hidden behind something opaque, and so must not be held.
    ///
    /// Today that is one thing: a film that is playing. `VideoPlayer` covers the poster frame completely, so holding it
    /// is waste at exactly the moment memory is tightest — an `AVPlayer`'s own decode buffers were measured taking the
    /// footprint from 45.5 to **95.7 MB**, one megabyte from the warning threshold, with nothing of ours running.
    ///
    /// Expressed as *not wanted* rather than as a separate rule, so it costs no new machinery: a covered page leaves
    /// the window, which gives its bytes back through the ordinary eviction and stops it being decoded; uncovering puts
    /// it back and it is rebuilt like anything else.
    private var covered = Set<URL>()

    /// What ought to be held, in the order it ought to be decoded: the centre first, then the page after it, then the
    /// page before. A swipe forward is the common case, so it is served first.
    private var wanted = [Page]()

    /// Pages whose decode returned nothing, so the worker does not ask again for ever.
    private var failed = Set<URL>()

    /// The single decode. `nil` when nothing is being built.
    private var worker: Task<Void, Never>?

    /// Which worker the one above is, so a worker that finishes late cannot un-register a newer one.
    ///
    /// Without it there is a hole straight through the guarantee this type exists for: ``reset`` clears `worker`, a new
    /// window starts a second worker, and then the *first* worker's last line sets `worker = nil` — whereupon the guard
    /// in ``decodeWhatIsMissing`` sees nothing running and starts a third. Two decodes at once, which is the state
    /// measured at 96 MB.
    private var workerGeneration = 0

    /// The box a page is drawn in, and the scale it is drawn at. Both are properties of the screen rather than of a
    /// page — `containerRelativeFrame(.horizontal, count: 1)` gives every page the same box — so they are learnt once
    /// and every page is then sized by identical arithmetic, the centre and its neighbours alike.
    private var pageBox: CGSize = .zero
    private var displayScale: CGFloat = 1


    // MARK: - Reading

    /// The picture for this page, or nil while there is none.
    ///
    /// Read straight from `body`. The view holds no copy and no seed, so it cannot be showing something this store has
    /// let go of — which is the failure this design exists to make impossible.
    func picture(for url: URL) -> CGImage? {
        pictures[url]
    }


    /// Whether this page was tried and could not be rendered, so a view can show the error glyph rather than waiting
    /// for ever on a picture that is never coming.
    func failedToBuildAPicture(for url: URL) -> Bool {
        failed.contains(url)
    }


    // MARK: - Driving the window

    /// Says where the reader is, and lets the store put that right.
    ///
    /// **Evicts first, then decodes**, and that order is the point rather than an implementation detail: a picture
    /// leaving the window gives its bytes back *before* the picture arriving asks for its own. The old cache could not
    /// do this — `NSCache` evicts only as a consequence of an insert, so the new bitmap always existed alongside the
    /// old one.
    ///
    /// `pages` is index-aligned with the pager and carries nil where a page has nothing to preview (a link card, an
    /// audio file, an item still loading), so an index means the same thing here as it does on screen.
    func readerIsLookingAt(index: Int, pages: [Page?], pageBox: CGSize, displayScale: CGFloat, because trigger: String = "") {

        guard pageBox.width > 0, pageBox.height > 0 else { return }

        self.pageBox = pageBox
        self.displayScale = displayScale
        self.centre = index
        self.pages = pages

        recomputeTheWindow(because: trigger)

    }


    /// Says that a page's picture has become hidden, or visible again.
    ///
    /// The store works the window out again from what it already knows, so a view reporting coverage needs no geometry
    /// and no index — see ``covered``.
    func pictureIsCovered(_ isCovered: Bool, forPageWith url: URL) {
        let changed = isCovered ? covered.insert(url).inserted : covered.remove(url) != nil
        guard changed else { return }
        recomputeTheWindow(because: isCovered ? "covered" : "uncovered")
    }


    /// Decides what ought to be held, gives back everything else, and asks for what is missing — in that order.
    private func recomputeTheWindow(because trigger: String) {

        guard pageBox.width > 0, pageBox.height > 0, let centre else { return }

        wanted = Self.windowOfIndices(centeredOn: centre, count: pages.count)
            .compactMap { pages[$0] }
            .filter { !covered.contains($0.url) }
        let window = wanted.map(\.url)

        // **Being told the same thing twice does nothing.** Five call sites drive this and several of them fire on
        // every re-render, so the common case by far is a repeat — and a repeat that evicted and re-decoded would make
        // the store's own `objectWillChange` a cause of more work, which is a loop looking for a reason to start.
        guard window != lastWindow else { return }
        Self.logger.notice("📤🧠 window \(trigger, privacy: .public) centre=\(centre, privacy: .public) box=\(Int(self.pageBox.width), privacy: .public)x\(Int(self.pageBox.height), privacy: .public)pt covered=\(self.covered.count, privacy: .public) [\(window.map(\.lastPathComponent).joined(separator: " "), privacy: .public)] \(self.residentDescription(), privacy: .public) \(PreviewMemory.description(), privacy: .public)")
        lastWindow = window

        // Step one: give back what is no longer wanted, and anything whose size is no longer right — now,
        // synchronously, before a single byte is asked for.
        let keep = Set(window).filter { url in
            guard let held = askedFor[url], let page = wanted.first(where: { $0.url == url }) else { return false }
            return held == request(for: page)
        }
        forget(everythingExcept: keep)

        // Step two: and only now ask for what is missing.
        decodeWhatIsMissing()

    }


    /// The indices the window covers: the reader's page, then the one after, then the one before.
    ///
    /// Returned in decode order rather than in screen order, so the priority is carried by the list itself and the
    /// worker needs no notion of importance.
    static func windowOfIndices(centeredOn index: Int, count: Int) -> [Int] {
        guard count > 0, index >= 0, index < count else { return [] }
        return [index, index + 1, index - 1]
            .filter { $0 >= 0 && $0 < count }
            .prefix(sizeOfTheWindow)
            .map { $0 }
    }


    /// Gives up everything the reader has moved away from.
    ///
    /// Whether a picture is *held* and whether it is *wanted* are kept apart deliberately: a decode that finishes after
    /// its page has left the window is dropped rather than stored, so a fast swipe cannot accumulate.
    private func forget(everythingExcept keep: Set<URL>) {
        let leaving = pictures.keys.filter { !keep.contains($0) }
        guard !leaving.isEmpty else { return }
        for url in leaving {
            let bytes = pictures[url].map { UInt64($0.bytesPerRow * $0.height) } ?? 0
            pictures.removeValue(forKey: url)
            askedFor.removeValue(forKey: url)
            Self.logger.notice("📤🧠 evict          \(url.lastPathComponent, privacy: .public) bytes=\(PreviewMemory.megabytes(bytes), privacy: .public) \(self.residentDescription(), privacy: .public) \(PreviewMemory.description(), privacy: .public)")
        }
        objectWillChange.send()
    }


    /// Starts the reader again from nothing.
    ///
    /// **The share extension's process is reused between shares** — measured: a second share four minutes later ran in
    /// the same pid, and its baseline was 18.2 MB against 8.8 MB for the first. A `static let shared` therefore outlives
    /// the share that filled it, and without this the pictures of the previous share would be counted against the
    /// budget of the next one.
    public func reset() {
        worker?.cancel()
        worker = nil
        wanted = []
        failed = []
        askedFor = [:]
        lastWindow = nil
        centre = nil
        pages = []
        covered = []
        pageBox = .zero
        displayScale = 1
        forget(everythingExcept: [])
        Self.logger.notice("📤🧠 reset          \(PreviewMemory.description(), privacy: .public)")
    }


    /// Gives back everything but the page being looked at.
    ///
    /// The last resort, for a memory warning. It costs the two neighbours a re-decode, which is a placeholder for a
    /// moment. Worth knowing what the measurements say about this: at 96 MB the warning fires and there are still
    /// 24 MB left, so it arrives in time to matter — but it arrived on *every* page interaction under the old design,
    /// which is why nothing here relies on it.
    public func dropEverythingButTheCentre() {
        guard let centre = wanted.first else { return }
        Self.logger.notice("📤🧠 pressure       keeping only \(centre.url.lastPathComponent, privacy: .public) \(PreviewMemory.description(), privacy: .public)")
        forget(everythingExcept: [centre.url])
    }


    /// What is held, for a log line.
    func residentDescription() -> String {
        let total = pictures.values.reduce(UInt64(0)) { $0 + UInt64($1.bytesPerRow * $1.height) }
        let names = pictures.keys.map(\.lastPathComponent).sorted().joined(separator: " ")
        return "resident=\(pictures.count) residentBytes=\(PreviewMemory.megabytes(total)) [\(names)]"
    }


    // MARK: - Decoding, one at a time

    /// Builds whatever the window is missing, **one picture at a time**.
    ///
    /// The serialisation is the single most important line in this file. Measured on an iPhone 13: one decode in flight
    /// peaked at 68–76 MB, two at 96, three at over 120 and death. Every crash in three recorded runs would have been
    /// prevented by this alone, before any of the right-sizing below.
    ///
    /// The guard is what enforces it. A second caller finds a worker already running and simply returns: the queue is
    /// ``wanted`` itself, so there is nothing to enqueue and no ordering to maintain — whatever the window says when
    /// the current decode finishes is what gets built next, which is also exactly the right answer after a swipe.
    private func decodeWhatIsMissing() {
        guard worker == nil else { return }
        guard nextPageToDecode() != nil else { return }
        workerGeneration += 1
        let generation = workerGeneration
        worker = Task { [weak self] in
            // The cancellation check is in the condition, not only inside the decode: cancelling a task does not break
            // a `while`, so without it a cancelled worker would go on asking for pages and each decode would return
            // nil at its own cancellation check for ever.
            while !Task.isCancelled, let page = self?.nextPageToDecode() {
                await self?.decode(page)
            }
            self?.workerHasFinished(generation)
        }
    }


    /// Un-registers the worker, but only if it is still the current one.
    private func workerHasFinished(_ generation: Int) {
        guard generation == workerGeneration else { return }
        worker = nil
    }


    /// The most wanted page that is not held and has not already failed.
    private func nextPageToDecode() -> Page? {
        wanted.first { pictures[$0.url] == nil && !failed.contains($0.url) }
    }


    /// Whether a page is one the reader may still be shown, which is what decides if a finished decode is kept.
    private func isWanted(_ page: Page) -> Bool {
        wanted.contains { $0.url == page.url }
    }


    /// Builds one picture and keeps it **only if it is still wanted**.
    ///
    /// The old code cached before checking, on the reasoning that a decode already paid for should not be thrown away.
    /// That reasoning is what let a fast swipe accumulate: the bitmap is indeed already paid for, but *keeping* it is
    /// what breaks the bound. The waste is logged (`stillWanted=false`) so it can be judged rather than assumed.
    private func decode(_ page: Page) async {

        let ask = request(for: page)

        _ = DecodesInFlight.shared.began(String(describing: page.kind),
                                         url: page.url,
                                         boxInPoints: Self.fittedSize(aspectRatio: page.shapeToSizeAgainst, in: pageBox),
                                         displayScale: displayScale,
                                         sourcePixelSize: page.sourcePixelSize,
                                         aspectRatio: page.aspectRatio,
                                         pixelSize: ask,
                                         maxPixelSize: Int(max(ask.width, ask.height).rounded()))

        let picture = await Self.picture(of: page, atMost: ask)
        let stillWanted = isWanted(page)

        DecodesInFlight.shared.ended(String(describing: page.kind),
                                     url: page.url,
                                     actualPixelSize: picture.map { .init(width: $0.width, height: $0.height) },
                                     actualBytes: picture.map { UInt64($0.bytesPerRow * $0.height) },
                                     stillWanted: stillWanted)

        guard let picture else {
            failed.insert(page.url)
            return
        }
        guard stillWanted else { return }

        pictures[page.url] = picture
        askedFor[page.url] = ask
        Self.logger.notice("📤🧠 hold           \(page.url.lastPathComponent, privacy: .public) bytes=\(PreviewMemory.megabytes(UInt64(picture.bytesPerRow * picture.height)), privacy: .public) \(self.residentDescription(), privacy: .public) \(PreviewMemory.description(), privacy: .public)")
        objectWillChange.send()

    }


    // MARK: - How big to ask for

    /// The pixels to ask for, for one page: what it is drawn at, and never more than ``bytesPerPreview``.
    private func request(for page: Page) -> CGSize {
        let fitted = Self.fittedSize(aspectRatio: page.shapeToSizeAgainst, in: pageBox)
        let inPixels = CGSize(width: fitted.width * displayScale, height: fitted.height * displayScale)
        return Self.capped(inPixels, toAtMost: Self.bytesPerPreview)
    }


    /// The box a picture of this shape occupies when drawn `.fit` inside `box` — the same arithmetic SwiftUI applies,
    /// so the answer is the size actually drawn rather than an estimate of it.
    ///
    /// **This is where the share extension departs from the discussion screen deliberately.** There, a tile names a
    /// fixed point size and the data source collapses it to `Int(max(w, h))`, which is blind to the picture's shape —
    /// hence the document path having to over-ask 400pt for a 280pt box, and a panorama coming back short. Here the
    /// shape is already known from the file's header at no cost, and the box is aspect-fitted, so the long edge asked
    /// for is exactly the long edge drawn: nothing is over-served and nothing is upscaled.
    ///
    /// A nil ratio means **the whole box**, which is the honest answer for something whose renderer preserves the
    /// file's own proportions and fits it inside whatever it is given — see ``Page/Kind/assumedAspectRatio``. Callers
    /// pass ``Page/shapeToSizeAgainst`` rather than deciding this themselves.
    ///
    /// The unknown case is the one the old code got worst: with no `pixelSize` it applied its cap as a *square*, so the
    /// file it knew least about cost the most — 16 MB against the 2.5 MB it is drawn at.
    static func fittedSize(aspectRatio: CGFloat?, in box: CGSize) -> CGSize {
        guard box.width > 0, box.height > 0 else { return .zero }
        guard let aspectRatio, aspectRatio > 0 else { return box }
        let boxRatio = box.width / box.height
        if aspectRatio >= boxRatio {
            return CGSize(width: box.width, height: (box.width / aspectRatio).rounded())
        } else {
            return CGSize(width: (box.height * aspectRatio).rounded(), height: box.height)
        }
    }


    /// The same size, scaled down until its bitmap fits within `bytes`, and returned untouched when it already does.
    ///
    /// Both edges are scaled by the square root of the excess, so the shape is preserved: a picture is never squashed
    /// to fit a budget, only made slightly softer.
    static func capped(_ pixelSize: CGSize, toAtMost bytes: Int) -> CGSize {
        let weight = Double(pixelSize.width) * Double(pixelSize.height) * 4
        guard weight > Double(bytes), weight > 0 else { return pixelSize }
        let factor = (Double(bytes) / weight).squareRoot()
        return CGSize(width: (pixelSize.width * factor).rounded(),
                      height: (pixelSize.height * factor).rounded())
    }


    // MARK: - The three things that can make a picture

    /// Dispatches to whichever framework can render this kind of file.
    ///
    /// `nonisolated` **and** `async`, so the work runs on the cooperative pool rather than on the main actor while
    /// still belonging to the calling task tree — so a cancelled store cancels its decode. A detached task would not.
    nonisolated private static func picture(of page: Page, atMost pixelSize: CGSize) async -> CGImage? {
        switch page.kind {
        case .photo: return await photograph(at: page.url, maxPixelSize: Int(max(pixelSize.width, pixelSize.height).rounded()))
        case .video: return await posterFrame(at: page.url, atMost: pixelSize)
        case .document: return await document(at: page.url, atMost: pixelSize)
        }
    }


    /// Decodes a photograph straight to the size asked for, so the full-resolution bitmap never exists.
    ///
    /// `kCGImageSourceShouldCacheImmediately` makes the pixels resident here, off the main thread, rather than lazily
    /// on the first frame that draws them — which is what keeps a swipe smooth, and what makes the cost honest at the
    /// moment it is reported.
    nonisolated private static func photograph(at url: URL, maxPixelSize: Int) async -> CGImage? {
        // The decode cannot be interrupted once begun, so the only useful place to notice cancellation is before it.
        guard !Task.isCancelled else { return nil }
        guard maxPixelSize > 0 else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // bake in the EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }


    /// A frame of a film, at the size it will be drawn.
    ///
    /// `AVAssetImageGenerator.maximumSize` is in **pixels** and preserves the aspect ratio, so the box computed above
    /// can be handed over as it is. It used to be a flat 2048×2048 — up to 16 MB for a picture drawn at 3 — and, worse,
    /// the result was held in a `@State` with no release and counted by nothing.
    nonisolated private static func posterFrame(at url: URL, atMost pixelSize: CGSize) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = pixelSize
        return try? await generator.image(at: .zero).image
    }


    /// Whatever QuickLook can make of the file: a page of a document, a rendering of anything the system can open.
    ///
    /// Asked for in pixels, by requesting points at a scale of one — QuickLook takes both, and everything in this
    /// store deals in pixels. `.thumbnail` rather than `.icon`, so it is a picture of the contents and not the generic
    /// badge of a file type.
    nonisolated private static func document(at url: URL, atMost pixelSize: CGSize) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: pixelSize,
                                                   scale: 1,
                                                   representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return representation.cgImage
    }

}
