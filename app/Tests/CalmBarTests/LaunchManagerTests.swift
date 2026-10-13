import Foundation
import Testing
@testable import CalmBar

@Suite("LaunchManager 模块质量验证测试 (v1.1)")
@MainActor
struct LaunchManagerTests {

    @Test("验证 Feature 基础元信息注册与命令集完整性")
    @MainActor
    func testFeatureMetadata() {
        let feature = LaunchManagerFeature()
        #expect(feature.id == .launchManager)
        #expect(feature.title == "启动项与常驻服务")
        #expect(feature.category == .system)
        #expect(feature.commands.contains { $0.id == "launchManager.open" })
        #expect(feature.commands.contains { $0.id == "launchManager.scanPorts" })
        #expect(feature.commands.contains { $0.id == "launchManager.refresh" })
    }

    @Test("验证 launchctl list 输出字符串解析精度")
    func testLaunchctlListParsing() {
        let sampleOutput = """
        PID\tStatus\tLabel
        1234\t0\tcom.example.running
        -\t0\tcom.example.loaded.stopped
        -\t78\tcom.example.crashed
        """
        let parsed = LaunchctlService.shared.parseListOutputForTesting(sampleOutput)

        #expect(parsed["com.example.running"]?.pid == 1234)
        #expect(parsed["com.example.running"]?.exitCode == 0)
        #expect(parsed["com.example.loaded.stopped"]?.pid == nil)
        #expect(parsed["com.example.loaded.stopped"]?.exitCode == 0)
        #expect(parsed["com.example.crashed"]?.pid == nil)
        #expect(parsed["com.example.crashed"]?.exitCode == 78)
    }

    @Test("验证 print-disabled 禁用集合输出解析")
    func testDisabledLabelsParsing() {
        let sampleOutput = """
        disabled services = {
            "com.apple.coreservices.disabled" => true
            "com.example.myagent" => true
            "com.example.enabled" => false
        }
        """
        let parsed = LaunchctlService.shared.parseDisabledOutputForTesting(sampleOutput)
        #expect(parsed.contains("com.apple.coreservices.disabled"))
        #expect(parsed.contains("com.example.myagent"))
        #expect(!parsed.contains("com.example.enabled"))
    }

    @Test("验证 launchctl print system 输出服务块解析")
    func testPrintSystemParsing() {
        let sampleOutput = """
        system = {
            active service count = 161
            services = {
                     515      - \tcom.crystalidea.macsfancontrol.smcwrite
                       0      - \tcom.apple.lskdd
                       0   (pe) \tcom.apple.kernelmanager_helper
                       0      78 \tcom.example.crashed.daemon
                     518      - \tcom.netease.uuremote.daemon
            }
            disabled services = {
            }
        }
        """
        let parsed = LaunchctlService.shared.parsePrintSystemOutputForTesting(sampleOutput)

        #expect(parsed["com.crystalidea.macsfancontrol.smcwrite"]?.pid == 515)
        #expect(parsed["com.crystalidea.macsfancontrol.smcwrite"]?.exitCode == nil)

        #expect(parsed["com.apple.lskdd"]?.pid == nil)
        #expect(parsed["com.apple.lskdd"]?.exitCode == nil)

        #expect(parsed["com.example.crashed.daemon"]?.pid == nil)
        #expect(parsed["com.example.crashed.daemon"]?.exitCode == 78)

        #expect(parsed["com.netease.uuremote.daemon"]?.pid == 518)
    }

    @Test("验证 KeepAlive 多态策略解析与序列化 (多态策略保护)")
    func testKeepAliveStrategy() {
        // 布尔值解析
        let boolTrue = KeepAliveStrategy.parse(from: true)
        #expect(boolTrue == .always)
        #expect(boolTrue.isEffectivelyActive == true)

        let boolFalse = KeepAliveStrategy.parse(from: false)
        #expect(boolFalse == .disabled)
        #expect(boolFalse.isEffectivelyActive == false)

        // 复杂字典解析
        let dictInput: [String: Any] = ["SuccessfulExit": false, "NetworkState": true]
        let strategy = KeepAliveStrategy.parse(from: dictInput)
        #expect(strategy.isEffectivelyActive == true)
        if case .conditional(let conds) = strategy {
            #expect(conds["SuccessfulExit"] == "false")
            #expect(conds["NetworkState"] == "true")
        } else {
            Issue.record("应当成功解析为 .conditional")
        }
    }

