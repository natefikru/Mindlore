import SwiftUI
import UIKit

// The row above the keyboard: what the paragraph under the caret is, and the buttons that change
// it. The text view owns the model and answers the actions; this only draws state. Nine buttons,
// Day One's set less the rule, in a row that scrolls if Dynamic Type makes it long.
enum FormatAction: Equatable {
    case block(EntryFormatting.Block)
    case inline(FormattingStyle.Inline)
    case indent(Int)
    case dismissKeyboard
}

// A name being typed after "@": what was typed and who it could be. While one is open the bar
// shows the names instead of the buttons.
struct MentionState: Equatable {
    var query: String
    var matches: [EntitySearch.Row]
}

enum MentionPick: Equatable {
    case existing(EntitySearch.Row)
    case new(String)
}

@MainActor
@Observable
final class FormatBarModel {
    var block: EntryFormatting.Block?
    var indent = 0
    var inline: FormattingStyle.Inline = []
    var mention: MentionState?
    var onAction: (FormatAction) -> Void = { _ in }
    var onPick: (MentionPick) -> Void = { _ in }
}

struct FormatBarView: View {
    let model: FormatBarModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                if let mention = model.mention {
                    mentionRow(mention)
                } else {
                    buttons
                }
            }
            Divider().frame(height: 24)
            Button { model.onAction(.dismissKeyboard) } label: { Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down") }
                .padding(.horizontal, 10)
                .accessibilityIdentifier("formatDismissKeyboard")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(FormatButtonStyle())
        .frame(height: 44)
        .background(.bar)
        .accessibilityIdentifier("formatBar")
    }

    // The names the "@" could mean, best first, and the typed name as someone new.
    private func mentionRow(_ mention: MentionState) -> some View {
        HStack(spacing: 6) {
            ForEach(mention.matches) { row in
                Button { model.onPick(.existing(row)) } label: {
                    Label(row.name, systemImage: row.kind.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .buttonStyle(MentionChipStyle())
                .accessibilityIdentifier("mention-\(row.name)")
            }
            let typed = mention.query.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty, !mention.matches.contains(where: { $0.name.caseInsensitiveCompare(typed) == .orderedSame }) {
                Button { model.onPick(.new(typed)) } label: {
                    Label("Add \u{201C}\(typed)\u{201D}", systemImage: "person.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .buttonStyle(MentionChipStyle())
                .accessibilityIdentifier("mentionAdd")
            }
            if mention.matches.isEmpty && typed.isEmpty {
                Text("Type a name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
    }

    private var buttons: some View {
                HStack(spacing: 2) {
                    blockButton(.heading1, "Title", "textformat.size.larger")
                    blockButton(.heading2, "Heading", "textformat.size")
                    inlineButton(.bold, "Bold", "bold")
                    inlineButton(.italic, "Italic", "italic")
                    inlineButton(.strike, "Strikethrough", "strikethrough")
                    blockButton(.bullet, "Bulleted list", "list.bullet")
                    blockButton(.number, "Numbered list", "list.number")
                    blockButton(.check, "Checklist", "checklist")
                    blockButton(.quote, "Quote", "text.quote")
                    Button { model.onAction(.indent(-1)) } label: { Label("Outdent", systemImage: "decrease.indent") }
                        .disabled(model.indent == 0)
                        .accessibilityIdentifier("formatOutdent")
                    Button { model.onAction(.indent(1)) } label: { Label("Indent", systemImage: "increase.indent") }
                        .disabled(model.indent >= EntryFormatting.maxIndent || model.block?.isList == false)
                        .accessibilityIdentifier("formatIndent")
                }
                .padding(.horizontal, 6)
    }

    private func blockButton(_ block: EntryFormatting.Block, _ title: String, _ symbol: String) -> some View {
        let active = model.block == block || (block == .check && model.block == .checked)
        return Button { model.onAction(.block(block)) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(FormatButtonStyle(active: active))
            .accessibilityIdentifier("format-\(block.rawValue)")
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func inlineButton(_ mark: FormattingStyle.Inline, _ title: String, _ symbol: String) -> some View {
        let active = model.inline.contains(mark)
        return Button { model.onAction(.inline(mark)) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(FormatButtonStyle(active: active))
            .accessibilityIdentifier("format-\(title.lowercased())")
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct MentionChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(Palette.ink)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct FormatButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .frame(width: 38, height: 34)
            .foregroundStyle(active ? Color.accentColor : Palette.ink)
            .background(active ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

// Hosts the bar as a UITextView's inputAccessoryView.
@MainActor
final class FormatBarHost {
    let model = FormatBarModel()
    let view: UIView

    init() {
        let controller = UIHostingController(rootView: FormatBarView(model: model))
        controller.view.backgroundColor = .clear
        let input = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 44), inputViewStyle: .keyboard)
        input.allowsSelfSizing = false
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        input.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: input.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: input.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: input.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: input.bottomAnchor),
        ])
        view = input
        self.controller = controller
    }

    private let controller: UIHostingController<FormatBarView>
}
