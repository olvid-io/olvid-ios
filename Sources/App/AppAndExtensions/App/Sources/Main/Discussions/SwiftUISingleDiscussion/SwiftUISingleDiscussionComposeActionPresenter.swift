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
import OSLog
import AVFoundation
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import VisionKit
import ObvAppCoreConstants
import ObvComposition
import ObvDesignSystem
import ObvSettings
import ObvUI
import ObvUICoreData


/// Presents what the composition bar's `+` menu asks for, and answers whatever it presents.
///
/// **A type of its own, and an `NSObject`**, for the reasons ``SwiftUISingleDiscussionAttachmentPresenter`` and
/// ``SwiftUISingleDiscussionMessagePresenter`` are: every one of these actions is a *conversation with a view controller*, each
/// with a UIKit delegate of its own to answer — a photo picker, a document scanner, a camera, a file browser — and several of
/// those delegates want an `NSObject`. Answering them from ``SwiftUISingleDiscussionComposeActions`` would make the object that
/// implements a SwiftUI protocol also the object UIKit calls back, which is what those two types exist to avoid.
///
/// Everything the `+` menu offers goes through here, and so do the two other places that show something: the emoji button, and tapping
/// a file already attached to the draft.
@MainActor
final class SwiftUISingleDiscussionComposeActionPresenter: NSObject {

    /// Which draft everything picked is added to. A plain value, the draft of a screen never changing while the screen is up.
    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>

    /// Weak, as everywhere on this screen: the SwiftUI view tree holds the actions strongly, and the actions hold this.
    weak var viewController: (any SomeSingleDiscussionViewController)?

    /// The flow controller, which is what turns item providers into attachments on the draft.
    weak var delegate: (any SingleDiscussionViewControllerDelegate)?

    /// The composition bar's own state — weak for the same reason, the bar's view tree ultimately holding this object.
    ///
    /// Two things are said through it, both of which the legacy screen says to its hosting controller instead: that the bar is
    /// not to be edited while something is being loaded, and what of the picked content turned out to be *text* rather than an
    /// attachment. A screen that owns its shared state has no controller to be called on — see Step 19b, item 13.
    weak var composeViewSharedState: ComposeView.SharedState?

    /// The load of item providers whose progress the composition bar is currently showing, or nil when it is showing none.
    ///
    /// **This is what makes a late progress report harmless**, and it is here rather than at the producer because the producer cannot fix
    /// it: `postOnDispatchQueue()` makes a fresh `DispatchQueue` for every post, so two notifications are two independent async hops with
    /// nothing sequencing them. Written and read only on the main actor, which the observer's block is delivered on — so the moment
    /// ``handsOver(_:source:)`` clears this, anything still queued behind it stands down.
    fileprivate var theLoadWhoseProgressTheBarIsShowing: UUID?

