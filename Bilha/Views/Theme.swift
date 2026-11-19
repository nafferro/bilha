import SwiftUI

/// Small design kit: rounded type, soft cards, coloured rounded-square icons.
enum Theme {
    static let corner: CGFloat = 22
    static let spacing: CGFloat = 16
    static let card = Color(.secondarySystemBackground)
    static let background = Color(.systemBackground)
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// Coloured rounded square with a white symbol, like a list icon.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Big tile for the top of the home screen.
struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: symbol, color: color, size: 34)
            Spacer(minLength: 0)
            Text(value)
                .font(.rounded(.title, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// One row: icon, title, optional trailing text or check.
struct ItemRow: View {
    let symbol: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    var checked = false
    var chevron = false
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rounded(.body, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.rounded(.footnote)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.rounded(.body, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if checked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            } else if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

/// Card that groups rows with thin dividers.
struct CardList<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.rounded(.title3, weight: .bold))
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { i, view in
                        view
                        if i < subviews.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
    }
}

/// Wide filled button.
struct BigButton: View {
    let title: String
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.rounded(.headline, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

