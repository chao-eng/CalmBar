import Testing
import Foundation
@testable import CalmBar
@testable import CalmBarKit

@Suite("Translation and 38-Language Integration Tests")
struct TranslationTests {

    @Test("Test supported 38 languages count, codes, and lookups")
    func testSupported38LanguagesCountAndCodes() {
        let languages = TranslationLanguage.supportedLanguages
        #expect(languages.count == 38, "Should support exactly 38 languages")

        let expectedPairs: [(code: String, english: String, chinese: String)] = [
            ("zh", "Chinese", "中文"),
            ("en", "English", "英语"),
            ("ja", "Japanese", "日语"),
            ("ko", "Korean", "韩语"),
            ("zh-Hant", "Traditional Chinese", "繁体中文"),
            ("yue", "Cantonese", "粤语"),
            ("bo", "Tibetan", "藏语"),
            ("ug", "Uyghur", "维吾尔语"),
            ("kk", "Kazakh", "哈萨克语"),
            ("mn", "Mongolian", "蒙古语"),
            ("hi", "Hindi", "印地语")
        ]

        for expected in expectedPairs {
            let found = TranslationLanguage.find(byCode: expected.code)
            #expect(found.code == expected.code)
            #expect(found.englishName == expected.english)
            #expect(found.chineseName == expected.chinese)
        }
    }

    @Test("Test HY-MT2 prompt construction for standard languages")
    func testPromptConstructionStandard() {
        let text = "Hello world"
        let target = TranslationLanguage.find(byCode: "zh")
        let prompt = TranslationService.buildPrompt(text: text, targetLanguage: target)

        #expect(prompt == "Translate the following segment into Chinese, without additional explanation:\n\nHello world")

        let targetTibetan = TranslationLanguage.find(byCode: "bo")
        let promptTibetan = TranslationService.buildPrompt(text: text, targetLanguage: targetTibetan)
        #expect(promptTibetan == "Translate the following segment into Tibetan, without additional explanation:\n\nHello world")
    }

    @Test("Test prompt construction with custom template")
    func testPromptConstructionCustomTemplate() {
        let text = "Sample sentence"
        let target = TranslationLanguage.find(byCode: "yue")
        let template = "【请将以下文本翻译为{targetLanguageZH}({targetLanguage})】:\n{text}"
        let prompt = TranslationService.buildPrompt(text: text, targetLanguage: target, customPromptTemplate: template)

        #expect(prompt == "【请将以下文本翻译为粤语(Cantonese)】:\nSample sentence")
    }

    @Test("Test DoubleCopyDetector consecutive copy matching")
    func testDoubleCopyDetectorSuccess() {
        var detector = ClipboardDoubleCopyDetector(interval: 0.8)

        // 第一次复制
        let firstMatch = detector.registerCopy(of: "Test Text", at: 100.0)
        #expect(!firstMatch)

        // 0.5s 后第二次复制相同文本 -> 触发
        let secondMatch = detector.registerCopy(of: "Test Text", at: 100.5)
        #expect(secondMatch)

        // 触发后重置，紧接着第三次不应直接触发
        let thirdMatch = detector.registerCopy(of: "Test Text", at: 100.6)
        #expect(!thirdMatch)
    }

    @Test("Test DoubleCopyDetector different text prevention")
    func testDoubleCopyDetectorDifferentTextDoesNotTrigger() {
        var detector = ClipboardDoubleCopyDetector(interval: 0.8)

        _ = detector.registerCopy(of: "First Text", at: 100.0)
        let secondMatch = detector.registerCopy(of: "Second Text", at: 100.3)
        #expect(!secondMatch, "Different text in quick succession should not trigger translation")
    }

    @Test("Test DoubleCopyDetector timeout expiration")
    func testDoubleCopyDetectorTimeoutDoesNotTrigger() {
        var detector = ClipboardDoubleCopyDetector(interval: 0.8)

        _ = detector.registerCopy(of: "Test Text", at: 100.0)
        let secondMatch = detector.registerCopy(of: "Test Text", at: 101.5)
        #expect(!secondMatch, "Copying after interval exceeded should not trigger")
    }

    @Test("Test TranslationFeature registration into FeatureManager")
    @MainActor
    func testTranslationFeatureRegistration() {
        let featureManager = FeatureManager.shared
        featureManager.registerDefaultFeatures()

        let translationFeature = featureManager.feature(id: .translation)
        #expect(translationFeature != nil)
        #expect(translationFeature?.title == "AI 划词翻译")
        #expect(translationFeature?.category == .productivity)

        let commands = featureManager.allCommands()
        #expect(commands.contains(where: { $0.id == "translation.clipboard" }))
        #expect(commands.contains(where: { $0.id == "translation.history" }))
    }
}
