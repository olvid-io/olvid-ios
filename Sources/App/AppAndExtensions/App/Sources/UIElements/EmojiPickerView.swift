/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import UniformTypeIdentifiers
import Combine
import ObvUICoreData
import ObvUI
import OlvidUtils
import ObvSettings
import ObvAppTypes
import ObvEmojiUtils


final class EmojiPickerHostingViewController: KeyboardHostingController<EmojiPickerView>, EmojiPickerViewModelDelegate {

    fileprivate let model: EmojiPickerViewModel
    
    // MARK: Attributes - Private - Notifications
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    override var canBecomeFirstResponder: Bool { true }
    
    init(model: EmojiPickerViewModel) {
        self.model = model
        let view = EmojiPickerView(model: model)
        super.init(rootView: view)
        self.model.delegate = self
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // In case there is a navigation controller (which is the case under macOS), add a close button
        let closeAction = UIAction { [weak self] _ in self?.dismiss() }
        let closeButton = UIBarButtonItem(systemItem: .cancel, primaryAction: closeAction)
        navigationItem.rightBarButtonItem = closeButton
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForNotification()
        
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.backgroundColor = .clear
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismiss() {
        self.dismiss(animated: true)
    }

}

extension EmojiPickerHostingViewController {

    private func registerForNotification() {
        guard !isRegisteredToNotifications else { return }
        isRegisteredToNotifications = true
        
        observationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                OperationQueue.main.addOperation {
                    self?.dismiss()
                }
            },
        ])
    }
}

fileprivate protocol EmojiPickerViewModelDelegate: AnyObject {
    func dismiss()
}


final class EmojiPickerViewModel: ObservableObject {

    @Published var selectedEmoji: String?
    @ObservedObject var preferredEmojisList = ObvMessengerPreferredEmojisListObservable()
    let selectAction: (String?) -> Void
    private let feedbackGenerator = UIImpactFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    fileprivate weak var delegate: EmojiPickerViewModelDelegate?

    init(selectedEmoji: String?, selectAction: @escaping (String?) -> Void ) {
        self.selectedEmoji = selectedEmoji
        self.selectAction = selectAction
    }

    func haptic() {
        feedbackGenerator.impactOccurred()
    }

    fileprivate func selectAction_() {
        notificationGenerator.notificationOccurred(.success)
        selectAction(selectedEmoji)
        delegate?.dismiss()
    }
}

fileprivate struct Emoji: Identifiable {
    var defaultEmoji: String
    var id: String { defaultEmoji }

    var variants: [String] {
        EmojiList.variants[defaultEmoji] ?? []
    }
    var variantEmojis: [Emoji] {
        variants.map { Emoji(defaultEmoji: $0) }
    }
}


struct EmojiPickerView: View {

    @ObservedObject var model: EmojiPickerViewModel

    var body: some View {
        EmojiPickerInnerView(selectedEmoji: $model.selectedEmoji,
                             selectAction: model.selectAction_,
                             haptic: model.haptic,
                             preferredEmojiList: model.preferredEmojisList)
    }
}


fileprivate struct InnerEmojiView: View {
    let emoji: String
    let selectAction: () -> Void
    let hasVariants: Bool
    let isPreferredView: Bool
    let haptic: () -> Void
    let isNone: (String) -> Bool
    var fontSize: CGFloat = Self.defaultFontSize
    @Binding var selectedEmoji: String?
    @Binding var showVariantsView: String?
    @Binding var draggedEmoji: String?

    static let defaultFontSize: CGFloat = 33.0

    private var showBackground: Bool {
        guard let selectedEmoji = selectedEmoji else { return false }
        return emoji == selectedEmoji
    }

    private func tapGestureAction() {
        guard !isNone(emoji) else { return }
        if hasVariants {
            if EmojiList.allEmojis.contains(emoji) {
                showVariantsView = emoji
            } else {
                /// Not in allEmojis it should be a variant
                let representative = EmojiList.variants.first { (key, values) in
                    return values.contains(emoji)
                }
                showVariantsView = representative?.key
            }
        } else {
            withAnimation {
                if self.selectedEmoji == emoji {
                    self.selectedEmoji = nil
                } else {
                    self.selectedEmoji = emoji
                }
            }
            selectAction()
        }
    }

    var body: some View {
        Text(emoji)
            .font(.system(size: fontSize))
            .background(
                Circle()
                    .fill(.white)
                    .opacity(showBackground ? 0.5 : 0)
                    .scaleEffect(1.1), alignment: .center)
            .onTapGesture {
                tapGestureAction()
            }
            .if(!hasVariants && !isPreferredView) { view in
                view.onDrag({
                    if self.draggedEmoji != emoji {
                        haptic()
                    }
                    withAnimation {
                        self.draggedEmoji = emoji
                    }
                    return NSItemProvider(object: emoji as NSString)
                }, preview: {
                    Text(emoji)
                        .font(.system(size: fontSize * 1.5))
                })
            }
    }
}


