//
//  MainHeaderView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026-11-24.
//

import SwiftUI
import AppKit

// 主界面顶部原先是一整条三段式 header。按 QQ 音乐那张图重排之后，三块各归各位：
// 用户身份进了左列（和歌单同宽、同一块黑底），搜索框进了右块面板的第一行，
// macSpectrum 字样留在右块右上角。所以这里不再是单个 MainHeaderView，而是三个可独立摆放的零件。

// MARK: - 左列顶部：当前登录用户

/// 系统登录用户的头像 + 全名。宽度由父级给（必须与歌单列同宽，用户要求的）。
struct MainUserCell: View {
    @ObservedObject var palette: PaletteManager

    @State private var avatar: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            avatarView
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            Text(SystemUser.displayName)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .task { avatar = await SystemUser.avatar() }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatar {
            // 系统头像实测 421×421pt，缩到 30pt 是 1/14，交给 AppKit 缩放即可；
            // 但它解码出来是 2MB TIFF，所以只在左列出现一次，别拿它去做逐帧动画。
            Image(nsImage: avatar).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(palette.textSecondary.opacity(0.22))
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.textSecondary)
            }
        }
    }
}

// MARK: - 右块第一行：搜索

/// 搜索框 + 命中下拉。下拉挂在搜索框自己的 overlay 上往下长，
/// ⚠️ 父级必须给这一行 `.zIndex(1)`，否则 VStack 里后声明的歌曲列表会盖住它半截。
struct MainSearchBar: View {
    /// 搜索框与下拉同宽，且都不参与弹性布局 —— 宽度固定，下拉才能用 alignmentGuide 精确贴住。
    static let fieldWidth: CGFloat = 360
    private static let rowHeight: CGFloat = 44
    private static let maxResults = 30
    /// 空框时显的提示文字。title 与 prompt 共用一个串，免改一处漏一处。
    private static let searchTitle = "搜索歌曲、艺术家或专辑"

    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    let allSongs: [Song]
    /// 命中后由父视图执行「选中歌单 → 滚动定位 → 播放」三件套。
    let onPick: (Song) -> Void
    @Binding var query: String

    var body: some View {
        searchField
            .frame(width: Self.fieldWidth)
            .overlay(alignment: .bottom) {
                dropdown.alignmentGuide(.bottom) { d in d[.top] - 6 }
            }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.textSecondary)
            // ⚠️ placeholder 必须走 prompt: 显式给色。不给 prompt 时那层灰字吃的是 NSTextField
            // 的 placeholderTextColor，只跟着**系统外观**走，app 自己那套黑白主题它不理。本机系统外观
            // 是 Dark，于是浅底上画出来的是白字：离屏渲染逐像素量过（NSHostingView + cacheDisplay，
            // ImageRenderer 画不出 NSTextField 不能用），底色亮度 0.957、placeholder 最深也是 0.957，
            // 对比度正好为零 —— 就是用户说的“一直是灰的、白色主题下看不清”。
            // 给 prompt 打 foregroundColor 后同一处量到 0.237。macOS 27 之前若某版 SDK 不采信这个样式，
            // 后果只是退回原来那层浅灰，不会叠字。
            TextField(Self.searchTitle, text: $query,
                      prompt: Text(Self.searchTitle).foregroundColor(palette.textPlaceholder))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(palette.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(fieldSurface, in: Capsule())
        .overlay(Capsule().stroke(hairline, lineWidth: 1))
        // Super Shuffle 期间全库随机，歌单与列表都锁死，搜索框是唯一能「跳出这个模式」的口子，
        // 用户明确要求它也一起禁用。
        .opacity(player.superShuffle ? 0.4 : 1)
        .disabled(player.superShuffle)
        .help(player.superShuffle ? "Super Shuffle 期间不可用" : "")
    }

    @ViewBuilder
    private var dropdown: some View {
        let hits = results
        if !hits.isEmpty {
            ScrollView {
                // 不用 LazyVStack：上限已经卡在 maxResults，lazy 一点收益都没有，
                // 反而在 ImageRenderer 离屏渲染下根本不布行，排出来的下拉是空白的。
                VStack(spacing: 0) {
                    ForEach(hits) { song in
                        resultRow(song)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: Self.fieldWidth,
                   height: min(CGFloat(hits.count) * Self.rowHeight + 8, 320))
            .background(panelSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }

    private func resultRow(_ song: Song) -> some View {
        Button {
            query = ""
            onPick(song)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 11))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.songTitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(song.artist + " · " + song.album)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.rowHeight)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 匹配口径与歌词查找共用 PlaylistLoader.sanitize（小写 + NFC + 去空格），
    /// 这样「搜得到」和「有歌词」不会因为 é 的组合式/预组合式差异而分家。
    private var results: [Song] {
        let needle = PlaylistLoader.sanitize(query)
        guard needle.count >= 2, !player.superShuffle else { return [] }
        var out: [Song] = []
        for song in allSongs {
            let hay = PlaylistLoader.sanitize("\(song.songTitle) \(song.artist) \(song.album)")
            if hay.contains(needle) {
                out.append(song)
                if out.count >= Self.maxResults { break }
            }
        }
        return out
    }

    // MARK: 配色

    /// 下拉面板底色必须写死而且不透明：material 背后是 NSVisualEffectView，只看**系统**外观，
    /// app 自己那套黑白主题它不跟；而它下面就是歌曲列表，半透明会把列表透上来。
    private var panelSurface: Color {
        palette.surface.isLight ? Color.white : Color(white: 0.11)
    }

    private var fieldSurface: Color {
        palette.surface.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.10)
    }

    private var hairline: Color {
        palette.surface.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.14)
    }
}

// MARK: - 右块右上角：macSpectrum 字样

/// 呼吸字样，并接管原来大专辑图上的拖窗手势。
struct SpectrumWordmark: View {
    @ObservedObject var palette: PaletteManager

    // 字样呼吸的三个约束（周期用真实时间而不是 repeatForever、只包住这一个 Text、
    // 幅度 0.60 不摆到纯白）原先在 MainPlayerView，随字样一起搬到这里。
    private let idleBreathPeriod: Double = 6
    private let idleBreathAmplitude: Double = 0.60
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // 余弦而不是三角波：线性往返在两个端点有速度突变，看着像「顿一下」。
            let p = 0.5 - 0.5 * cos(2 * Double.pi * (t / idleBreathPeriod))
            Text("macSpectrum")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(palette.wordmarkColor(phase: p, amplitude: idleBreathAmplitude))
        }
        .fixedSize()
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    // 原写法是 NSApp.currentEvent!，鼠标按下到回调之间理论上可能为 nil，
                    // 这里改成 guard —— 拖窗口拖出个 crash 说不过去。
                    if let event = NSApp.currentEvent {
                        NSApp.keyWindow?.performDrag(with: event)
                    }
                }
        )
        .help("拖动以移动窗口")
    }
}
