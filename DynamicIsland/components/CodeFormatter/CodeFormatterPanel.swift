/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Defaults
import SwiftUI

private enum CodeFormatterPanelMetrics {
    static let cornerRadius: CGFloat = 18
    static let contentInset: CGFloat = 12
    static let paneSpacing: CGFloat = 1
    static let defaultSize = CGSize(width: 900, height: 560)
    static let minimumSize = CGSize(width: 640, height: 380)

    /// Sandbox tokens so more than one utility panel can record a position.
    static let originXKey = "codeFormatterPanelOriginX"
    static let originYKey = "codeFormatterPanelOriginY"
}

class CodeFormatterPanelManager: ObservableObject {
    static let shared = CodeFormatterPanelManager()

    private var panel: CodeFormatterPanel?

    private init() {}

    func showPanel() {
        hidePanel()

        let newPanel = CodeFormatterPanel()
        panel = newPanel
        newPanel.positionNearNotch()
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.orderFrontRegardless()

        NSApp.activate(ignoringOtherApps: true)

        // Text fields only take the first keystroke once the panel is key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            newPanel.makeKey()
        }
    }

    func hidePanel() {
        panel?.close()
        panel = nil
    }

    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }
}

/// Persists the panel's size so a resized window keeps its shape next time.
private final class CodeFormatterPanelSizeTracker: NSObject, NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Defaults[.codeFormatterPanelSizeWidth] = Double(window.frame.size.width)
        Defaults[.codeFormatterPanelSizeHeight] = Double(window.frame.size.height)
    }
}

class CodeFormatterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private let sizeTracker = CodeFormatterPanelSizeTracker()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: true
        )
        setupPanel()
        setupContentView()
    }

    private func setupPanel() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true

        styleMask.insert(.fullSizeContentView)

        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        acceptsMouseMovedEvents = true

        delegate = sizeTracker

        let restored = CGSize(
            width: max(Defaults[.codeFormatterPanelSizeWidth], CodeFormatterPanelMetrics.minimumSize.width),
            height: max(Defaults[.codeFormatterPanelSizeHeight], CodeFormatterPanelMetrics.minimumSize.height)
        )
        minSize = CodeFormatterPanelMetrics.minimumSize
        setContentSize(restored)
    }

    private func setupContentView() {
        let panelView = CodeFormatterPanelView {
            CodeFormatterPanelManager.shared.hidePanel()
        }
        let hostingView = NSHostingView(rootView: panelView)
        applyCornerMask(hostingView, radius: CodeFormatterPanelMetrics.cornerRadius)
        contentView = hostingView
        hostingView.setFrameSize(contentSizeForView(restoredSize: frame.size))
    }

    private func applyCornerMask(_ view: NSView, radius: CGFloat) {
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerRadius = radius
        view.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 13.0, *) {
            view.layer?.cornerCurve = .continuous
        }
    }

    private func contentSizeForView(restoredSize: CGSize) -> CGSize {
        CGSize(width: max(restoredSize.width, 320), height: max(restoredSize.height, 240))
    }

    func positionNearNotch() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = frame

        if let saved = Self.savedOrigin() {
            let savedFrame = NSRect(origin: saved, size: panelFrame.size)
            if screenFrame.contains(savedFrame) {
                setFrameOrigin(saved)
                return
            }
            if screenFrame.intersects(savedFrame) {
                setFrameOrigin(Self.clampedOrigin(saved, size: panelFrame.size, within: screenFrame))
                return
            }
        }

        setFrameOrigin(
            NSPoint(
                x: (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX,
                y: (screenFrame.height - panelFrame.height) / 2 + screenFrame.minY
            )
        )
    }

    /// Keeps a frame of `size` fully inside `bounds`.
    static func clampedOrigin(_ origin: NSPoint, size: NSSize, within bounds: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }

    private static func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        let x = defaults.double(forKey: CodeFormatterPanelMetrics.originXKey)
        let y = defaults.double(forKey: CodeFormatterPanelMetrics.originYKey)
        guard x != 0.0 || y != 0.0 else { return nil }
        return NSPoint(x: x, y: y)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        saveOrigin(point)
    }

    private func saveOrigin(_ point: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(point.x, forKey: CodeFormatterPanelMetrics.originXKey)
        defaults.set(point.y, forKey: CodeFormatterPanelMetrics.originYKey)
    }

    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}

struct CodeFormatterPanelView: View {
    let onClose: () -> Void

    @Default(.codeFormatterLanguage) private var language
    @Default(.codeFormatterIndentWidth) private var indentWidth
    @Default(.codeFormatterLiveFormat) private var liveFormat
    @Default(.codeFormatterUppercaseSQLKeywords) private var uppercaseSQLKeywords
    @Default(.codeFormatterInputText) private var inputText

