import SwiftUI

/// Lists the Plumas nearby (Bluetooth names starting with "Pluma--"), closest first.
struct AddBottleView: View {
    @Environment(BottleManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    let onAdd: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: manager.state == .bluetoothOff ? "antenna.radiowaves.left.and.right.slash" : "flame.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, isActive: manager.isDiscovering)
                        .frame(width: 100, height: 100)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .padding(.top, 12)

                    Text(message)
                        .font(.rounded(.body))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if !manager.found.isEmpty {
                        CardList(title: nil) {
                            ForEach(manager.found) { p in
                                Button {
                                    let id = manager.addBottle(p)
                                    dismiss()
                                    onAdd(id)
                                } label: {
                                    ItemRow(symbol: "flame.fill", color: Color("Accent"), title: p.name,
                                            subtitle: signal(p.rssi), chevron: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.spacing)
            }
            .background(Theme.background)
            .navigationTitle(L("Nearby Plumas"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
            }
        }
        .onAppear { manager.startDiscovery() }
        .onDisappear { manager.stopDiscovery() }
    }

    private var message: String {
        if manager.state == .bluetoothOff { return L("Turn on Bluetooth and allow this app to use it.") }
        if manager.found.isEmpty { return L("Looking for Plumas… Put the iPhone right next to the bottle.") }
        return L("Tap your bottle. The closest one is at the top.")
    }

    private func signal(_ rssi: Int) -> String {
        switch rssi {
        case (-60)...: L("Very close")
        case (-75)...: L("Close")
        default: L("Far")
        }
    }
}
