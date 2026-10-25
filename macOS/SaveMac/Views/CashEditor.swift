// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct CashEditor: View {
    let store: EditorStore
    @State private var amount = "0"
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Geld", systemImage: "dollarsign.circle").fontWeight(.medium)
                Spacer()
                TextField("Betrag", text: $amount).textFieldStyle(.roundedBorder).frame(width: 150)
                Button("Übernehmen") {
                    do {
                        guard let value = Int32(amount) else { throw CashInput.invalid }
                        try store.setCash(value); validation = nil
                    } catch { validation = error.localizedDescription }
                }.disabled(amount == store.cashValue)
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
        }
        .padding()
        .onAppear { amount = store.cashValue }
        .onChange(of: amount) { _, value in store.trackCashDraft(value) }
        .onDisappear { store.cashDrafts.removeValue(forKey: store.profile) }
        .onChange(of: store.draftResetToken) { _, _ in amount = store.cashValue; validation = nil }
        .onChange(of: store.cashValue) { _, value in amount = value }
        .onChange(of: store.profile) { previous, _ in store.cashDrafts.removeValue(forKey: previous); amount = store.cashValue; validation = nil }
        .onChange(of: store.source) { _, _ in amount = store.cashValue; validation = nil }
    }
    private enum CashInput: LocalizedError {
        case invalid
        var errorDescription: String? { "Bitte einen gültigen Geldbetrag eingeben." }
    }
}