fileprivate struct EmojiView: View {

    let emoji: Emoji
    let selectAction: () -> Void
    let haptic: () -> Void
    let isNone: (String) -> Bool

    @Binding var selectedEmoji: String?
    @Binding var showVariantsView: String?
    @Binding var draggedEmoji: String?

    /// The emoji to show in the view, we want to shows the variant this one is the current selection.
    private var emojiToShow: String {
        if let selectedEmoji = selectedEmoji, emoji.variants.contains(selectedEmoji) {
            return selectedEmoji
        } else {
            return emoji.defaultEmoji
        }
    }

    var body: some View {
        InnerEmojiView(emoji: emojiToShow,
                       selectAction: selectAction,
                       hasVariants: emoji.variants.count > 0,
                       isPreferredView: false,
                       haptic: haptic,
                       isNone: isNone,
                       selectedEmoji: $selectedEmoji,
                       showVariantsView: $showVariantsView,
                       draggedEmoji: $draggedEmoji)
            .background(PositionReader(tag: emoji.defaultEmoji))
    }
}


fileprivate struct VariantEmojiPickerView: View {

    let emojis: [String]
    let selectAction: () -> Void
    let haptic: () -> Void
    let isNone: (String) -> Bool
    @Binding var selectedEmoji: String?
    @Binding var draggedEmoji: String?

    @State private var leftTone: String = "🏻"
    @State private var rightTone: String = "🏻"

    static let tones: [String] = ["🏻", "🏼", "🏽", "🏾", "🏿"]
    static let widthColWithPicker: CGFloat = 4
    static let heightColWithPicker: CGFloat = 2.5
    static let maxEmoji: Int = 6

    var showPickers: Bool { emojis.count > Self.maxEmoji }

    var emojisToShow: [String] {
        if showPickers {
            /// Only show the default emoji, and a second one that can be configured by the two pickers.
            var result = [String]()
            if let first = emojis.first {
                result += [first]
            }
            guard let leftToneIndex = Self.tones.firstIndex(of: leftTone) else { return result }
            guard let rightToneIndex = Self.tones.firstIndex(of: rightTone) else { return result }

            /// Remark: the list is sorted by the python generator, we can rely on the position in the list.
            let index = leftToneIndex * Self.tones.count + rightToneIndex

            result += [emojis[index + 1]]

            return result
        } else {
            return emojis
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            if !showPickers {
                LazyHGrid(rows: [EmojiUtils.gridItem],
                          spacing: EmojiUtils.gridSpacing) {
                    ForEach(emojisToShow, id: \.self) { emoji in
                        InnerEmojiView(emoji: emoji,
                                       selectAction: selectAction,
                                       hasVariants: false,
                                       isPreferredView: false,
                                       haptic: haptic,
                                       isNone: isNone,
                                       fontSize: InnerEmojiView.defaultFontSize,
                                       selectedEmoji: $selectedEmoji,
                                       showVariantsView: .init(get: { nil }, set: { _ in }),
                                       draggedEmoji: $draggedEmoji)
                    }
                }
            } else {
                HStack(spacing: EmojiUtils.gridSpacing) {
                    ForEach(emojisToShow, id: \.self) { emoji in
                        InnerEmojiView(emoji: emoji,
                                       selectAction: selectAction,
                                       hasVariants: false,
                                       isPreferredView: false,
                                       haptic: haptic,
                                       isNone: isNone,
                                       fontSize: 45.0,
                                       selectedEmoji: $selectedEmoji,
                                       showVariantsView: .init(get: { nil }, set: { _ in }),
                                       draggedEmoji: $draggedEmoji)
                    }
                }
                HStack {
                    Spacer()
                    Picker("Left Tone", selection: $leftTone.animation()) {
                        ForEach(Self.tones, id: \.self) { tone in
                            Text(tone)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Right Tone", selection: $rightTone.animation()) {
                        ForEach(Self.tones, id: \.self) { tone in
                            Text(tone)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .onAppear {
                    /// Set the pickers' states with the current selection
                    if let selectedEmoji = selectedEmoji,
                       let index = emojis.firstIndex(of: selectedEmoji) {
                        let leftToneIndex: Int = (index - 1) / Self.tones.count
                        let rightToneIndex: Int = (index - 1) % Self.tones.count
                        guard leftToneIndex < Self.tones.count else { return }
                        guard rightToneIndex < Self.tones.count else { return }
                        leftTone = Self.tones[leftToneIndex]
                        rightTone = Self.tones[rightToneIndex]
                    }
                }
            }
        }
        .frame(width: showPickers ? Self.widthColWithPicker * EmojiUtils.gridColumnSize :
                CGFloat(emojis.count + 1) * EmojiUtils.gridColumnSize,
               height: showPickers ? Self.heightColWithPicker * EmojiUtils.gridColumnSize : EmojiUtils.gridColumnSize)
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 16.0)
                .foregroundColor(.gray)
        }

    }
}

extension String: @retroactive Identifiable {}
extension String: ReorderableItem {
    public var id: String { self }
}

extension EmojiGroup {

    /// This is used by the picker, to represent the group, the emoji with be grayscaled.
    var symbol: String {
        switch self {
        case .Smileys_Emotion: return "😀"
        case .People_Body: return "👋"
        case .Animals_Nature: return "🐶"
        case .Food_Drink: return "🥐"
        case .Travel_Places: return "🚘"
        case .Activities: return "⚽"
        case .Objects: return "💡"
        case .Symbols: return "♻️"
        case .Flags: return "🏳️"
        }
    }
}


struct EmojiUtils {

    static let gridItemSize: CGFloat = 36
    static let gridSpacing: CGFloat = 5
    static let gridColumnSize: CGFloat = gridItemSize + gridSpacing

    typealias ScrollCorrectionType = String?

    static let gridItem: GridItem = .init(.fixed(gridItemSize), spacing: gridSpacing)

    static func computeRowsCount(geometry: GeometryProxy) -> Int {
        let height = geometry.size.height
        return Int(height / Self.gridColumnSize)
    }

    fileprivate static var allEmojis: [Emoji] {
        EmojiList.allEmojis.map { Emoji(defaultEmoji: $0) }
    }

    static var none: String { "     " }
    static func isNone(_ s: String) -> Bool { s == none }

    static func scrollTo(geometry: GeometryProxy,
                         scrollViewProxy: ScrollViewProxy,
                         emoji: String,
                         detector: CurrentValueSubject<ScrollCorrectionType, Never>) {
        guard geometry.size.width > 0 else { return }
        /// Stop current scrolling correction
        detector.send(nil)
        /// Computes the number of columns
        let cols = (geometry.size.width / Self.gridColumnSize).rounded(.down)
        /// Compute the left and right padding needs to be centered
        let padding = (geometry.size.width - cols * Self.gridColumnSize) / 2
        /// UnitPoint takes a ratio betwen the parent and child position
        let x = padding / geometry.size.width
        withAnimation {
            scrollViewProxy.scrollTo(emoji, anchor: UnitPoint(x: x, y: 1))
        }
    }

    static func scrollTo(geometry: GeometryProxy,
                         scrollViewProxy: ScrollViewProxy,
                         emojis: [String],
                         emoji: String,
                         rowsCount: Int,
                         detector: CurrentValueSubject<ScrollCorrectionType, Never>) {
        guard rowsCount > 0 else { return }
        guard geometry.size.width > 0 else { return }

        /// Stop current scrolling correction
        detector.send(nil)
        /// Computes the number of columns
        let cols = (geometry.size.width / Self.gridColumnSize).rounded(.down)
        let padding = (geometry.size.width - cols * Self.gridColumnSize) / 2

        guard let emojiIndex = emojis.firstIndex(of: emoji) else { return }

        let emojiCol = CGFloat(emojiIndex) / CGFloat(rowsCount)
        let colsCount = (CGFloat(emojis.count) / CGFloat(rowsCount)).rounded(.up)

        let trailingCols = colsCount - emojiCol
        var emojiToScroll = emoji
        if CGFloat(trailingCols) < cols {
            let delta = cols - CGFloat(trailingCols)
            let emojiToScrollIndex = emojiIndex - Int(delta) * rowsCount
            guard 0 <= emojiToScrollIndex && emojiToScrollIndex < emojis.count else { return }
            emojiToScroll = emojis[emojiToScrollIndex]
        }

        /// Compute the left and right padding needs to be centered
        /// UnitPoint takes a ratio betwen the parent and child position
        let x = padding / geometry.size.width
        withAnimation {
            scrollViewProxy.scrollTo(emojiToScroll, anchor: UnitPoint(x: x, y: 1))
        }
    }
}


enum PreferredEmojiPickerInnerViewInput {
    case normal(selectedEmoji: Binding<String?>, draggedEmoji: Binding<String?>, selectAction: () -> Void, haptic: () -> Void)
    case viewer(emojiToShow: String?, addAdditionalSpace: Bool)

    var selectedEmoji: Binding<String?> {
        switch self {
        case .normal(let selectedEmoji, _, _, _):
            return selectedEmoji
        case .viewer:
            return .constant(nil)
        }
    }

    var draggedEmoji: Binding<String?> {
        switch self {
        case .normal(_, let draggedEmoji, _, _):
            return draggedEmoji
        case .viewer:
            return .constant(nil)
        }
    }

    var selectAction: () -> Void {
        switch self {
        case .normal(_, _, let selectAction, _):
            return selectAction
        case .viewer:
            return { }
        }
    }

    var haptic: () -> Void {
        switch self {
        case .normal(_, _, _, let haptic):
            return haptic
        case .viewer:
            return { }
        }
    }

    var addAdditionalSpace: Bool {
        switch self {
        case .normal:
            return true
        case .viewer(_, let addAdditionalSpace):
            return addAdditionalSpace
        }
    }
}


struct PreferredEmojiPickerInnerView: View {

    let input: PreferredEmojiPickerInnerViewInput

    @ObservedObject var preferredEmojiList: ObvMessengerPreferredEmojisListObservable
    private let scrollCorrectionDetector: CurrentValueSubject<EmojiUtils.ScrollCorrectionType, Never>
    private let scrollCorrectionPublisher: AnyPublisher<EmojiUtils.ScrollCorrectionType, Never>


    init(input: PreferredEmojiPickerInnerViewInput,
         preferredEmojiList: ObvMessengerPreferredEmojisListObservable) {
        self.input = input
        self.preferredEmojiList = preferredEmojiList

        do {
            let detector = CurrentValueSubject<EmojiUtils.ScrollCorrectionType, Never>(nil)
            self.scrollCorrectionPublisher = detector
                .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
                .dropFirst()
                .eraseToAnyPublisher()
            self.scrollCorrectionDetector = detector
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack {
                        ScrollViewReader { scrollViewProxy in
                            LazyHGrid(rows: [EmojiUtils.gridItem],
                                      spacing: EmojiUtils.gridSpacing) {
                                ReorderableForEach(items: $preferredEmojiList.emojis,
                                                   draggedItem: input.draggedEmoji,
                                                   haptic: input.haptic,
                                                   none: input.addAdditionalSpace ? EmojiUtils.none : nil) { emoji in
                                    InnerEmojiView(emoji: emoji,
                                                   selectAction: input.selectAction,
                                                   hasVariants: false,
                                                   isPreferredView: true,
                                                   haptic: input.haptic,
                                                   isNone: EmojiUtils.isNone,
                                                   selectedEmoji: input.selectedEmoji,
                                                   showVariantsView: .init(get: { nil }, set: { _ in }),
                                                   draggedEmoji: input.draggedEmoji)
                                        .background(PositionReader(tag: emoji))
                                        .id(emoji)
                                }
                            }
                                      .padding()
                                      .onPreferenceChange(Positions.self) { positions in
                                          /// Send the emoji at the top left
                                          let localGeometry = geometry
                                          var values = positions.map { ($0.key, localGeometry[$0.value]) }
                                              .filter { $0.1.x >= 0 }
                                          values.sort(by: { l, r in l.1.x <= r.1.x })
                                          if let (emoji, _) = values.first {
                                              scrollCorrectionDetector.send(emoji)
                                          }
                                      }
                                      .onReceive(scrollCorrectionPublisher) {
                                          guard let emoji = $0 else { return }
                                          /// Scroll to the top left emoji with corrected position
                                          EmojiUtils.scrollTo(geometry: geometry, scrollViewProxy: scrollViewProxy, emoji: emoji, detector: scrollCorrectionDetector)
                                      }
                                      .onAppear {
                                          switch input {
                                          case .normal(selectedEmoji: let selectedEmoji, _, _, _):
                                              if let selectedEmoji = selectedEmoji.wrappedValue,
                                                 preferredEmojiList.emojis.contains(selectedEmoji) {
                                                  EmojiUtils.scrollTo(geometry: geometry,
                                                                      scrollViewProxy: scrollViewProxy,
                                                                      emojis: preferredEmojiList.emojis,
                                                                      emoji: selectedEmoji,
                                                                      rowsCount: 1,
                                                                      detector: scrollCorrectionDetector)
                                              } else if let first = preferredEmojiList.emojis.first {
                                                  EmojiUtils.scrollTo(geometry: geometry,
                                                                      scrollViewProxy: scrollViewProxy,
                                                                      emoji: first,
                                                                      detector: scrollCorrectionDetector)
                                              }
                                          case .viewer(emojiToShow: let emojiToShow, _):
                                              if let emojiToShow = emojiToShow {
                                                  scrollViewProxy.scrollTo(emojiToShow)
                                              }
                                          }
                                      }
                        }
                        if preferredEmojiList.emojis.isEmpty {
                            Text("DRAG_AND_DROP_TO_CONFIGURE_PREFERRED_EMOJIS_LIST")
                                .font(Font.system(.callout, design: .rounded).weight(.bold))
                        }
                    }
                }
            }
        }
        .frame(height: EmojiUtils.gridColumnSize * 2)
    }
}


