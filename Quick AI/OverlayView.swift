import SwiftUI

struct OverlayView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void
    var onResponseVisibilityChanged: (Bool) -> Void = { _ in }

    @FocusState private var isInputFocused: Bool
    private let bottomAnchorID = "response-bottom"

    var body: some View {
        VStack(spacing: 0) {
            // Input field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))

                TextField("Ask anything...", text: $appState.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isInputFocused)
                    .onSubmit {
                        appState.submit()
                    }

                if appState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Response area
            if showResponseArea {
                Divider()

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
        }
        .frame(width: 600)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear {
            isInputFocused = true
            onResponseVisibilityChanged(showResponseArea)
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
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        } else if appState.response.isEmpty && appState.isLoading {
            Text("Thinking...")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
        } else {
            Text(markdownAttributedString)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var markdownAttributedString: AttributedString {
        (try? AttributedString(
            markdown: appState.response,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(appState.response)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard showResponseArea else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
}
