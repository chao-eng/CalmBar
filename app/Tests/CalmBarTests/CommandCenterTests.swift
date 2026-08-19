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
}