    /// Names the files this screen writes into the temporary directory, so that a scan or a photograph reaches the draft with a
    /// readable name rather than the one the system gives it. Copied from the legacy screen, including the fixed locale, so that the
    /// two screens name a file the same way.
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return df
    }()

    /// Shows a file already attached to the draft, and stays alive for as long as it is on screen.
    private var filesViewer: FilesViewer?

    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.draftObjectID = draftObjectID
        super.init()
    }


    /// A file dropped onto this discussion from another device, which the flow controller hands over once this screen is on top of the stack.
    ///
    /// **It is the same path as the file browser's**, which is the whole of why this is one line: legacy writes it out again in
    /// `NewSingleDiscussionViewController.addAttachmentFromAirDropFile(at:)`, with its own `Task` and its own bracket around
    /// `isDiscussionViewPreventingEdition`, and gets the same answer. A file is a file however it arrived.
    ///
    /// One at a time because that is how it is asked for: the flow controller loops over the URLs it has and says each of them separately.
    func aFileArrivedFromAnotherDevice(at url: URL) {
        Task { await addsToTheDraft([url]) }
    }


    /// Closes the bar to editing, adds the files to the draft, and opens the bar again however it ends.
    ///
    /// Every path in this file that produces a file on disk ends here: the file browser, the scanner, the camera, a finished
    /// recording, and a file arriving by AirDrop. Copying a large video out of the system's own storage takes a perceptible while, and a draft being written to
    /// underneath a reader who is typing is what that flag exists to prevent.
    private func addsToTheDraft(_ urls: [URL]) async {
        guard let viewController, let delegate else { assertionFailure(); return }
        composeViewSharedState?.setIsDiscussionViewPreventingEdition(true)
        defer { composeViewSharedState?.setIsDiscussionViewPreventingEdition(false) }
        do {
            try await delegate.userWantsToAddAttachmentsToDraftFromURLs(viewController, draftObjectID: draftObjectID, urls: urls)
        } catch {
            Self.logger.fault("Could not add the files to the draft: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
        }
    }


    /// Shows the photo library, as the legacy screen's `.chooseImageFromLibrary` does.
    ///
    /// `selectionLimit = 0` means *no limit*, which is legacy's configuration, and the whole selection is handed over in one
    /// call so that one draft update covers all of it. Presented with `presentOnTop(_:animated:)`, again as legacy does: a
    /// sheet may already be up over this screen — a message's *Info*, the reactions — and a picker presented from the screen
    /// itself would never appear.
    ///
    /// Nothing happens on a device with no library to offer, silently: legacy returns without a word, and there is no failure
    /// to report to a reader who has just been told there is nothing to pick from.
    func showThePhotoLibrary() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
        guard let viewController else { assertionFailure(); return }
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 0
        // The file as the library stores it. `.automatic` re-encoded an iPhone's HEVC clips before handing them over, 57 s for three,
        // where `.current` took 0.2 s; the smaller sizes are made from the original.
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        viewController.presentOnTop(picker, animated: true)
    }


    // MARK: Choosing a file

    /// Shows the system's file browser, as the legacy screen's `.choseFile` does: the same content types, and several files at a time.
    func showsTheFileBrowser() {
        guard let viewController else { assertionFailure(); return }
        // The list legacy uses. `.item` alone would probably do, but the more precise types are kept so that the browser opens on the
        // same tab it opens on today.
        let documentTypes: [UTType] = [.image, .movie, .pdf, .data, .item]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: documentTypes, asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        viewController.presentOnTop(documentPicker, animated: true)
    }


    // MARK: Scanning a document

    /// Shows the document scanner, if this device has a camera and supports scanning.
    ///
    /// Asks for permission when it has not been asked before, and says nothing when permission has been refused: a notification is
    /// posted instead, and the app answers it. That is how the legacy screen behaves, and it is the app's decision rather than this
    /// screen's.
    func showsTheDocumentScanner() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera), VNDocumentCameraViewController.isSupported else { return }
        withPermissionToUseTheCamera { [weak self] in
            guard let self, let viewController = self.viewController else { return }
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = self
            viewController.presentOnTop(scanner, animated: true)
        }
    }


    // MARK: Taking a photograph or a film

    /// Shows the camera, on a real device only. A simulator has none, and the legacy screen returns without a word there too.
    func showsTheCamera() {
        guard ObvMessengerConstants.isRunningOnRealDevice else { return }
        withPermissionToUseTheCamera { [weak self] in
            guard let self, let viewController = self.viewController else { return }
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .camera
            imagePicker.mediaTypes = [UTType.image, UTType.movie].map(\.identifier)
            imagePicker.videoQuality = .typeHigh
            imagePicker.allowsEditing = false
            imagePicker.delegate = self
            viewController.presentOnTop(imagePicker, animated: true)
        }
    }


    /// Runs the given work once the camera may be used, asking for permission if it has not been asked before.
    ///
    /// When permission has been refused there is nothing to show and nothing to say here: a notification is posted, and the app
    /// decides what the reader is told. Copied from the legacy screen, which does the same for the scanner and for the camera.
    private func withPermissionToUseTheCamera(_ work: @escaping @MainActor () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            work()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                Task { @MainActor in work() }
            }
        case .denied, .restricted:
            let notification = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
            NotificationCenter.default.post(name: notification.name, object: nil)
        @unknown default:
            assertionFailure("A new AVCaptureDevice.authorizationStatus is not handled")
        }
    }


    // MARK: How long this message will last

    /// Shows the sheet that decides how long the message being written will last once it is read.
    func showsHowLongThisMessageWillLast() {
        guard let viewController else { assertionFailure(); return }
        guard let draft = try? PersistedDraft.get(objectID: draftObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        guard let vc = DraftSettingsHostingViewController(draft: draft, delegate: self) else { assertionFailure(); return }
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.delegate = vc
            sheet.preferredCornerRadius = 30.0
        }
        viewController.presentOnTop(vc, animated: true)
    }


    // MARK: The settings of the composition bar

    /// Shows the settings of the bar itself: which actions its `+` menu offers, and in which order.
    ///
    /// Inside a navigation controller because the sheet needs a place for its *Done* button, which is what closes it.
    func showsTheSettingsOfTheComposeBar() {
        guard let viewController else { assertionFailure(); return }
        guard let draft = try? PersistedDraft.get(objectID: draftObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        let vc = ComposeMessageViewSettingsViewController(input: .local(configuration: draft.discussion.localConfiguration), actions: self)
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem.forClosing(target: self, action: #selector(closesTheSheetOnTop))
        let nav = ObvNavigationController(rootViewController: vc)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 30.0
        }
        viewController.presentOnTop(nav, animated: true)
    }


    @objc private func closesTheSheetOnTop() {
        viewController?.presentedViewController?.dismiss(animated: true)
    }


    // MARK: The emoji sent by the button beside the bar

    /// Shows the picker that chooses which single emoji the button beside the bar sends.
    ///
    /// The choice is a setting of this discussion, so it is announced rather than returned: the bar reads it back through its own data
    /// source, as the legacy screen does.
    func showsTheEmojiPickerForTheDefaultEmoji() {
        guard let viewController else { assertionFailure(); return }
        guard let draft = try? PersistedDraft.get(objectID: draftObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        let localConfiguration = draft.discussion.localConfiguration
        let model = EmojiPickerViewModel(selectedEmoji: localConfiguration.defaultEmoji) { emoji in
            ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(
                value: .defaultEmoji(emoji),
                localConfigurationObjectID: localConfiguration.typedObjectID)
            .postOnDispatchQueue()
        }
        let vc = EmojiPickerHostingViewController(model: model)
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 30.0
        }
        viewController.presentOnTop(vc, animated: true)
    }


    // MARK: Pasting from the menu

    /// Adds whatever is on the pasteboard to the draft, which is the `+` menu's own paste entry.
    ///
    /// This is not the same thing as pasting into the text field, which the bar handles itself. Both end at the same operation, and
    /// that operation decides what becomes an attachment and what is written as text.
    ///
    /// **An empty pasteboard is worth a word to the reader**, because they have just asked for something to happen. A pasteboard
    /// holding one string of nothing but spaces counts as empty, which the legacy screen checks for by hand and so does this.
    func pastesWhateverIsOnThePasteboard() {

        let itemProviders = UIPasteboard.general.itemProviders

        let thereIsNothingToPaste: Bool
        if itemProviders.isEmpty {
            thereIsNothingToPaste = true
        } else if itemProviders.count == 1, let string = UIPasteboard.general.string, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            thereIsNothingToPaste = true
        } else {
            thereIsNothingToPaste = false
        }

        guard !thereIsNothingToPaste else {
            Toaster.showToast(toast: .init(style: .warning, message: NewSingleDiscussionViewController.Strings.nothingToPaste))
            return
        }

        Task { await handsOver(itemProviders) }

    }


    // MARK: Looking at a file already attached to the draft

    /// Shows the file at the given place among those already attached to the draft.
    func showsTheFileOfTheDraft(at index: Int) throws {
        guard let viewController else { assertionFailure(); return }
        let frc = PersistedDraftFyleJoin.getFetchedResultsControllerForAllDraftFyleJoinsOfDraft(withObjectID: draftObjectID, within: ObvStack.shared.viewContext)
        try frc.performFetch()
        filesViewer = FilesViewer(frc: frc, qlPreviewControllerDelegate: self)
        filesViewer?.tryToShowFile(atIndexPath: IndexPath(item: index, section: 0), within: viewController)
    }

}