    @Test("验证复杂 KeepAlive 策略及 Crash-Looping 判定阈值 (BR-LM-02)")
    func testCrashLoopDetectionWithStrategy() {
        // 1. 定时任务 (KeepAlive 为 disabled，仅依靠 startInterval)，退出码非 0 也不算死循环
        let cronItem = LaunchItem(
            label: "test.cron",
            plistURL: URL(fileURLWithPath: "/tmp/cron.plist"),
            scope: .userAgent,
            programArguments: ["/bin/sync"],
            runAtLoad: false,
            keepAlive: .disabled,
            startInterval: 300,
            watchPaths: [],
            isLoaded: true,
            isDisabledByOverride: false,
            pid: nil,
            lastExitCode: 1,
            crashCountWithinWindow: 5
        )
        #expect(!cronItem.isCrashLooping(alertThreshold: 3))

        // 2. 常驻守护任务，未达到连续崩溃阈值
        let transientFailingItem = LaunchItem(
            label: "test.transient",
            plistURL: URL(fileURLWithPath: "/tmp/loop.plist"),
            scope: .userAgent,
            programArguments: ["/bin/service"],
            runAtLoad: true,
            keepAlive: .always,
            isLoaded: true,
            pid: nil,
            lastExitCode: 78,
            crashCountWithinWindow: 2
        )
        #expect(!transientFailingItem.isCrashLooping(alertThreshold: 3))

        // 3. 常驻守护任务，达到连续崩溃阈值 3 次
        let loopingItem = LaunchItem(
            label: "test.looping",
            plistURL: URL(fileURLWithPath: "/tmp/loop.plist"),
            scope: .userAgent,
            programArguments: ["/bin/bad_server"],
            runAtLoad: true,
            keepAlive: .always,
            isLoaded: true,
            pid: nil,
            lastExitCode: 78,
            crashCountWithinWindow: 3
        )
        #expect(loopingItem.isCrashLooping(alertThreshold: 3))

        // 4. 正在运行中的任务，即使有旧崩溃计数也不算 CrashLooping
        let runningItem = LaunchItem(
            label: "test.running",
            plistURL: URL(fileURLWithPath: "/tmp/loop.plist"),
            scope: .userAgent,
            programArguments: ["/bin/server"],
            runAtLoad: true,
            keepAlive: .always,
            isLoaded: true,
            pid: 9999,
            lastExitCode: 0,
            crashCountWithinWindow: 5
        )
        #expect(!runningItem.isCrashLooping(alertThreshold: 3))
    }

    @Test("验证系统只读目录防护拦截 (BR-LM-07)")
    @MainActor
    func testSystemProtectionBarrier() async {
        let protectedItem = LaunchItem(
            label: "com.apple.coreservices.test",
            plistURL: URL(fileURLWithPath: "/System/Library/LaunchAgents/test.plist"),
            scope: .appleSystem,
            programArguments: [],
            runAtLoad: false,
            keepAlive: .disabled,
            isLoaded: true
        )

        await #expect(throws: LaunchServiceError.systemProtected) {
            try await LaunchctlService.shared.reloadAtomic(item: protectedItem)
        }

