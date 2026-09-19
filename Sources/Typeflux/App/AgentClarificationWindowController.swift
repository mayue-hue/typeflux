import AppKit
import SwiftUI

/// Window controller that shows when the agent returns a text clarification question instead of a tool call.
/// Displays the model's response and guides the user to press the hotkey to record a voice reply.
final class AgentClarificationWindowController: NSObject {
    fileprivate enum Metrics {
        static let windowWidth: CGFloat = 760
        static let windowHeight: CGFloat = 420
        static let minWindowWidth: CGFloat = 640
        static let minWindowHeight: CGFloat = 340
        static let outerHorizontalPadding: CGFloat = 16
        static let outerTopPadding: CGFloat = 10
        static let outerBottomPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 10
        static let contentCardCornerRadius: CGFloat = 12
    }

    enum RecordingState {
        case waitingForReply
        case recording
        case transcribing
    }

    fileprivate final class Model: ObservableObject {
        @Published var question: String = ""
        @Published var selectedText: String = ""
        @Published var modelResponse: String = ""
        @Published var recordingState: RecordingState = .waitingForReply
        @Published var appearanceMode: AppearanceMode = .light
        @Published var isSelectedTextExpanded: Bool = false
    }

    /// Called when the user closes the clarification window.
    var onDismiss: (() -> Void)?

    private let settingsStore: SettingsStore
    fileprivate let model = Model()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AgentClarificationWindowView>?
    private var appearanceObserver: NSObjectProtocol?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .appearanceModeDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window else { return }
            model.appearanceMode = self.settingsStore.appearanceMode
            hostingView?.rootView = AgentClarificationWindowView(model: model)
            applyAppearance(to: window)
        }
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    func show(question: String, selectedText: String?, modelResponse: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show(question: question, selectedText: selectedText, modelResponse: modelResponse)
            }
            return
        }

        ensureWindow()

        model.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        model.selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        model.modelResponse = modelResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        model.recordingState = .waitingForReply
        model.appearanceMode = settingsStore.appearanceMode

        guard let window else { return }
        hostingView?.rootView = AgentClarificationWindowView(model: model)
        applyAppearance(to: window)
        if !window.isVisible {
            window.center()
        }
        DockVisibilityController.shared.windowDidShow(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.dismiss() }
            return
        }
        if let window {
            DockVisibilityController.shared.windowDidHide(window)
            window.orderOut(nil)
        }
    }

    /// Updates the recording state indicator shown in the window.
    func updateRecordingState(_ state: RecordingState) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.updateRecordingState(state) }
            return
        }
        model.recordingState = state
    }

    private func ensureWindow() {
        guard window == nil else { return }

        model.appearanceMode = settingsStore.appearanceMode
        let rootView = AgentClarificationWindowView(model: model)
        let hosting = NSHostingView(rootView: rootView)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.windowWidth, height: Metrics.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        win.title = L("agent.clarification.windowTitle")
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.minSize = NSSize(width: Metrics.minWindowWidth, height: Metrics.minWindowHeight)
        win.backgroundColor = NSColor(StudioTheme.windowBackground)
        win.contentView = hosting
        win.level = .normal
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        applyAppearance(to: win)

        hostingView = hosting
        window = win
    }

    private func applyAppearance(to window: NSWindow) {
        window.appearance = AppAppearance.nsAppearance(for: settingsStore.appearanceMode)
        window.backgroundColor = NSColor(StudioTheme.windowBackground)
    }
}

extension AgentClarificationWindowController: NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        dismiss()
        onDismiss?()
        return false
    }
}

private struct AgentClarificationWindowView: View {
    @ObservedObject var model: AgentClarificationWindowController.Model

