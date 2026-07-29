import AppKit
import SwiftUI

@MainActor
final class FloatingSuggestionPanelController: NSObject, ObservableObject {
    @Published private(set) var isExpanded = false

    private let panel: NSPanel
    private weak var model: AppModel?
    private let compactSize = NSSize(width: 292, height: 62)
    private let expandedSize = NSSize(width: 380, height: 360)

    init(model: AppModel) {
        self.model = model
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.panel = panel
        super.init()

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(
            rootView: FloatingSuggestionView(controller: self)
                .environmentObject(model)
        )
    }

    func show(near elementFrame: CGRect?) {
        isExpanded = false
        resize(to: compactSize)
        position(near: elementFrame, size: compactSize)
        panel.orderFrontRegardless()
    }

    func expand() {
        isExpanded = true
        resize(to: expandedSize)
        position(near: nil, size: expandedSize)
    }

    func collapse() {
        isExpanded = false
        resize(to: compactSize)
    }

    func hide() {
        panel.orderOut(nil)
        isExpanded = false
    }

    private func resize(to size: NSSize) {
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true, animate: true)
    }

    private func position(near elementFrame: CGRect?, size: NSSize) {
        let screen = NSScreen.screens.first { screen in
            guard let elementFrame else { return false }
            return screen.frame.contains(elementFrame.origin)
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var x = visible.maxX - size.width - 18
        var y = visible.maxY - size.height - 22
        if let elementFrame {
            x = min(max(visible.minX + 14, elementFrame.maxX - size.width), visible.maxX - size.width - 14)
            // Accessibility coordinates use a top-left origin; AppKit uses a
            // bottom-left origin. Place the pill just above the text field.
            y = screen.frame.maxY - elementFrame.minY - size.height - 12
            y = min(max(visible.minY + 12, y), visible.maxY - size.height - 12)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct FloatingSuggestionView: View {
    @ObservedObject var controller: FloatingSuggestionPanelController
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if controller.isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .padding(controller.isExpanded ? 14 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: controller.isExpanded ? 16 : 31))
        .overlay {
            RoundedRectangle(cornerRadius: controller.isExpanded ? 16 : 31)
                .strokeBorder(.white.opacity(0.14))
        }
        .animation(.easeInOut(duration: 0.16), value: model.latestSuggestions)
    }

    private var compactView: some View {
        Button {
            controller.expand()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WriteSense")
                        .font(.subheadline.weight(.semibold))
                    Text("\(model.latestSuggestions.count) writing suggestion\(model.latestSuggestions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Writing suggestions", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button {
                    controller.hide()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if model.latestSuggestions.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.green)
                    Text("All suggestions handled")
                        .font(.headline)
                    Text("You can close this panel when you’re ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Done") {
                        controller.hide()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(model.latestSuggestions.prefix(3))) { suggestion in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(suggestion.category.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(suggestion.confidence * 100))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if suggestion.requiresClarification {
                                Label("Choose your intended meaning", systemImage: "questionmark.bubble")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            } else {
                                HStack(spacing: 6) {
                                    Text(suggestion.originalText)
                                        .foregroundStyle(.red)
                                        .strikethrough()
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                    Text(suggestion.suggestedText)
                                        .fontWeight(.semibold)
                                }
                            }
                            Text(suggestion.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let reason = suggestion.personalizationReason, suggestion.isPersonalized {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            if suggestion.requiresClarification {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(suggestion.alternativeTexts, id: \.self) { alternative in
                                        Button(alternative) {
                                            if model.canApplyCurrentSuggestions {
                                                model.editAndApply(suggestion, replacement: alternative)
                                            } else {
                                                model.copyReplacement(alternative)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    HStack {
                                        Button("Reject") { model.reject(suggestion) }
                                            .buttonStyle(.bordered)
                                        Button("Ignore") { model.ignore(suggestion) }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            } else {
                                HStack(spacing: 8) {
                                    if model.canApplyCurrentSuggestions {
                                        Button("Apply") { model.accept(suggestion) }
                                            .buttonStyle(.borderedProminent)
                                    } else {
                                        Button("Copy") { model.copyReplacement(suggestion) }
                                            .buttonStyle(.borderedProminent)
                                        Text("Terminal is read-only")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button("Reject") { model.reject(suggestion) }
                                        .buttonStyle(.bordered)
                                    Button("Ignore") { model.ignore(suggestion) }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                            .padding(9)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }
}
