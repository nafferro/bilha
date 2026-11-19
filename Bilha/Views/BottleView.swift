import SwiftUI

/// One bottle: read it, see the raw reply, help decode the level.
struct BottleView: View {
    @Environment(BottleManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var confirmRemove: Bottle?
    @State private var renaming = false
    @State private var newLabel = ""

    var body: some View {
        if let b = manager.bottle(id) {
            content(b)
        } else {
            ContentUnavailableView(L("Bottle removed"), systemImage: "trash")
        }
    }

    private func content(_ b: Bottle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GaugeCard(level: b.latest?.levelPercent, temperature: b.latest?.temperatureC,
                          busy: manager.isBusy(id))

                HStack(spacing: 12) {
                    StatTile(title: L("Temperature"),
                             value: b.latest?.temperatureC.map { "\($0)°C" } ?? "—",
                             symbol: "thermometer.medium", color: .blue)
                    StatTile(title: L("Last read"), value: b.latest?.date.relativeText ?? L("Never"),
                             symbol: "clock.fill", color: .gray)
                }

                if let msg = manager.error(for: id) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.rounded(.subheadline, weight: .medium))
                        .foregroundStyle(.red)
                }

                BigButton(title: buttonTitle, color: manager.isBusy ? .gray : Color("Accent")) {
                    manager.read(id)
                }
                .disabled(manager.isBusy)
            }
            .padding(Theme.spacing)
        }
        .background(Theme.background)
        .navigationTitle(b.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newLabel = b.label ?? ""; renaming = true } label: { Label(L("Rename"), systemImage: "pencil") }
                    NavigationLink { ReadingsView(id: id) } label: { Label(L("Readings"), systemImage: "list.bullet") }
                    Divider()
                    Button(role: .destructive) { confirmRemove = b } label: { Label(L("Remove bottle"), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .refreshable { if !manager.isBusy { manager.read(id) } }
        .alert(L("Rename bottle"), isPresented: $renaming) {
            TextField(b.deviceName ?? "Pluma", text: $newLabel)
            Button(L("Save")) { manager.rename(id, to: newLabel) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("For example, Kitchen or Barbecue. Leave it empty to use its Bluetooth name."))
        }
        .removeBottleDialog($confirmRemove) { dismiss() }
    }

    private var buttonTitle: String {
        guard manager.activeID == id else { return manager.isBusy ? L("Reading another bottle…") : L("Read bottle") }
        switch manager.state {
        case .scanning: return L("Looking for the bottle…")
        case .connecting: return L("Connecting…")
        case .reading: return L("Reading…")
        case .bluetoothOff: return L("Bluetooth is off")
        default: return L("Read bottle")
        }
    }
}

/// Big card: the gas ring and the level.
struct GaugeCard: View {
    let level: Int?
    let temperature: Int?
    let busy: Bool

    var body: some View {
        HStack(spacing: 22) {
            LevelRing(level: level, busy: busy)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.rounded(.largeTitle, weight: .bold))
                    .contentTransition(.numericText())
                Text(L("Gas left"))
                    .font(.rounded(.headline, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Ring with a flame in the middle; full = 100%.
struct LevelRing: View {
    let level: Int?
    var lineWidth: CGFloat = 16
    var busy = false

    private var fraction: Double { Double(min(max(level ?? 0, 0), 100)) / 100 }
    var color: Color {
        guard let level else { return .gray }
        return level < 15 ? .red : level < 30 ? .orange : Color("Accent")
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.8), value: fraction)
                Image(systemName: "flame.fill")
                    .font(.system(size: g.size.width * 0.3, weight: .semibold))
                    .foregroundStyle(color.gradient)
                    .symbolEffect(.pulse, isActive: busy)
            }
        }
    }
}