    @State private var outputText = ""
    @State private var statusMessage: String?
    @State private var hasError = false
    @State private var justCopied = false
    @State private var copyTask: Task<Void, Never>?
    @State private var formatTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()
                .background(Color.gray.opacity(0.3))

            contentSection

            Divider()
                .background(Color.gray.opacity(0.3))

            footerSection
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(CodeFormatterPanelMetrics.cornerRadius)
        .onAppear(perform: formatInput)
        .onChange(of: inputText) { _, _ in
            Defaults[.codeFormatterInputText] = inputText
            scheduleFormat()
        }
        .onChange(of: language) { _, _ in formatInput() }
        .onChange(of: indentWidth) { _, _ in formatInput() }
        .onChange(of: uppercaseSQLKeywords) { _, _ in formatInput() }
        .onDisappear {
            formatTask?.cancel()
            copyTask?.cancel()
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            NativeStyleCloseButton(action: onClose)

            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)

                Text("Code Formatter")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Toggle("Auto", isOn: $liveFormat)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(String(localized: "Reformat as you type"))

            Picker("", selection: $language) {
                ForEach(CodeFormatterLanguage.allCases) { option in
                    Text(option.localizedName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .labelsHidden()

            Button(action: pasteFromClipboard) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(String(localized: "Paste from clipboard"))
        }
        .padding(CodeFormatterPanelMetrics.contentInset)
    }

    // MARK: Content

    private var contentSection: some View {
        HSplitView {
            inputPane
                .frame(minWidth: 260)

            outputPane
                .frame(minWidth: 260)
        }
        .frame(maxHeight: .infinity)
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                paneLabel("Input")

                Spacer()

                Text("\(inputText.formatterLineCount) lines")
                    .foregroundStyle(.secondary)

                Button(action: { inputText = "" }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.red)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(inputText.isEmpty)
            }
            .font(.system(size: 12, weight: .medium))

            editorContainer {
                TextEditor(text: $inputText)
                    .font(editorFont)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .overlay(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text(language.editorPlaceholder)
                                .font(editorFont)
                                .foregroundStyle(.tertiary)
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(CodeFormatterPanelMetrics.contentInset)
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                paneLabel("Formatted Output")

                Spacer()

                if hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Button(action: copyOutput) {
                    HStack(spacing: 4) {
                        Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(justCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(justCopied ? .green : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(outputText.isEmpty)
            }
            .font(.system(size: 12, weight: .medium))

            editorContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if outputText.isEmpty {
                            Text(emptyOutputHint)
                                .font(editorFont)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        } else {
                            Text(outputText)
                                .font(editorFont)
                                .foregroundStyle(hasError ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(CodeFormatterPanelMetrics.contentInset)
    }

    // MARK: Footer

    private var footerSection: some View {
        HStack(spacing: 10) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(hasError ? .orange : .secondary)
                    .lineLimit(2)
            } else {
                Text("\(inputText.count) characters in · \(outputText.count) out")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: minifyInput) {
                Text("Minify")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(7)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || !CodeFormatterEngine.minifiableLanguages.contains(language))
            .help(String(localized: "Collapse whitespace and comments out of \(language.localizedName)"))

            Button(action: formatInput) {
                Text("Format")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .cornerRadius(7)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, CodeFormatterPanelMetrics.contentInset)
        .padding(.vertical, 10)
    }

    // MARK: Behaviour

    private var editorFont: Font {
        .system(size: 13, design: .monospaced)
    }

    private var emptyOutputHint: String {
        String(localized: "Formatted output appears here.")
    }

    private func paneLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .foregroundStyle(.primary)
    }

    private func editorContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func scheduleFormat() {
        guard liveFormat else { return }
        formatTask?.cancel()
        formatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            applyFormatting()
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        inputText = text
        formatInput()
    }

    private func formatInput() {
        formatTask?.cancel()
        applyFormatting()
    }

    private func minifyInput() {
        let result = CodeFormatterEngine.minify(inputText, language: language)
        outputText = result.output
        hasError = !result.isValid
        statusMessage = result.message
    }

    private func applyFormatting() {
        let source = inputText
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            outputText = ""
            statusMessage = nil
            hasError = false
            return
        }

        let result = CodeFormatterEngine.format(
            source,
            language: language,
            indentWidth: indentWidth,
            uppercaseSQLKeywords: uppercaseSQLKeywords
        )
        outputText = result.output
        hasError = !result.isValid
        statusMessage = result.message
    }

    private func copyOutput() {
        guard !outputText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            justCopied = true
        }
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) {
                justCopied = false
            }
        }

        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
    }
}

private extension String {
    /// Line count that counts a trailing newline as ending the last line.
    var formatterLineCount: Int {
        isEmpty ? 0 : split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

#Preview {
    CodeFormatterPanelView {}
        .frame(width: 900, height: 560)
}
