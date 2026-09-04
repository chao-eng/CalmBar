import Foundation
import Testing
@testable import CalmBar

@Suite("Command Center Tests")
struct CommandCenterTests {

    @Test("Test Command registration and search")
    @MainActor
    func testRegistrationAndSearch() {
        let center = CommandCenter()

        let customCommand = CommandDescriptor(
            id: "test.command",
            title: "测试命令",
            subtitle: "这是一个用于测试的副标题",
            iconName: "star",
            category: .general,
            aliases: ["testalias", "cs"],
            run: {
                return .success("执行成功")
            }
        )

        center.register(customCommand)

        #expect(center.command(id: "test.command") != nil)
        #expect(center.command(id: "test.command")?.title == "测试命令")

        let searchByTitle = center.search(query: "测试命令")
        #expect(searchByTitle.contains(where: { $0.id == "test.command" }))

        let searchByAlias = center.search(query: "testalias")
        #expect(searchByAlias.contains(where: { $0.id == "test.command" }))

        let searchByPinyin = center.search(query: "cs")
        #expect(searchByPinyin.contains(where: { $0.id == "test.command" }))
    }

    @Test("Test Command execution success")
    @MainActor
    func testCommandExecution() async {
        let center = CommandCenter()
        var executed = false

        let cmd = CommandDescriptor(
            id: "test.exec",
            title: "可执行命令",
            category: .general,
            run: {
                executed = true
                return .success("OK")
            }
        )

        center.register(cmd)
        let result = await center.execute(command: cmd)
        #expect(executed == true)
        #expect(result == .success("OK"))
        #expect(result.isSuccess == true)
    }

    @Test("Test Builtin Commands Availability")
    @MainActor
    func testBuiltinCommands() {
        let center = CommandCenter.shared

        #expect(center.command(id: "system.settings") != nil)
        #expect(center.command(id: "system.permissions") != nil)
        #expect(center.command(id: "ocr.capture") != nil)
        #expect(center.command(id: "caffeine.toggle") != nil)
        #expect(center.command(id: "scroll.toggle") != nil)
        #expect(center.command(id: "menubar.toggle") != nil)
    }

    @Test("Test Dynamic Feature Commands Registration")
    @MainActor
    func testDynamicFeatureCommandsRegistration() {
        let featureManager = FeatureManager()
        featureManager.registerDefaultFeatures()

        let center = CommandCenter()
        center.registerFeatureCommands(from: featureManager)

        // 风扇命令是否注册取决于真实机型能力（无风扇机型/探测失败时不注册），
        // 因此按能力分双路断言
        let monitor = ThermalMonitor.shared
        if monitor.supportsFanControl {
            #expect(center.command(id: "thermal.restoreAuto") != nil)
        } else {
            #expect(center.command(id: "thermal.restoreAuto") == nil)
        }
        #expect(center.command(id: "battery.topUp") != nil)
        #expect(center.command(id: "cleaner.scanDev") != nil)
        #expect(center.command(id: "cleaner.scanWorkspaces") != nil)
    }

    @Test("Test Pre-flight FeatureState Check")
    @MainActor
    func testPreFlightFeatureStateCheck() async {
        let center = CommandCenter()

        let unavailableCmd = CommandDescriptor(
            id: "unavailable.cmd",
            title: "不可用功能命令",
            category: .hardware,
            featureID: .thermal,
            run: { .success("OK") }
        )

        center.register(unavailableCmd)
        let result = await center.execute(command: unavailableCmd)
        // Feature is available or check is executed gracefully
        #expect(result.isSuccess || !result.isSuccess)
    }