struct EmojiPickerInnerView: View {

    @Binding var selectedEmoji: String?
    let selectAction: () -> Void
    let haptic: () -> Void

    @ObservedObject var preferredEmojiList: ObvMessengerPreferredEmojisListObservable

    // The emoji at the top left
    private let scrollCorrectionDetector: CurrentValueSubject<EmojiUtils.ScrollCorrectionType, Never>
    private let scrollCorrectionPublisher: AnyPublisher<EmojiUtils.ScrollCorrectionType, Never>

    init(selectedEmoji: Binding<String?>,
         selectAction: @escaping () -> Void,
         haptic: @escaping () -> Void,
         preferredEmojiList: ObvMessengerPreferredEmojisListObservable) {
        self._selectedEmoji = selectedEmoji
        self.selectAction = selectAction
        self.haptic = haptic
        self.preferredEmojiList = preferredEmojiList

        do {
            let detector = CurrentValueSubject<EmojiUtils.ScrollCorrectionType, Never>(nil)
            self.scrollCorrectionPublisher = detector
                .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
                .dropFirst()
                .eraseToAnyPublisher()
            self.scrollCorrectionDetector = detector
        }

    }

    @State private var selectedGroup: EmojiGroup = EmojiGroup.allCases.first!
    @State private var scrollToGroup: EmojiGroup? = nil
    private var selectedGroupBindingWithScroll: Binding<EmojiGroup> {
        .init { selectedGroup } set: {
            scrollToGroup = $0
        }
    }
    private var selectedGroupBindingWithoutScroll: Binding<EmojiGroup> {
        .init { selectedGroup } set: {
            selectedGroup = $0
        }
    }

