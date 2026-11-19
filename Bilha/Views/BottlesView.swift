import SwiftUI

/// Home: every bottle added, plus adding one by Bluetooth.
struct BottlesView: View {
    @Environment(BottleManager.self) private var manager
    @Binding var path: [UUID]
    @State private var showAdd = false
    @State private var confirmRemove: Bottle?
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    var body: some View {
        ScrollView {
            if manager.bottles.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    CardList(title: nil) {
                        ForEach(manager.bottles) { b in
                            NavigationLink(value: b.id) { BottleRow(bottle: b) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { manager.read(b.id) } label: { Label(L("Read"), systemImage: "arrow.clockwise") }
                                        .disabled(manager.isBusy)
                                    Button(role: .destructive) { confirmRemove = b } label: { Label(L("Remove"), systemImage: "trash") }
                                }
                        }
                    }
                    BigButton(title: L("Add a bottle")) { showAdd = true }
                    Text(L("Touch and hold a bottle to remove it."))
                        .font(.rounded(.footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(Theme.spacing)
            }
        }
        .background(Theme.background)
        .navigationTitle(manager.bottles.isEmpty ? "" : L("Bottles"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAdd = true } label: { Label(L("Add a bottle"), systemImage: "plus") }
                    Picker(selection: $language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    } label: {
                        Label(L("Language"), systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddBottleView { id in path = [id] }
                .presentationDetents([.medium, .large])
        }
        .removeBottleDialog($confirmRemove)
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)
            Image(systemName: "flame.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 128, height: 128)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            VStack(spacing: 8) {
                Text(L("Add your Pluma"))
                    .font(.rounded(.title2, weight: .bold))
                Text(L("Put the iPhone next to the bottle and add it by Bluetooth."))
                    .font(.rounded(.body))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            BigButton(title: L("Add a bottle")) { showAdd = true }
        }
        .padding(Theme.spacing)
    }
}

/// One bottle in the list: flame, name, last reading.
struct BottleRow: View {
    @Environment(BottleManager.self) private var manager
    let bottle: Bottle

    var body: some View {
        HStack(spacing: 14) {
            LevelRing(level: bottle.latest?.levelPercent, lineWidth: 5, busy: manager.isBusy(bottle.id))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.title).font(.rounded(.body, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.rounded(.footnote)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(bottle.latest?.levelPercent.map { "\($0)%" } ?? "—")
                .font(.rounded(.title3, weight: .bold))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if manager.isBusy(bottle.id) { return L("Reading…") }
        if manager.error(for: bottle.id) != nil { return L("Last reading failed") }
        guard let d = bottle.latest?.date else { return L("Not read yet") }
        return L("Read %@", d.relativeText)
    }
}

extension View {
    /// Confirmation before removing a bottle and its readings.
    func removeBottleDialog(_ bottle: Binding<Bottle?>, onRemove: @escaping () -> Void = {}) -> some View {
        modifier(RemoveBottleDialog(bottle: bottle, onRemove: onRemove))
    }
}

private struct RemoveBottleDialog: ViewModifier {
    @Environment(BottleManager.self) private var manager
    @Binding var bottle: Bottle?
    let onRemove: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(L("Remove %@?", bottle?.title ?? L("this bottle")),
                                   isPresented: Binding(get: { bottle != nil }, set: { if !$0 { bottle = nil } }),
                                   titleVisibility: .visible) {
            Button(L("Remove"), role: .destructive) {
                if let b = bottle { manager.remove(b.id); onRemove() }
                bottle = nil
            }
        } message: {
            Text(L("Its readings are deleted from this iPhone. You can add it again later."))
        }
    }
}