// MARK: - Implementing PHPickerViewControllerDelegate

extension SwiftUISingleDiscussionComposeActionPresenter: PHPickerViewControllerDelegate {

    /// What the reader picked, on its way to the draft.
    ///
    /// **The bar is closed to editing for as long as this takes**, and re-opened however it ends — a large video takes a
    /// perceptible while to be copied out of the library, and a draft being written to underneath a reader who is typing is
    /// what that flag exists to prevent. The legacy screen sets the same flag on its hosting controller.
    ///
    /// **Dismissed first, then loaded**, which is legacy's order and not merely a tidy one: the loading is what takes the time,
    /// and doing it behind a picker that is still on screen leaves the reader looking at a picker that no longer responds.
    ///
    /// Whatever the operation decides was *text* rather than an attachment comes back here and is written into the bar — a
    /// picked item can be both, and it is the operation that knows. See ``TextToPasteIntoTheDraft``.
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {

        composeViewSharedState?.setIsDiscussionViewPreventingEdition(true)

        picker.dismiss(animated: true) { [weak self] in

            guard let self else { return }

            // Nothing picked: the reader cancelled, and the bar goes back to being editable with nothing else done.
            guard !results.isEmpty else {
                self.composeViewSharedState?.setIsDiscussionViewPreventingEdition(false)
                return
            }

            let itemProviders = results.map({ $0.itemProvider })

            Task { await self.handsOver(itemProviders, source: .photoPicker) }
        }

    }

}


