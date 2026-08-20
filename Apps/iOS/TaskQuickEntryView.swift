import SwiftUI
import AppDesign
import TaskDomain

struct TaskQuickEntryView: View {
    let placeholder: String
    @Binding var draft: String
    let suggestions: [Task]
    var textFieldIdentifier: String = ""
    var focusOnAppear = false
    let onSubmit: (String) -> Void
    let onSelectSuggestion: (Task) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if isFocused && !suggestions.isEmpty {
                suggestionsView
            }

            HStack(spacing: AppSpacing.s) {
                Image(systemName: AppSymbols.Tasks.add)
                    .foregroundStyle(Color.accentColor)
                    .font(.headline)

                TextField(placeholder, text: $draft)
                    .accessibilityIdentifier(textFieldIdentifier)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(submitDraft)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button {
                                submitDraft()
                            } label: {
                                Label("Add", systemImage: AppSymbols.Tasks.add)
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: AppSymbols.Tasks.add)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "Add Task"))
            }
            .padding(.horizontal, AppSpacing.m)
            .frame(minHeight: 52)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.secondary.opacity(isFocused ? 0.22 : 0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isFocused ? 0.18 : 0.10), radius: isFocused ? 18 : 10, y: 8)
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.top, AppSpacing.s)
        .padding(.bottom, AppSpacing.s)
        .animation(.snappy(duration: AppDuration.normal), value: isFocused)
        .animation(.snappy(duration: AppDuration.normal), value: suggestions.map(\.id))
        .task(id: focusOnAppear) {
            guard focusOnAppear else { return }
            await Swift.Task.yield()
            isFocused = true
        }
    }

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Existing tasks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, AppSpacing.m)

            ForEach(suggestions.prefix(4)) { task in
                Button {
                    isFocused = false
                    onSelectSuggestion(task)
                } label: {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: AppSymbols.Navigation.taskHub)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: AppSpacing.s)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, AppSpacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Use existing task \(task.title)"))
            }
        }
        .padding(.vertical, AppSpacing.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private func submitDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draft = ""
        isFocused = false
        onSubmit(title)
    }
}

#if DEBUG
#Preview("Quick Entry — Empty") {
    TaskQuickEntryPreview(draft: "", suggestions: [])
}

#Preview("Quick Entry — Draft") {
    TaskQuickEntryPreview(draft: "Renew domain", suggestions: [])
}

#Preview("Quick Entry — Suggestions") {
    TaskQuickEntryPreview(
        draft: "Re",
        suggestions: Array(PreviewMocks.samplePool.prefix(3)),
        focusOnAppear: true
    )
}

private struct TaskQuickEntryPreview: View {
    @State var draft: String
    let suggestions: [Task]
    var focusOnAppear = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.secondary.opacity(0.12)
                .ignoresSafeArea()

            TaskQuickEntryView(
                placeholder: "Add or search task",
                draft: $draft,
                suggestions: suggestions,
                focusOnAppear: focusOnAppear,
                onSubmit: { _ in },
                onSelectSuggestion: { _ in }
            )
            .padding(.bottom, AppSpacing.l)
        }
    }
}
#endif
