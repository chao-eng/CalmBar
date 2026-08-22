import Foundation

public struct TranslationLanguage: Identifiable, Hashable, Sendable, Codable {
    public let code: String          // e.g. "zh", "en", "yue", "bo"
    public let englishName: String   // e.g. "Chinese", "English", "Cantonese"
    public let chineseName: String   // e.g. "中文", "英语", "粤语"

    public var id: String { code }

    public var displayName: String {
        "\(chineseName) (\(englishName))"
    }

    public init(code: String, englishName: String, chineseName: String) {
        self.code = code
        self.englishName = englishName
        self.chineseName = chineseName
    }

    public static let defaultSource = TranslationLanguage(code: "auto", englishName: "Auto", chineseName: "自动检测")
    public static let defaultTarget = TranslationLanguage(code: "zh", englishName: "Chinese", chineseName: "中文")

    /// 完整的 38 种支持语言列表（严格对齐 HY-MT2 规范）
    public static let supportedLanguages: [TranslationLanguage] = [
        TranslationLanguage(code: "zh", englishName: "Chinese", chineseName: "中文"),
        TranslationLanguage(code: "en", englishName: "English", chineseName: "英语"),
        TranslationLanguage(code: "fr", englishName: "French", chineseName: "法语"),
        TranslationLanguage(code: "pt", englishName: "Portuguese", chineseName: "葡萄牙语"),
        TranslationLanguage(code: "es", englishName: "Spanish", chineseName: "西班牙语"),
        TranslationLanguage(code: "ja", englishName: "Japanese", chineseName: "日语"),
        TranslationLanguage(code: "tr", englishName: "Turkish", chineseName: "土耳其语"),
        TranslationLanguage(code: "ru", englishName: "Russian", chineseName: "俄语"),
        TranslationLanguage(code: "ar", englishName: "Arabic", chineseName: "阿拉伯语"),
        TranslationLanguage(code: "ko", englishName: "Korean", chineseName: "韩语"),
        TranslationLanguage(code: "th", englishName: "Thai", chineseName: "泰语"),
        TranslationLanguage(code: "it", englishName: "Italian", chineseName: "意大利语"),
        TranslationLanguage(code: "de", englishName: "German", chineseName: "德语"),
        TranslationLanguage(code: "vi", englishName: "Vietnamese", chineseName: "越南语"),
        TranslationLanguage(code: "ms", englishName: "Malay", chineseName: "马来语"),
        TranslationLanguage(code: "id", englishName: "Indonesian", chineseName: "印尼语"),
        TranslationLanguage(code: "tl", englishName: "Filipino", chineseName: "菲律宾语"),
        TranslationLanguage(code: "hi", englishName: "Hindi", chineseName: "印地语"),
        TranslationLanguage(code: "zh-Hant", englishName: "Traditional Chinese", chineseName: "繁体中文"),
        TranslationLanguage(code: "pl", englishName: "Polish", chineseName: "波兰语"),
        TranslationLanguage(code: "cs", englishName: "Czech", chineseName: "捷克语"),
        TranslationLanguage(code: "nl", englishName: "Dutch", chineseName: "荷兰语"),
        TranslationLanguage(code: "km", englishName: "Khmer", chineseName: "高棉语"),
        TranslationLanguage(code: "my", englishName: "Burmese", chineseName: "缅甸语"),
        TranslationLanguage(code: "fa", englishName: "Persian", chineseName: "波斯语"),
        TranslationLanguage(code: "gu", englishName: "Gujarati", chineseName: "古吉拉特语"),
        TranslationLanguage(code: "ur", englishName: "Urdu", chineseName: "乌尔都语"),
        TranslationLanguage(code: "te", englishName: "Telugu", chineseName: "泰卢固语"),
        TranslationLanguage(code: "mr", englishName: "Marathi", chineseName: "马拉地语"),
        TranslationLanguage(code: "he", englishName: "Hebrew", chineseName: "希伯来语"),
        TranslationLanguage(code: "bn", englishName: "Bengali", chineseName: "孟加拉语"),
        TranslationLanguage(code: "ta", englishName: "Tamil", chineseName: "泰米尔语"),
        TranslationLanguage(code: "uk", englishName: "Ukrainian", chineseName: "乌克兰语"),
        TranslationLanguage(code: "bo", englishName: "Tibetan", chineseName: "藏语"),
        TranslationLanguage(code: "kk", englishName: "Kazakh", chineseName: "哈萨克语"),
        TranslationLanguage(code: "mn", englishName: "Mongolian", chineseName: "蒙古语"),
        TranslationLanguage(code: "ug", englishName: "Uyghur", chineseName: "维吾尔语"),
        TranslationLanguage(code: "yue", englishName: "Cantonese", chineseName: "粤语")
    ]

    public static func find(byCode code: String) -> TranslationLanguage {
        supportedLanguages.first { $0.code.lowercased() == code.lowercased() } ?? defaultTarget
    }
}
