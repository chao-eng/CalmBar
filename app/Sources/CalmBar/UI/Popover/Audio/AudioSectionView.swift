import SwiftUI

// MARK: - 声音分区骨架（M7 / PRD §5.5，最多 4 行静态应用，不接音频引擎）

struct AudioSectionView: View {
    var isEmpty: Bool = false
    var onMeasure: ((CGFloat) -> Void)?
    var onAction: ((String) -> Void)?

    @State private var rows: [AudioRowStub] = AudioRowStub.defaults

    var body: some View {
        Group {
            if isEmpty {
                PopoverEmptyState(
                    icon: "speaker.slash",
                    title: "暂无应用发声",
                    detail: "播放声音后，这里会按应用列出音量",
                    accessibilityValue: "声音"
                )
            } else {
                VStack(spacing: 6) {
                    VStack(spacing: 6) {
                        ForEach($rows) { $row in
                            audioRow(row: $row)
                        }
                    }

                    Text("最多显示 4 行，更多应用请打开混音窗口")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: PopoverLayout.contentWidth)
                .background {
                    GeometryReader { proxy in
                        Color.clear.onAppear { onMeasure?(proxy.size.height) }
                    }
                }
            }
        }
    }

    private func audioRow(row: Binding<AudioRowStub>) -> some View {
        let value = row.wrappedValue
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(value.accent.opacity(0.14))
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: value.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(value.accent)
                }

            Text(value.appName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                row.wrappedValue.device = value.device == "默认" ? "扬声器" : "默认"
                onAction?("device:\(value.appName)")
            } label: {
                HStack(spacing: 2) {
                    Text(value.device)
                        .font(.system(size: 9))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 78, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(PopoverPalette.surfaceWell)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("切换「\(value.appName)」的输出设备")
            .accessibilityLabel("\(value.appName) 输出设备，\(value.device)")

            Slider(
                value: Binding(
                    get: { Double(row.wrappedValue.volume) },
                    set: { newValue in
                        row.wrappedValue.volume = Int(newValue.rounded())
                        onAction?("volume:\(value.appName):\(Int(newValue.rounded()))")
                    }
                ),
                in: 0...200
            )
            .controlSize(.mini)
            .frame(width: 56)
            .tint(PopoverPalette.audioAccent)
            .accessibilityLabel("\(value.appName) 音量")

            Text("\(value.volume)%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button {
                row.wrappedValue.isMuted.toggle()
                onAction?("mute:\(value.appName)")
            } label: {
                Image(systemName: value.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(value.isMuted ? Color.secondary : Color.primary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(value.isMuted ? "取消静音" : "静音")
            .accessibilityLabel("\(value.appName) 静音")
            .accessibilityValue(value.isMuted ? "已静音" : "未静音")
        }
        .frame(height: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(value.appName) 音量行")
        .accessibilityValue("\(value.volume)%")
    }
}

// MARK: - 静态应用行（不读取真实音频进程）

struct AudioRowStub: Identifiable {
    let id: String
    let appName: String
    let icon: String
    let accent: Color
    var device: String
    var volume: Int
    var isMuted: Bool

    static let defaults: [AudioRowStub] = [
        AudioRowStub(id: "discord", appName: "Discord", icon: "bubble.left.fill", accent: PopoverPalette.accentIndigo, device: "默认", volume: 29, isMuted: false),
        AudioRowStub(id: "music", appName: "Music", icon: "music.note", accent: PopoverPalette.accentPink, device: "默认", volume: 187, isMuted: false),
        AudioRowStub(id: "safari", appName: "Safari", icon: "safari.fill", accent: PopoverPalette.accentBlue, device: "扬声器", volume: 100, isMuted: false),
        AudioRowStub(id: "zoom", appName: "Zoom", icon: "video.fill", accent: PopoverPalette.accentGreen, device: "默认", volume: 75, isMuted: false)
    ]
}
