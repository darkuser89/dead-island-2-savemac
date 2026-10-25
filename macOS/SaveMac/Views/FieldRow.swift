// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct FieldRow: View {
    let field: SaveField
    let store: EditorStore
    @State private var draft: String
    @State private var validation: String?

    init(field: SaveField, store: EditorStore) {
        self.field = field
        self.store = store
        _draft = State(initialValue: store.edits[field.id] ?? field.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.title).fontWeight(.medium)
                    Text((field.context ?? "Eintrag \(field.occurrence)") + " · Original: " + field.choiceTitle(field.value))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if field.isReadOnly {
                    Text(field.value).monospacedDigit().foregroundStyle(.secondary)
                } else if field.choices.isEmpty {
                    TextField("Wert", text: $draft)
                        .frame(width: 130).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(field.title + " " + String(field.occurrence))
                        .onSubmit(apply)
                } else {
                    Picker("Seltenheit", selection: $draft) {
                        ForEach(field.choices, id: \.self) { Text(field.choiceTitle($0)).tag($0) }
                    }.labelsHidden().frame(width: 145)
                }
                if !field.isReadOnly { Button("Übernehmen", action: apply)
                    .disabled(draft == (store.edits[field.id] ?? field.value))
                }
                if store.edits[field.id] != nil {
                    Image(systemName: "pencil.circle.fill").foregroundStyle(.orange)
                        .accessibilityLabel("Geändert")
                }
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 6)
        .onChange(of: draft) { _, value in store.trackDraft(field, value: value) }
        .onDisappear { store.removeDraft(field) }
        .onChange(of: store.draftResetToken) { _, _ in draft = store.edits[field.id] ?? field.value; validation = nil }
        .onChange(of: store.edits[field.id]) { _, value in draft = value ?? field.value }
        .onChange(of: field) { previous, updated in
            store.removeDraft(previous)
            draft = store.edits[updated.id] ?? updated.value
            validation = nil
        }
    }

    private func apply() {
        do { try store.change(field, to: draft); validation = nil }
        catch { validation = error.localizedDescription }
    }
}