        await #expect(throws: LaunchServiceError.systemProtected) {
            try await LaunchctlService.shared.bootstrap(protectedItem.plistURL, scope: .appleSystem)
        }
    }

    @Test("验证 Plist 原子写入与未知 Key 保留机制 (BR-LM-05)")
    @MainActor
    func testAtomicPlistWriting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchManagerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistURL = tempDir.appendingPathComponent("test.service.plist")
        let initialDict: [String: Any] = [
            "Label": "test.service",
            "ProgramArguments": ["/bin/echo", "hello"],
            "RunAtLoad": true,
            "MachServices": ["com.example.mach": true], // 未知专有 Key
            "ThrottleInterval": 10 // 未知 Key
        ]

        try LaunchPlistService.shared.writeDictionary(initialDict, to: plistURL)
        #expect(FileManager.default.fileExists(atPath: plistURL.path))

        let readBack = try LaunchPlistService.shared.readDictionary(from: plistURL)
        #expect(readBack["Label"] as? String == "test.service")
        #expect(readBack["ThrottleInterval"] as? Int == 10)
        #expect((readBack["MachServices"] as? [String: Any])?["com.example.mach"] as? Bool == true)
    }

    @Test("验证 Shell 参数转义防命令注入")
    func testShellEscaping() {
        let normal = "/Users/test/Library/LaunchAgents/a.plist"
        #expect(LaunchPrivilegeService.escapeShellArg(normal) == "'/Users/test/Library/LaunchAgents/a.plist'")

        let withSpaces = "/Users/test user/My Plist.plist"
        #expect(LaunchPrivilegeService.escapeShellArg(withSpaces) == "'/Users/test user/My Plist.plist'")

        let withQuotes = "/Users/test/O'Reilly's App.plist"
        #expect(LaunchPrivilegeService.escapeShellArg(withQuotes) == "'/Users/test/O'\\''Reilly'\\''s App.plist'")
    }

    @Test("验证备份创建与一键还原机制")
    @MainActor
    func testBackupService() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourcePlist = tempDir.appendingPathComponent("com.test.backup.plist")
        let dict: [String: Any] = ["Label": "com.test.backup", "RunAtLoad": true]
        try LaunchPlistService.shared.writeDictionary(dict, to: sourcePlist)

        let backupURL = try LaunchBackupService.shared.createBackup(of: sourcePlist, label: "com.test.backup")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        let backups = LaunchBackupService.shared.listBackups()
        #expect(backups.contains { $0.label == "com.test.backup" })

        // 清理刚刚测试创建的备份
        try LaunchBackupService.shared.deleteBackup(backupURL)
    }

    @Test("验证 Crontab 表达式解析与序列化")
    func testCrontabParsing() {
        let sample = """
        # 用户定时备份
        0 2 * * * /usr/local/bin/backup.sh
        # 10 3 * * 1 /usr/bin/weekly_cleanup
        */5 * * * * /usr/bin/python3 /script.py
        """
        let lines = CrontabService.shared.parseLines(sample, scope: .user)
        let jobs = lines.compactMap { line -> CronJob? in
            if case .job(let j) = line { return j }
            return nil
        }

        #expect(jobs.count == 3)
        #expect(jobs[0].isEnabled == true)
        #expect(jobs[0].cronExpression == "0 2 * * *")
        #expect(jobs[0].command == "/usr/local/bin/backup.sh")
        #expect(jobs[0].scheduleDescription == "每天 02:00 执行")

        // 验证带 # 的注释停用任务
        #expect(jobs[1].isEnabled == false)
        #expect(jobs[1].cronExpression == "10 3 * * 1")
        #expect(jobs[1].scheduleDescription == "每周一 03:10 执行")

        #expect(jobs[2].isEnabled == true)
        #expect(jobs[2].scheduleDescription == "每 5 分钟执行一次")

        let serialized = CrontabService.shared.serialize(lines: lines, scope: .user)
        #expect(serialized.contains("0 2 * * * /usr/local/bin/backup.sh"))
        #expect(serialized.contains("# 10 3 * * 1 /usr/bin/weekly_cleanup"))
    }

    @Test("验证多行 Shell 脚本自动安全扁平化为单行 Crontab 命令")
    func testCrontabMultilineNormalization() {
        let multiScript = """
        if [ -e /usr/libexec/PlistBuddy ]; then
            /usr/libexec/PlistBuddy -c "Delete :014BF4EC24C114BEF46E1587042B3619" ~/Library/Preferences/com.navicat.NavicatPremium.plist 2>/dev/null || true;
            /usr/libexec/PlistBuddy -c "Delete :91F6C435D172C8163E0689D3DAD3F3E9" ~/Library/Preferences/com.navicat.NavicatPremium.plist 2>/dev/null || true;
            /usr/libexec/PlistBuddy -c "Delete :B966DBD409B87EF577C9BBF3363E9614" ~/Library/Preferences/com.navicat.NavicatPremium.plist 2>/dev/null || true;
        fi;
        if [ -d ~/Library/Application\\ Support/PremiumSoft\\ CyberTech/Navicat\\ CC/Navicat\\ Premium ]; then
            rm -rf ~/Library/Application\\ Support/PremiumSoft\\ CyberTech/Navicat\\ CC/Navicat\\ Premium/.* 2>/dev/null || true;
        fi;
        """

        let normalized = CrontabService.normalizeCommandForCrontab(multiScript)
        #expect(!normalized.contains("\n"))
        #expect(normalized.contains("if [ -e /usr/libexec/PlistBuddy ]; then"))
        #expect(normalized.contains("fi; if [ -d"))
        #expect(!normalized.contains("; ;"))

        // 单行命令保持原样
        let singleLine = "/usr/local/bin/python3 /Users/me/backup.py"
        #expect(CrontabService.normalizeCommandForCrontab(singleLine) == singleLine)

        // 包含注释和空行的脚本应剔除注释和空行
        let scriptWithComments = """
        # 清理临时文件
        rm -rf /tmp/test1
        # 清理日志
        rm -rf /tmp/test2
        """
        let normComments = CrontabService.normalizeCommandForCrontab(scriptWithComments)
        #expect(!normComments.contains("#"))
        #expect(normComments == "rm -rf /tmp/test1; rm -rf /tmp/test2")
    }

    @Test("验证快捷命令面板中的 Crontab 快捷命令注册与搜索")
    @MainActor
    func testCrontabCommandPaletteRegistration() {
        let center = CommandCenter.shared
        let cmd = center.command(id: "launchManager.crontab")
        #expect(cmd != nil)
        #expect(cmd?.title == "Crontab 计划任务")
        #expect(cmd?.iconName == "clock")

        // 验证关键词搜索 (中文、拼音、别名)
        let resultsByZh = center.search(query: "计划任务")
        #expect(resultsByZh.contains { $0.id == "launchManager.crontab" })

        let resultsByCron = center.search(query: "cron")
        #expect(resultsByCron.contains { $0.id == "launchManager.crontab" })

        let resultsByPinyin = center.search(query: "jhrw")
        #expect(resultsByPinyin.contains { $0.id == "launchManager.crontab" })
    }
}
