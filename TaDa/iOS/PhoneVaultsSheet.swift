// The Vaults sheet: the folders opened on this iPhone, to switch between, remove or add one.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneVaultsSheet: View {
    let model: AppModel
    @State private var isPicking = false
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("On this iPhone") {
                    ForEach(model.vaults) { vault in
                        row(vault)
                            .swipeActions(edge: .trailing) {
                                if !vault.isOpen {
                                    Button("Remove", role: .destructive) { model.forget(vault) }
                                        .tint(theme.color(\.deadline))
                                }
                            }
                    }
                }
                .listRowBackground(theme.color(\.code))
                Section {
                    Button { isPicking = true } label: {
                        Label("Open Another Vault…", systemImage: "folder.badge.plus")
                    }
                    .foregroundStyle(theme.color(\.accent))
                } footer: {
                    Text("Remove forgets a vault on this iPhone. Its files stay where they are.")
                }
                .listRowBackground(theme.color(\.code))
            }
            .scrollContentBackground(.hidden)
            .background(theme.color(\.bg))
            .navigationTitle("Vaults")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .folderImporter(isPresented: $isPicking, model: model)
            .onChange(of: model.vault?.root) { dismiss() }
        }
        .tint(theme.color(\.accent))
        .onAppear { model.reloadVaults() }
    }

    private func row(_ vault: RememberedVault) -> some View {
        Button {
            if vault.isMissing {
                isPicking = true
            } else if !vault.isOpen {
                Task {
                    await model.switchVault(to: vault)
                    dismiss()
                }
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: vault.isInICloud ? "icloud" : "folder")
                    .scaledFont(size: 22)
                    .foregroundStyle(theme.color(vault.isOpen ? \.done : \.muted))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vault.name).scaledFont(size: 17).foregroundStyle(theme.color(\.fg))
                    Text(vault.isMissing ? "Not found" : vault.location)
                        .scaledFont(size: 13)
                        .foregroundStyle(theme.color(\.muted))
                }
                Spacer()
                if vault.isOpen {
                    Image(systemName: "checkmark").foregroundStyle(theme.color(\.accent))
                }
            }
            .opacity(vault.isMissing ? 0.5 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(vault.isOpen ? .isSelected : [])
    }
}
#endif