// MARK: - Handing item providers over

extension SwiftUISingleDiscussionComposeActionPresenter {

    /// Hands item providers to the operation that decides what becomes an attachment and what is written into the text, and writes
    /// back whatever it decided was text.
    ///
    /// A picked item can be both. A pasted link, for example, is attached as a preview *and* leaves its address where the reader was
    /// typing. Only that operation knows, which is why it answers rather than simply acting.
    ///
    /// The bar is closed to editing throughout, and opened again however this ends.
    func handsOver(_ itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource = .paste) async {

        guard !itemProviders.isEmpty else { return }
        guard let viewController, let delegate else { assertionFailure(); return }

        composeViewSharedState?.setIsDiscussionViewPreventingEdition(true)
        defer { composeViewSharedState?.setIsDiscussionViewPreventingEdition(false) }

        // The loading progress arrives as a notification, observed for the length of this call only. Each post is delivered on a fresh
        // `DispatchQueue`, so posts are not ordered: `thisLoad` lets a late report from a load that has ended stand down rather than
        // repaint the bar. This class is `@MainActor` and the block runs on `.main`, so once the `defer` has cleared it, nothing repaints.
        let thisLoad = UUID()
        theLoadWhoseProgressTheBarIsShowing = thisLoad

        let token = ObvMessengerInternalNotification.observeDraftAttachmentsLoadingProgressDidChange(queue: .main) { [weak self] objectID, fractionCompleted in
            guard let self, objectID == self.draftObjectID else { return }
            guard self.theLoadWhoseProgressTheBarIsShowing == thisLoad else { return }
            self.composeViewSharedState?.setAttachmentsLoadingFractionCompleted(fractionCompleted)
        }
        defer {
            theLoadWhoseProgressTheBarIsShowing = nil
            NotificationCenter.default.removeObserver(token)
            composeViewSharedState?.setAttachmentsLoadingFractionCompleted(nil)
        }

        do {
            let textsToPaste = try await delegate.userWantsToAddAttachmentsToDraft(
                viewController,
                draftObjectID: draftObjectID,
                itemProviders: itemProviders,
                source: source)
            for textToPaste in textsToPaste {
                composeViewSharedState?.pasteTextIntoTextEditor(AttributedString(textToPaste.textToPaste))
            }
        } catch {
            Self.logger.fault("Could not add the items to the draft: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
        }

    }

}


// MARK: - Implementing UIDocumentPickerDelegate

extension SwiftUISingleDiscussionComposeActionPresenter: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { await addsToTheDraft(urls) }
    }

}


// MARK: - Implementing VNDocumentCameraViewControllerDelegate

// **`@preconcurrency` because VisionKit never said where it calls this.** `UIDocumentPickerDelegate` above is declared `NS_SWIFT_UI_ACTOR` and needs nothing;
// `VNDocumentCameraViewControllerDelegate` carries no such annotation, so this `@MainActor` type conforming to it is a crossing as far as the compiler can see.
// It is called from a presented view controller, on the main thread, and this is what that pre-concurrency fact is spelled with — the arrangement two sibling
// presenters in this directory already use.
extension SwiftUISingleDiscussionComposeActionPresenter: @preconcurrency VNDocumentCameraViewControllerDelegate {

    /// Turns a finished scan into one PDF and attaches it to the draft.
    ///
    /// **Dismissed first, then written**, which is the legacy screen's order and matters: writing the pages takes a moment, and doing
    /// it behind a scanner that is still on screen leaves the reader looking at one that no longer answers.
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {

        composeViewSharedState?.setIsDiscussionViewPreventingEdition(true)

        controller.dismiss(animated: true) { [weak self] in

            guard let self else { return }

            guard scan.pageCount > 0 else {
                self.composeViewSharedState?.setIsDiscussionViewPreventingEdition(false)
                return
            }

            Task {
                defer { self.composeViewSharedState?.setIsDiscussionViewPreventingEdition(false) }

                let pdfDocument = PDFDocument()
                for pageNumber in 0..<scan.pageCount {
                    guard let pdfPage = PDFPage(image: scan.imageOfPage(at: pageNumber)) else { assertionFailure(); return }
                    pdfDocument.insert(pdfPage, at: pageNumber)
                }

                let name = "Scan @ \(self.dateFormatter.string(from: Date()))"
                let fileName = [name, UTType.pdf.preferredFilenameExtension ?? "pdf"].joined(separator: ".")
                let url = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(fileName)
                guard pdfDocument.write(to: url) else {
                    Self.logger.fault("Could not write the scan to a temporary file")
                    assertionFailure()
                    return
                }

                await self.addsToTheDraft([url])
            }
        }

    }


    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }


    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        Self.logger.fault("The document scanner failed: \(error.localizedDescription, privacy: .public)")
        controller.dismiss(animated: true)
    }

}


