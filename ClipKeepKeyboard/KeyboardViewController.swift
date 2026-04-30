import UIKit
import SwiftUI
import ClipKeepCore

final class KeyboardViewController: UIInputViewController {
    private let store = KeyboardStore()
    private let reader = PasteboardReader(defaults: AppGroup.defaults, readsInitialValue: true)
    private var heightConstraint: NSLayoutConstraint?
    private var lastInsertedText: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboardView = KeyboardView(
            store: store,
            onSelect: { [weak self] item in
                self?.handleSelection(item) ?? false
            },
            onInsertText: { [weak self] text in
                // Called after OCR completes — insert the recognised text directly.
                self?.insertTextFromKeyboard(text)
            },
            onUndoInsertion: { [weak self] in
                self?.undoLastInsertion() ?? false
            },
            onDeleteBackward: { [weak self] in
                self?.clearUndoInsertion()
                self?.textDocumentProxy.deleteBackward()
            },
            onDismiss: { [weak self] in self?.advanceToNextInputMode() }
        )
        let host = UIHostingController(rootView: keyboardView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let h = view.heightAnchor.constraint(equalToConstant: 270)
        h.priority = UILayoutPriority(999)
        view.addConstraint(h)
        heightConstraint = h

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        capturePasteboardAndReload()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        capturePasteboardAndReload()
    }

    private func capturePasteboardAndReload() {
        if let clip = reader.readClipIfChanged() {
            ClipStore.shared.add(clip)
        }
        store.reload()
    }

    private func handleSelection(_ item: ClipItem) -> Bool {
        if item.kind == .text {
            insertTextFromKeyboard(item.content)
            return true
        }

        let copied = ClipStore.shared.copyToPasteboard(item)
        if copied {
            reader.markCurrentChangeCountSeen()
        }
        return copied
    }

    private func insertTextFromKeyboard(_ text: String) {
        guard !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        lastInsertedText = text
        store.setCanUndoInsertion(true)
    }

    private func undoLastInsertion() -> Bool {
        guard let text = lastInsertedText, !text.isEmpty else { return false }
        for _ in text {
            textDocumentProxy.deleteBackward()
        }
        clearUndoInsertion()
        return true
    }

    private func clearUndoInsertion() {
        lastInsertedText = nil
        store.setCanUndoInsertion(false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let isLandscape = view.bounds.width > view.bounds.height
        heightConstraint?.constant = isLandscape ? 200 : 270
    }
}