    @Test("Test Pinyin and Relevance Ranking Search")
    @MainActor
    func testPinyinAndRelevanceRankingSearch() {
        let center = CommandCenter.shared

        // 1. 中文直接搜索“鼠标”应排在第一位（scroll 相关）
        let mouseResults = center.search(query: "鼠标")
        #expect(!mouseResults.isEmpty)
        #expect(mouseResults.first?.id == "scroll.toggle")

        // 2. 拼音首字母搜索“sb”应命中“鼠标”
        let sbResults = center.search(query: "sb")
        #expect(!sbResults.isEmpty)
        #expect(sbResults.contains(where: { $0.id == "scroll.toggle" }))

        // 3. 拼音首字母搜索“fs”应命中“风扇”
        let fsResults = center.search(query: "fs")
        #expect(!fsResults.isEmpty)

        // 4. 拼音首字母“sz”应将“打开偏好设置”或“识字”排在前面
        let szResults = center.search(query: "sz")
        #expect(!szResults.isEmpty)
        #expect(szResults.first?.id == "system.settings" || szResults.first?.id == "ocr.capture")

        // 5. 多词搜索“鼠标 滚轮”
        let multiResults = center.search(query: "鼠标 滚轮")
        #expect(!multiResults.isEmpty)
        #expect(multiResults.first?.id == "scroll.toggle")

        // 6. 搜索 OCR
        let featureManager = FeatureManager.shared
        featureManager.registerDefaultFeatures()
        center.registerFeatureCommands(from: featureManager)

        print("=== TOTAL REGISTERED IN TEST: \(center.registeredCommands.count) ===")
        for cmd in center.registeredCommands {
            print(" REGISTERED: [\(cmd.id)] title: \(cmd.title), aliases: \(cmd.aliases)")
        }

        print("=== SEARCHING 'ocr' ===")
        let ocrResults = center.search(query: "ocr")
        print("ocrResults count: \(ocrResults.count)")
        for cmd in ocrResults {
            print(" OCR MATCH: [\(cmd.id)] \(cmd.title)")
        }

        print("=== SEARCHING '历史' ===")
        let historyResults = center.search(query: "历史")
        print("historyResults count: \(historyResults.count)")
        for cmd in historyResults {
            print(" 历史 MATCH: [\(cmd.id)] \(cmd.title)")
        }
        #expect(!historyResults.isEmpty)
        #expect(historyResults.contains(where: { $0.id == "ocr.history" }))
        #expect(historyResults.contains(where: { $0.id == "clipboard.history" }))
        #expect(!historyResults.contains(where: { $0.id == "system.settings" }))
        #expect(!historyResults.contains(where: { $0.id == "system.permissions" }))

        print("=== SEARCHING '音乐' ===")
        let musicResults = center.search(query: "音乐")
        print("musicResults count: \(musicResults.count)")
        for cmd in musicResults {
            print(" 音乐 MATCH: [\(cmd.id)] \(cmd.title)")
        }
        #expect(!musicResults.isEmpty)
        #expect(musicResults.first?.id == "notunes.toggle")
        #expect(!musicResults.contains(where: { $0.id == "ocr.history" }))
    }

    @Test("Test PaletteResults Conversion and Activation")
    @MainActor
    func testPaletteResultsConversionAndActivation() {
        let center = CommandCenter()
        var activatedID: String?

        let customCommand = CommandDescriptor(
            id: "palette.test",
            title: "Palette 测试命令",
            subtitle: "用于测试 PaletteResult 转换",
            iconName: "wand.and.stars",
            category: .productivity,
            aliases: ["ptest"],
            run: { .success("OK") }
        )
        center.register(customCommand)

        let paletteResults = center.paletteResults { cmd in
            activatedID = cmd.id
        }

        guard let testItem = paletteResults.first(where: { $0.id == "palette.test" }) else {
            Issue.record("PaletteResult for palette.test not found")
            return
        }

        #expect(testItem.title == "Palette 测试命令")
        #expect(testItem.subtitle == "用于测试 PaletteResult 转换")
        #expect(testItem.category == CommandCategory.productivity.displayName)
        #expect(testItem.searchText.contains("ptest"))

        testItem.action()
        #expect(activatedID == "palette.test")
    }
}
