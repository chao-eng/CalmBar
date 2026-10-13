import SwiftUI

public struct CrontabManagementView: View {
    @ObservedObject private var manager = LaunchManager.shared
    @State private var searchQuery: String = ""
    @State private var selectedScope: CrontabScopeFilter = .all
    @State private var showNewJobSheet: Bool = false
    @State private var jobToDelete: CronJob? = nil

    public init() {}

    private enum CrontabScopeFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case user = "用户级"
        case system = "系统级"

        var id: String { rawValue }
    }

    private var filteredJobs: [CronJob] {
        var list = manager.cronJobs

        switch selectedScope {
        case .all: break
        case .user: list = list.filter { $0.scope == .user }
        case .system: list = list.filter { $0.scope == .system }
        }

        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter {
                $0.command.lowercased().contains(q) ||
                $0.cronExpression.lowercased().contains(q) ||
                $0.scheduleDescription.lowercased().contains(q)
            }
        }

        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索计划表达式或命令...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 240)

                // Scope Filter
                Picker("", selection: $selectedScope) {
                    ForEach(CrontabScopeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Button {
                    showNewJobSheet = true
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    manager.refreshCrontab()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(.ultraThinMaterial)

            Divider()

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
                Text("Crontab 是类 Unix 系统传统的周期性任务调度器。用户任务通过 crontab -l 维护，系统任务受 /etc/crontab 约束。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Content
            if filteredJobs.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("暂无 Crontab 计划任务")
                        .font(.system(size: 14, weight: .medium))
                    Text("点击右上角「新建任务」即可为当前用户添加计划指令")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredJobs) { job in
                        cronJobRow(job: job)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showNewJobSheet) {
            NewCronJobSheetView(
                onDismiss: { showNewJobSheet = false },
                onCreated: { newJob in
                    showNewJobSheet = false
                    Task { await manager.addCronJob(newJob) }
                }
            )
        }
        .confirmationDialog(
            "确认删除该定时任务？",
            isPresented: Binding(
                get: { jobToDelete != nil },
                set: { if !$0 { jobToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认删除", role: .destructive) {
                if let target = jobToDelete {
                    Task { await manager.deleteCronJob(target) }
                    jobToDelete = nil
                }
            }
            Button("取消", role: .cancel) {
                jobToDelete = nil
            }
        } message: {
            if let target = jobToDelete {
                Text("确定删除计划任务吗？\n\n表达式: \(target.cronExpression)\n命令: \(target.command)")
            }
        }
        .alert(
            "Crontab 操作失败",
            isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { manager.errorMessage = nil }
        } message: {
            if let msg = manager.errorMessage {
                Text(msg)
            }
        }
    }

    private func cronJobRow(job: CronJob) -> some View {
        HStack(spacing: 12) {
            // Status Circle
            Circle()
                .fill(job.isEnabled ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    // Scope Badge
                    Text(job.scope == .user ? "用户级" : "系统级")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(job.scope == .user ? .blue : .purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((job.scope == .user ? Color.blue : Color.purple).opacity(0.12))
                        .cornerRadius(4)

                    // Cron expression
                    Text(job.cronExpression)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))

                    // Human-readable schedule
                    Text("·  \(job.scheduleDescription)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let user = job.runAsUser {
                        Text("运行者: \(user)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if job.scope == .system {
                        HStack(spacing: 2) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 9))
                            Text("管理员权限")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.purple)
                    }
                }

                // Command
                Text(job.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Actions
            Toggle("", isOn: Binding(
                get: { job.isEnabled },
                set: { _ in Task { await manager.toggleCronJob(job) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(job.isEnabled ? "点击停用该定时任务" : "点击启用该定时任务")

            Button(role: .destructive) {
                jobToDelete = job
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("删除该定时任务")
        }
        .padding(.vertical, 4)
    }
}

public struct NewCronJobSheetView: View {
    public let onDismiss: () -> Void
    public let onCreated: (CronJob) -> Void

    @State private var scope: CrontabScope = .user
    @State private var runAsUser: String = "root"
    @State private var minute: String = "0"
    @State private var hour: String = "2"
    @State private var dayOfMonth: String = "*"
    @State private var month: String = "*"
    @State private var weekday: String = "*"
    @State private var command: String = ""
    @State private var presetSelection: String = "daily2am"

    public init(onDismiss: @escaping () -> Void, onCreated: @escaping (CronJob) -> Void) {
        self.onDismiss = onDismiss
        self.onCreated = onCreated
    }

    private var previewSchedule: String {
        CronScheduleDescriber.describe(
            minute: minute,
            hour: hour,
            dayOfMonth: dayOfMonth,
            month: month,
            weekday: weekday
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("新建 Crontab 计划任务")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(14)
            .background(.ultraThinMaterial)

            Divider()

            Form {
                Section("任务级别与执行身份") {
                    Picker("任务级别", selection: $scope) {
                        Text("当前用户任务 (crontab)").tag(CrontabScope.user)
                        Text("系统全局任务 (/etc/crontab)").tag(CrontabScope.system)
                    }
                    .pickerStyle(.segmented)

                    if scope == .system {
                        HStack {
                            Text("执行身份 (用户):")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            TextField("例如 root", text: $runAsUser)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 140)
                            Spacer()
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 10))
                                .foregroundStyle(.purple)
                            Text("系统级任务保存时将弹出授权窗口提权写入 /etc/crontab")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("快捷预设") {
                    Picker("常用频次", selection: $presetSelection) {
                        Text("每天凌晨 02:00 (0 2 * * *)").tag("daily2am")
                        Text("每 5 分钟 (*/5 * * * *)").tag("every5min")
                        Text("每小时整点 (0 * * * *)").tag("hourly")
                        Text("每周日凌晨 03:00 (0 3 * * 0)").tag("weekly")
                        Text("自定义").tag("custom")
                    }
                    .onChange(of: presetSelection) { _, val in
                        switch val {
                        case "every5min": minute = "*/5"; hour = "*"; dayOfMonth = "*"; month = "*"; weekday = "*"
                        case "hourly": minute = "0"; hour = "*"; dayOfMonth = "*"; month = "*"; weekday = "*"
                        case "daily2am": minute = "0"; hour = "2"; dayOfMonth = "*"; month = "*"; weekday = "*"
                        case "weekly": minute = "0"; hour = "3"; dayOfMonth = "*"; month = "*"; weekday = "0"
                        default: break
                        }
                    }
                }

                Section("计划表达式 (分 时 日 月 周)") {
                    HStack(spacing: 8) {
                        fieldBox(title: "分", text: $minute)
                        fieldBox(title: "时", text: $hour)
                        fieldBox(title: "日", text: $dayOfMonth)
                        fieldBox(title: "月", text: $month)
                        fieldBox(title: "周", text: $weekday)
                    }

                    HStack {
                        Text("自然语义解析：")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(previewSchedule)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .padding(.top, 4)
                }

                Section("执行命令") {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            if command.isEmpty {
                                Text("输入要周期性执行的命令或 Shell 脚本，例如:\nif [ -e /path/to/app ]; then ... fi")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                                    .padding(8)
                            }
                            TextEditor(text: $command)
                                .font(.system(size: 11, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .frame(minHeight: 85, maxHeight: 140)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(6)

                        Text("支持多行 Shell 脚本，系统将自动安全合并为符合 POSIX 规范的单行 Crontab 命令")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("取消") { onDismiss() }
                    .focusable(false)
                Spacer()
                Button("创建计划任务") {
                    let normalizedCmd = CrontabService.normalizeCommandForCrontab(command)
                    let effectiveUser = runAsUser.trimmingCharacters(in: .whitespaces).isEmpty ? "root" : runAsUser.trimmingCharacters(in: .whitespaces)
                    let job = CronJob(
                        scope: scope,
                        minute: minute.trimmingCharacters(in: .whitespaces),
                        hour: hour.trimmingCharacters(in: .whitespaces),
                        dayOfMonth: dayOfMonth.trimmingCharacters(in: .whitespaces),
                        month: month.trimmingCharacters(in: .whitespaces),
                        weekday: weekday.trimmingCharacters(in: .whitespaces),
                        runAsUser: scope == .system ? effectiveUser : nil,
                        command: normalizedCmd,
                        isEnabled: true
                    )
                    onCreated(job)
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .frame(width: 530, height: 530)
    }

    private func fieldBox(title: String, text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }
}