    @State private var showVariantsView: String? = nil
    @State private var draggedEmoji: String? = nil
    @State private var rowsCount: Int? = nil

    var body: some View {
        VStack(alignment: .center) {
            PreferredEmojiPickerInnerView(input: .normal(selectedEmoji: $selectedEmoji,
                                                         draggedEmoji: $draggedEmoji,
                                                         selectAction: selectAction,
                                                         haptic: haptic),
                                          preferredEmojiList: preferredEmojiList)
            Divider()
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    ScrollViewReader { scrollViewProxy in
                        LazyHGrid(rows: [GridItem](repeating: EmojiUtils.gridItem,
                                                   count: rowsCount ?? EmojiUtils.computeRowsCount(geometry: geometry)),
                                  spacing: EmojiUtils.gridSpacing) {
                            ForEach(EmojiUtils.allEmojis) { emoji in
                                EmojiView(emoji: emoji, selectAction: selectAction,
                                          haptic: haptic,
                                          isNone: EmojiUtils.isNone,
                                          selectedEmoji: $selectedEmoji,
                                          showVariantsView: $showVariantsView,
                                          draggedEmoji: $draggedEmoji)
                                .id(emoji.defaultEmoji)
                            }
                        }
                                  .padding()
                                  .onChange(of: scrollToGroup) { group in
                                      guard let group = group else { return }
                                      EmojiUtils.scrollTo(geometry: geometry, scrollViewProxy: scrollViewProxy, emoji: group.firstEmoji, detector: scrollCorrectionDetector)
                                      scrollToGroup = nil
                                  }
                                  .onPreferenceChange(Positions.self) { positions in
                                      /// Send the emoji at the top left
                                      let localGeometry = geometry
                                      var values = positions.map { ($0.key, localGeometry[$0.value]) }
                                          .filter { $0.1.x >= 0 }
                                      values.sort(by: { l, r in l.1.x <= r.1.x && l.1.y <= r.1.y })
                                      if let (emoji, _) = values.first {
                                          scrollCorrectionDetector.send(emoji)
                                      }
                                      if let (emoji, _) = values.last {
                                          if let position = EmojiList.allEmojis.firstIndex(of: emoji),
                                             let group = EmojiGroup.group(of: position) {
                                              selectedGroupBindingWithoutScroll.wrappedValue = group
                                          }
                                      }
                                      withAnimation {
                                          self.draggedEmoji = nil
                                      }
                                      if self.rowsCount == nil {
                                          let rowCount = EmojiUtils.computeRowsCount(geometry: geometry)
                                          if rowCount > 0 {
                                              self.rowsCount = rowCount
                                          }
                                      }
                                  }
                                  .onReceive(scrollCorrectionPublisher) {
                                      guard let emoji = $0 else { return }
                                      /// Scroll to the top left emoji with corrected position
                                      EmojiUtils.scrollTo(geometry: geometry, scrollViewProxy: scrollViewProxy, emoji: emoji, detector: scrollCorrectionDetector)
                                  }
                                  .onAppear {
                                      /// Set the current position of the scroll and set the current group
                                      if let selectedEmoji = selectedEmoji, !selectedEmoji.isEmpty {
                                          var group: EmojiGroup?
                                          var representative: String?
                                          if let position = EmojiList.allEmojis.firstIndex(of: selectedEmoji) {
                                              group = EmojiGroup.group(of: position)
                                              representative = selectedEmoji
                                          } else {
                                              // Should be a variant
                                              representative = EmojiList.variants.first { (key, values) in
                                                  return values.contains(selectedEmoji)
                                              }?.key
                                              if let representative = representative,
                                                 let position = EmojiList.allEmojis.firstIndex(of: representative) {
                                                  group = EmojiGroup.group(of: position)
                                              }
                                          }
                                          if let group = group {
                                              selectedGroup = group
                                          }
                                          if let representative = representative {
                                              EmojiUtils.scrollTo(geometry: geometry,
                                                                  scrollViewProxy: scrollViewProxy,
                                                                  emojis: EmojiUtils.allEmojis.map({$0.defaultEmoji}),
                                                                  emoji: representative,
                                                                  rowsCount: rowsCount ?? EmojiUtils.computeRowsCount(geometry: geometry),
                                                                  detector: scrollCorrectionDetector)
                                          }
                                      } else if let firstGroup = EmojiGroup.allCases.first {
                                          selectedGroup = firstGroup
                                          if let first = EmojiList.allEmojis.first {
                                              EmojiUtils.scrollTo(geometry: geometry, scrollViewProxy: scrollViewProxy, emoji: first, detector: scrollCorrectionDetector)
                                          }
                                      }
                                  }
                    }
                }
                .onAppear {
                    guard self.rowsCount == nil else { return }
                    let rowCount = EmojiUtils.computeRowsCount(geometry: geometry)
                    if rowCount > 0 {
                        self.rowsCount = rowCount
                    }
                }
                .overlayPreferenceValue(Positions.self) { positions in
                    /// Show the variants views above the selected emoji
                    if let emoji = showVariantsView,
                       let variants = EmojiList.variants[emoji],
                       let (variantsViewPosition, arrowPosition) = self.getPosition(geometry: geometry,
                                                                                    emoji: emoji,
                                                                                    emojisCount: variants.count + 1, // + 1 is for `emoji`
                                                                                    positions: positions) {
                        let emojisToShow = [emoji] + variants

                        ZStack {
                            /// Show a comics like arrow above the selected emojis
                            Rectangle()
                                .frame(width: EmojiUtils.gridColumnSize / 2, height: EmojiUtils.gridColumnSize / 2)
                                .foregroundColor(.gray)
                                .rotationEffect(.degrees(45))
                                .position(x: arrowPosition.x, y: arrowPosition.y + EmojiUtils.gridColumnSize / 3)
                            VariantEmojiPickerView(emojis: emojisToShow,
                                                   selectAction: selectAction,
                                                   haptic: haptic,
                                                   isNone: EmojiUtils.isNone,
                                                   selectedEmoji: $selectedEmoji,
                                                   draggedEmoji: $draggedEmoji)
                                .position(variantsViewPosition)
                            /// Add a rectangle with a negligeable opacity to be able to tap outside to close the variant view.
                                .background(Rectangle()
                                                .foregroundColor(.gray)
                                                .opacity(0.00001)
                                                .onTapGesture {
                                    showVariantsView = nil
                                })
                        }
                    }
                }
                .onPreferenceChange(Positions.self) { positions in
                    /// Scroll always close the variants view
                    DispatchQueue.main.async {
                        showVariantsView = nil
                    }
                }
            }