    var body: some View {
        ZStack {
            StudioTheme.windowBackground

            VStack(alignment: .leading, spacing: AgentClarificationWindowController.Metrics.sectionSpacing) {
                promptSection
                modelResponseSection
                replyHintSection
            }
            .padding(.horizontal, AgentClarificationWindowController.Metrics.outerHorizontalPadding)
            .padding(.top, AgentClarificationWindowController.Metrics.outerTopPadding)
            .padding(.bottom, AgentClarificationWindowController.Metrics.outerBottomPadding)
        }
        .frame(
            minWidth: AgentClarificationWindowController.Metrics.minWindowWidth,
            idealWidth: AgentClarificationWindowController.Metrics.windowWidth,
            maxWidth: .infinity,
            minHeight: AgentClarificationWindowController.Metrics.minWindowHeight,
            idealHeight: AgentClarificationWindowController.Metrics.windowHeight,
            maxHeight: .infinity
        )
    }

    private var promptSection: some View {
        HStack(alignment: .top, spacing: StudioTheme.Spacing.smallMedium) {
            Image(systemName: "mic")
                .font(.system(size: StudioTheme.Typography.iconMedium, weight: .semibold))
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: StudioTheme.Spacing.textCompact) {
                HStack(alignment: .firstTextBaseline, spacing: StudioTheme.Spacing.xSmall) {
                    Text(model.question)
                        .font(.studioBody(StudioTheme.Typography.body, weight: .semibold))
                        .foregroundStyle(StudioTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !model.selectedText.isEmpty {
                        Image(systemName: model.isSelectedTextExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: StudioTheme.Typography.iconTiny, weight: .semibold))
                            .foregroundStyle(StudioTheme.textTertiary)
                            .padding(.top, 2)
                    }
                }

                if !model.selectedText.isEmpty {
                    Text(model.selectedText)
                        .font(.studioBody(StudioTheme.Typography.bodySmall, weight: .medium))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .lineLimit(model.isSelectedTextExpanded ? nil : 4)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, StudioTheme.Spacing.small)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(StudioTheme.border.opacity(0.9))
                                .frame(width: 3)
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !model.selectedText.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    model.isSelectedTextExpanded.toggle()
                }
            }
        }
        .padding(8)
    }

    private var modelResponseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L("agent.clarification.assistantSectionTitle"), systemImage: "sparkles")
                    .font(.studioBody(StudioTheme.Typography.bodySmall, weight: .semibold))
                    .foregroundStyle(StudioTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .overlay(StudioTheme.border.opacity(0.8))

            MarkdownWebView(
                markdown: model.modelResponse,
                appearanceMode: model.appearanceMode
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(
                cornerRadius: AgentClarificationWindowController.Metrics.contentCardCornerRadius,
                style: .continuous
            )
            .fill(StudioTheme.surface)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: AgentClarificationWindowController.Metrics.contentCardCornerRadius,
                style: .continuous
            )
            .stroke(StudioTheme.border.opacity(0.85), lineWidth: 1)
        )
    }

    private var replyHintSection: some View {
        HStack(spacing: StudioTheme.Spacing.small) {
            hintIcon
            Text(hintText)
                .font(.studioBody(StudioTheme.Typography.bodySmall, weight: .medium))
                .foregroundStyle(hintColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var hintIcon: some View {
        Group {
            switch model.recordingState {
            case .waitingForReply:
                Image(systemName: "mic.badge.plus")
                    .foregroundStyle(StudioTheme.accent)
            case .recording:
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
        }
        .font(.system(size: StudioTheme.Typography.iconSmall, weight: .semibold))
        .frame(width: 20)
    }

    private var hintText: String {
        switch model.recordingState {
        case .waitingForReply:
            L("agent.clarification.hotkeyHint")
        case .recording:
            L("agent.clarification.recordingHint")
        case .transcribing:
            L("agent.clarification.transcribingHint")
        }
    }

    private var hintColor: Color {
        switch model.recordingState {
        case .waitingForReply:
            StudioTheme.textSecondary
        case .recording:
            .red
        case .transcribing:
            StudioTheme.textSecondary
        }
    }
}
