import SwiftUI

public struct TranslationLanguagePicker: View {
    @Binding public var selectedLanguageCode: String
    public var onSelect: ((TranslationLanguage) -> Void)?

    @State private var searchText: String = ""

    public init(
        selectedLanguageCode: Binding<String>,
        onSelect: ((TranslationLanguage) -> Void)? = nil
    ) {
        self._selectedLanguageCode = selectedLanguageCode
        self.onSelect = onSelect
    }

    private var currentLanguage: TranslationLanguage {
        TranslationLanguage.find(byCode: selectedLanguageCode)
    }

    public var body: some View {
        Menu {
            ForEach(TranslationLanguage.supportedLanguages) { lang in
                Button(action: {
                    selectedLanguageCode = lang.code
                    onSelect?(lang)
                }) {
                    HStack {
                        Text(lang.displayName)
                        if lang.code.lowercased() == selectedLanguageCode.lowercased() {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentLanguage.chineseName)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .focusEffectDisabled()
    }
}