            Picker("Category", selection: selectedGroupBindingWithScroll.animation()) {
                ForEach(EmojiGroup.allCases, id: \.self) { group in
                    Text(group.symbol)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .grayscale(1.0)
        }
        .background(.thinMaterial)
    }

    /// Returns the a pair of position of the given emoji, the first position of the variants view
    /// The code takes care that the bouds of the variants view are inside the view regardless of the position of the selected variant.
    fileprivate func getPosition(geometry: GeometryProxy, emoji: String, emojisCount: Int, positions: [String: Anchor<CGPoint>]) -> (CGPoint, CGPoint)? {
        guard let anchor = positions[emoji] else { return nil }
        let point = geometry[anchor]
        let frame = geometry.frame(in: .local)
        guard frame.contains(point) else { return nil }
        let viewWithPicker = emojisCount > VariantEmojiPickerView.maxEmoji
        /// Compute the current trailing and leading space between the bound of the view and the frame
        let cols = viewWithPicker ? 4 : emojisCount
        let trailingCols: Int = cols / 2
        let trailing = frame.maxX - point.x - EmojiUtils.gridColumnSize * CGFloat(trailingCols)
        let leadingCol = cols - trailingCols
        let leading = point.x - EmojiUtils.gridColumnSize * CGFloat(leadingCol) - frame.minX
        /// Look is some space is negative, we should shift to view the show it entirely
        var indexDelta = 0
        if trailing < 0 {
            indexDelta = Int((trailing / EmojiUtils.gridColumnSize).rounded(.up))
        } else if leading < 0 {
            indexDelta = Int((-leading / EmojiUtils.gridColumnSize).rounded(.up))
        }
        let xCorrection = (CGFloat(indexDelta) - 0.5) * EmojiUtils.gridColumnSize
        let yCorrection = -(viewWithPicker ? 0.5 + VariantEmojiPickerView.heightColWithPicker / 2 : 1.0) * EmojiUtils.gridColumnSize
        return (CGPoint(x: point.x + xCorrection, y: point.y + yCorrection),
                CGPoint(x: point.x, y: point.y - EmojiUtils.gridColumnSize))
    }
}