// MARK: - Implementing UIImagePickerControllerDelegate

extension SwiftUISingleDiscussionComposeActionPresenter: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    /// Attaches what the camera produced to the draft.
    ///
    /// **The file is always copied to a place of our own**, even when the camera hands over a URL. That is required for a film, and it
    /// is done for a photograph too, because the name the camera gives a file is not one worth showing to anybody.
    ///
    /// A photograph taken here often arrives as an image in memory rather than as a file, so both cases are handled.
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {

        composeViewSharedState?.setIsDiscussionViewPreventingEdition(true)

        picker.dismiss(animated: true) { [weak self] in

            guard let self else { return }

            Task {
                defer { self.composeViewSharedState?.setIsDiscussionViewPreventingEdition(false) }

                // Only photographs and films, as on the legacy screen.
                guard let chosenMediaType = info[.mediaType] as? String,
                      [UTType.image, .movie].map(\.identifier).contains(chosenMediaType) else { return }

                if let pickedURL = (info[.imageURL] as? URL) ?? (info[.mediaURL] as? URL) {
                    let name = "Media @ \(self.dateFormatter.string(from: Date()))"
                    let fileName = [name, pickedURL.pathExtension.lowercased()].joined(separator: ".")
                    let url = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(fileName)
                    do {
                        try FileManager.default.copyItem(at: pickedURL, to: url)
                    } catch {
                        Self.logger.fault("Could not copy the file the camera produced: \(error.localizedDescription, privacy: .public)")
                        assertionFailure()
                        return
                    }
                    await self.addsToTheDraft([url])
                } else if let image = info[.originalImage] as? UIImage {
                    let name = "Photo @ \(self.dateFormatter.string(from: Date()))"
                    let fileName = [name, UTType.jpeg.preferredFilenameExtension ?? "jpeg"].joined(separator: ".")
                    let url = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(fileName)
                    guard let data = image.jpegData(compressionQuality: 1.0) else { assertionFailure(); return }
                    do {
                        try data.write(to: url)
                    } catch {
                        Self.logger.fault("Could not write the photograph to a temporary file: \(error.localizedDescription, privacy: .public)")
                        assertionFailure()
                        return
                    }
                    await self.addsToTheDraft([url])
                } else {
                    assertionFailure("The camera returned neither a file nor an image")
                }
            }
        }

    }

}


// MARK: - Implementing DraftSettingsHostingViewControllerDelegate

extension SwiftUISingleDiscussionComposeActionPresenter: DraftSettingsHostingViewControllerDelegate {

    func userWantsToUpdateDraftExpiration(_ draftSettingsHostingViewController: DraftSettingsHostingViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToUpdateDraftExpiration(viewController, draftObjectID: draftObjectID, value: value)
    }

}


// MARK: - Implementing ComposeMessageViewSettingsViewControllerActions

extension SwiftUISingleDiscussionComposeActionPresenter: ComposeMessageViewSettingsViewControllerActions {

    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: ComposeMessageViewSettingsViewController, value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToUpdateDiscussionLocalConfiguration(viewController, value: value, localConfigurationObjectID: localConfigurationObjectID)
    }

}


// MARK: - Implementing FilesViewerPreviewDelegate

// **`@preconcurrency` for the same reason as the scanner above**, one protocol further down: `FilesViewerPreviewDelegate` is ours, but it refines
// `QLPreviewControllerDelegate`, which Apple leaves unannotated — so marking ours `@MainActor` would move the crossing rather than remove it. The sibling
// `SwiftUISingleDiscussionAttachmentPresenter` conforms the same way.
extension SwiftUISingleDiscussionComposeActionPresenter: @preconcurrency FilesViewerPreviewDelegate {

    /// Nothing to do. This says that a file of a *received message* has been looked at, which is what marks it as read. A file
    /// attached to a draft has never been received, so it has nothing to report.
    func previewController(hasDisplayed joinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {}

}


// MARK: - Errors and logging

extension SwiftUISingleDiscussionComposeActionPresenter {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SwiftUISingleDiscussionComposeActionPresenter.self))

}
