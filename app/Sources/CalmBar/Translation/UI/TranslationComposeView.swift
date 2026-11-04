import SwiftUI
import AppKit

/// 手动输入原文的翻译面板：从菜单栏工具入口进入时展示，
/// 默认预填剪贴板内容但不自动翻译，用户可编辑后主动发起翻译。
@MainActor
struct TranslationComposeView: View {
    @ObservedObject var controller: TranslationToastWindowController
    let onClose: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTargetLangCode: String
    @FocusState private var isEditorFocused: Bool

    init(controller: TranslationToastWindowController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        self._selectedTargetLangCode = State(initialValue: AppSettings.shared.translationTargetLanguageCode)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
                .background(Color.white.opacity(0.1))
            editorArea
            Divider()
                .background(Color.white.opacity(0.1))
            footerBar
        }
        .frame(minWidth: 460, minHeight: 340)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            // 等待窗口成为 key window 后再聚焦，避免首次输入丢失
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isEditorFocused = true
            }
        }
    }

    private var trimmedDraft: String {
        controller.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .foregroundColor(.blue)
                .font(.system(size: 13, weight: .semibold))

            Text("AI 翻译")
                .font(.system(size: 12, weight: .semibold))

            Text(settings.translationModel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)

            Spacer()

            TranslationLanguagePicker(selectedLanguageCode: $selectedTargetLangCode)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("关闭")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Editor
    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $controller.draftText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .focused($isEditorFocused)

            if controller.draftText.isEmpty {
                Text("输入或粘贴需要翻译的原文…")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.leading, 12)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer
    private var footerBar: some View {
        HStack(spacing: 8) {
            Text("\(controller.draftText.count) 字")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Text("⌘↩ 快速翻译")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))

            Button(action: submit) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("翻译")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(trimmedDraft.isEmpty ? Color.blue.opacity(0.35) : Color.blue)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .disabled(trimmedDraft.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func submit() {
        guard !trimmedDraft.isEmpty else { return }
        let lang = TranslationLanguage.find(byCode: selectedTargetLangCode)
        TranslationManager.shared.translate(text: trimmedDraft, targetLanguage: lang)
    }
}
