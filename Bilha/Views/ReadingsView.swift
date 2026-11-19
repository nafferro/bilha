import SwiftUI

/// Saved readings. Tap one to type in what the Galp app showed at the same time.
struct ReadingsView: View {
    @Environment(BottleManager.self) private var manager
    let id: UUID
    @State private var editing: BottleReading?

    private var readings: [BottleReading] { manager.bottle(id)?.readings ?? [] }

    var body: some View {
        List {
            Section {
                ForEach(readings) { r in
                    Button { editing = r } label: { row(r) }
                        .buttonStyle(.plain)
                }
                .onDelete { manager.deleteReadings(at: $0, in: id) }
            } footer: {
                Text(L("Read the bottle in the Galp app, then here, and type in the Galp app's %. A few of these are enough to confirm what each value means."))
            }
        }
        .navigationTitle(L("Readings"))
        .toolbar {
            ShareLink(item: manager.bottle(id)?.csv ?? "", preview: SharePreview(L("Bilha readings")))
        }
        .overlay {
            if readings.isEmpty {
                ContentUnavailableView(L("No readings yet"), systemImage: "flame",
                                       description: Text(L("Read the bottle from its screen.")))
            }
        }
        .sheet(item: $editing) { r in
            GalpPercentSheet(id: id, reading: r)
                .presentationDetents([.height(280)])
        }
    }

    private func row(_ r: BottleReading) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.date.text(date: .abbreviated, time: .shortened))
                    .font(.rounded(.body, weight: .semibold))
                Text(r.raw ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let g = r.galpPercent {
                Text("Galp \(g)%")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "plus.circle").foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct GalpPercentSheet: View {
    @Environment(BottleManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let reading: BottleReading
    @State private var text = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(L("What did the Galp app show?"))
                .font(.rounded(.title3, weight: .bold))
            HStack {
                TextField(L("Gas %"), text: $text)
                    .keyboardType(.numberPad)
                    .font(.rounded(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("%").font(.rounded(.largeTitle, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            BigButton(title: L("Save")) {
                manager.setGalpPercent(Int(text), for: reading, in: id)
                dismiss()
            }
        }
        .padding(Theme.spacing)
        .onAppear { text = reading.galpPercent.map(String.init) ?? "" }
    }
}

