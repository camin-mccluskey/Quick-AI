import AppKit
import SwiftUI

struct OverlayView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void
    var onResponseVisibilityChanged: (Bool) -> Void = { _ in }

    @State private var shouldFocusInput = false
    @State private var copyFeedbackText: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

    private let bottomAnchorID = "response-bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))

                PromptInputTextView(
                    text: $appState.query,
                    shouldFocus: shouldFocusInput,
                    onSubmit: {
                        appState.submit()
                    }
                )
                .frame(height: 28)

                if appState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .simultaneousGesture(WindowDragGesture())

            if showResponseArea {
                Divider()

                VStack(spacing: 0) {
                    if appState.isSearchingWeb {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 11, weight: .medium))
                            Text("Searching web...")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                    }

                    if let feedback = copyFeedbackText {
                        HStack {
                            Spacer()
                            Text(feedback)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                                .padding(.horizontal, 16)
                        }
                    } else if !appState.response.isEmpty {
                        HStack(spacing: 8) {
                            Spacer()

                            Button("Copy response") {
                                copyResponse()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                responseContent
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)

                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchorID)
                            }
                        }
                        .onAppear {
                            scrollToBottom(proxy)
                        }
                        .onChange(of: appState.response) { _, _ in
                            scrollToBottom(proxy)
                        }
                    }
                    .frame(maxHeight: 500)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 600)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
        .animation(.easeOut(duration: 0.12), value: showResponseArea)
        .onAppear {
            shouldFocusInput = true
            onResponseVisibilityChanged(showResponseArea)
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
        .onChange(of: showResponseArea) { _, newValue in
            onResponseVisibilityChanged(newValue)
        }
    }

    private var showResponseArea: Bool {
        !appState.response.isEmpty || appState.error != nil || appState.isLoading
    }

    @ViewBuilder
    private var responseContent: some View {
        if let error = appState.error {
            VStack(alignment: .leading, spacing: 10) {
                Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)

                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Retry") {
                        appState.submit()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if appState.response.isEmpty && appState.isLoading {
            Text(appState.isSearchingWeb ? "Looking up current info..." : "Thinking...")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
        } else {
            Text(appState.renderedResponse)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard showResponseArea else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func copyResponse() {
        guard !appState.response.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.response, forType: .string)
        showCopyFeedback("Response copied")
    }

    private func showCopyFeedback(_ text: String) {
        copyFeedbackTask?.cancel()
        copyFeedbackText = text

        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            copyFeedbackText = nil
            copyFeedbackTask = nil
        }
    }
}

private struct PromptInputTextView: NSViewRepresentable {
    @Binding var text: String
    var shouldFocus: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 18)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.placeholder = NSAttributedString(
            string: "Ask anything...",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 18),
            ]
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.onSubmit = onSubmit

        if shouldFocus,
           let window = textView.window,
           window.firstResponder !== textView {
            DispatchQueue.main.async {
                window.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?

    var placeholder: NSAttributedString? {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let placeholder, string.isEmpty else { return }
        // Determine text container inset and the typing attributes to align placeholder
        let inset = textContainerInset
        let origin = NSPoint(x: inset.width + 2, y: inset.height)
        placeholder.draw(at: origin)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) {
                insertNewline(nil)
                return
            }

            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}
