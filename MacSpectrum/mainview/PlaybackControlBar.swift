//
//  PlaybackControlBar.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/23.
//

import SwiftUI
import AppKit

/// 光柱下方的常驻播控条（正在播放页）。
///
/// 双行居中：第一行 ⏮ ⏯ ⏭，第二行 `03:45 ────●──── 05:57`。
/// 左侧「回主界面 + 封面 + 歌手 - 歌名」与右侧「歌单」按钮**垂直对齐在两行的中线上**——
/// 所以骨架用的是「居中列 + leading/trailing overlay」，不是 HStack + Spacer：
/// 后者会让中间那两行随歌名长短左右漂移，而播控区必须钉在窗口中轴上。
struct PlaybackControlBar: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    
    /// 只有 trailingControl == .playlist 时才用得上，主界面换成开关后不需要传。
    var onTogglePlaylist: () -> Void = {}
    /// nil 就不画左上角那个「回主界面」按钮。主视图本来就在主界面，没东西可退。
    var onExit: (() -> Void)? = nil
    /// 点封面。主视图拿它跳正在播放页；不传就是普通图片，不可点。
    var onAlbumTap: (() -> Void)? = nil
    /// 右组摆什么。正在播放页要歌单胶囊，主视图要 Super Shuffle 开关。
    var trailingControl: TrailingControl = .playlist
    /// 顶部那条 1px 分隔线。正在播放页要用（它把光柱和播控条切开），主视图的播控条是独立
    /// 圆角面板、上方已经有呼吸空间，画一条反而像表格线，所以由调用方决定。
    var showsTopDivider: Bool = true
    /// 要不要自己铺底色。主视图在外层给了随专辑变化的圆角面板底，组件再叠一层
    /// `Color.black.opacity(0.22)` 就会把面板和控制条涂成两种灰，此时传 false。
    var drawsSurface: Bool = true
    
    enum TrailingControl {
        case playlist
        case superShuffle
    }
    
    // 🖱️ 拖拽期间的临时状态：抬手才 seek，过程中只显示预览。
    // seek 内部是 playerNode.stop() + scheduleSegment + play()，逐帧触发会碎成爆音。
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var isHoveringTrack = false
    
    /// 条高：留白 11×2 + 按钮行 34 + 行距 8 + 进度行 14 = 78
    static let height: CGFloat = 78
    /// 进度线宽度。居中列总宽 = 本值 + 2×40 时间 + 2×12 间距 = 424，
    /// 它同决定了左组能长到多大（见 body 里的 leftBudget）。
    private let trackWidth: CGFloat = 320
    private let timeFieldWidth: CGFloat = 40
    /// 左右两组到窗口边缘的距离，以及它们与居中列之间必须留的空白。
    private let groupPadding: CGFloat = 16
    private let groupGap: CGFloat = 20
    
    /// 居中列（两行里更宽的那个）的实际宽度，用来算左组的可用宽。
    private var centerColumnWidth: CGFloat {
        trackWidth + 2 * timeFieldWidth + 2 * 12
    }
    
    var body: some View {
        GeometryReader { geo in
            // 左组可用宽 = 居中列左边界 − 左边距 − 呼吸间隙。窗口越宽歌名显示得越多；
            // 不够时由歌名自己 middle 截断，歌手名靠 layoutPriority 保住。
            // 1100 宽时给到 208，1300 给到 308，1600 给到 458。
            let leftBudget = max(120, (geo.size.width - centerColumnWidth) / 2
                                    - groupPadding - groupGap)
            
            centerColumn
                .frame(width: geo.size.width, height: Self.height)
                .background(drawsSurface ? surface : Color.clear)
                .overlay(alignment: .top) {
                    if showsTopDivider {
                        Rectangle().fill(hairline).frame(height: 1)
                    }
                }
                .overlay(alignment: .leading) {
                    albumMeta
                        .frame(maxWidth: leftBudget, alignment: .leading)
                        .padding(.leading, groupPadding)
                }
                .overlay(alignment: .trailing) {
                    trailingGroup.padding(.trailing, groupPadding)
                }
        }
        .frame(height: Self.height)
    }
    
    // MARK: - 居中两行
    
    private var centerColumn: some View {
        VStack(spacing: 8) {
            transportRow
            scrubRow
        }
    }
    
    private var transportRow: some View {
        HStack(spacing: 34) {
            Button(action: { player.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17))
            }
            Button(action: { player.isPlaying ? player.pause() : player.resume() }) {
                playPauseButton
            }
            Button(action: { player.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17))
            }
        }
        // macOS 默认 ButtonStyle 是 bordered，会带一圈浅色背景。
        .buttonStyle(.plain)
        .foregroundColor(ink)
        .frame(height: 34)
    }
    
    /// 中间那颗：底色用当前专辑主色。
    ///
    /// 不直接给 `play.circle.fill` 上 foregroundColor：实测单色下圆盘内部的双杠既不是纯白也不是透明
    /// （ImageRenderer 出来既找不到 r/g/b>0.9 的像素、也找不到 alpha≈0 的像素），而是随 symbol 层级
    /// 变化的暗色。底色换成专辑色之后这个颜色不再受控，所以自己拼 ZStack，把符号颜色锁死。
    private var playPauseButton: some View {
        ZStack {
            Circle().fill(accent)
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(transportSymbolInk)
                // 实测 play.fill 的 bbox 本来就正好居中（34 圆里中心落在 17.0），这里 +1 是故意的
                // 视觉修正：三角形质量偏左，不给这一点会看着往左倒。觉得过了就调回 0。
                .offset(x: player.isPlaying ? 0 : 1)
        }
        .frame(width: 34, height: 34)
    }
    
    /// 专辑色可能很亮（浅色专辑、autopilot 混色），符号取黑取白由 WCAG 对比度直接比出来，
    /// 不拍一个经验阈值。
    private var transportSymbolInk: Color {
        let hsb = ThemeColorEngine.hsb(of: accent)
        let rgb = ThemeColorEngine.rgb(hue: hsb.h, sat: hsb.s, bri: hsb.b)
        let lum = ThemeColorEngine.luminance(r: rgb.r, g: rgb.g, b: rgb.b)
        return ThemeColorEngine.contrast(lum, 1.0) >= ThemeColorEngine.contrast(lum, 0.0) ? .white : .black
    }
    
    private var scrubRow: some View {
        HStack(spacing: 12) {
            Text(mmss(displayTime))
                .frame(width: timeFieldWidth, alignment: .trailing)
            
            progressTrack
                .frame(width: trackWidth)
            
            Text(mmss(player.totalDuration))
                .frame(width: timeFieldWidth, alignment: .leading)
        }
        // ⏱️ currentTime 是 10Hz 在跳的，等宽数字防止时间列宽度抽动。
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundColor(secondaryInk)
        .frame(height: 14)
    }
    
    /// 可见线只有 3px，命中区垫到整行 14px 高，否则拖不准。
    private var progressTrack: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let x = CGFloat(currentFraction) * w
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackBackground)
                    .frame(height: isHoveringTrack ? 4 : 3)
                
                Capsule()
                    .fill(accent)
                    .frame(width: max(x, 0), height: isHoveringTrack ? 4 : 3)
                
                Circle()
                    .fill(accent)
                    .frame(width: isHoveringTrack ? 11 : 9, height: isHoveringTrack ? 11 : 9)
                    .shadow(color: accent.opacity(isHoveringTrack ? 0.55 : 0), radius: 3)
                    .offset(x: x - CGFloat(isHoveringTrack ? 5.5 : 4.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        scrubFraction = clampFraction(value.location.x / w)
                    }
                    .onEnded { value in
                        let fraction = clampFraction(value.location.x / w)
                        if player.totalDuration > 0 {
                            player.seek(to: Double(fraction) * player.totalDuration)
                        }
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 14)
        .onHover { isHoveringTrack = $0 }
    }
    
    // MARK: - 左右两组
    
    private var albumMeta: some View {
        // 回主界面与封面之间原本只留 10，两个图标看上去粘在一起，拉到 16。
        HStack(spacing: 16) {
            if let onExit {
                Button(action: onExit) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(secondaryInk)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("回主界面")
            }
            
            // 封面：主视图里它是进正在播放页的唯一入口（大专辑图那一列已经删了）。
            // 用 Button 包而不是 onTapGesture：前者自带键盘可达性与焦点环，
            // 一个能点的图标用点击手势做的话，Tab 键是走不到它的。
            albumThumb
                .modifier(OptionalTap(onTap: onAlbumTap))
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            titleLine
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
    }
    
    @ViewBuilder
    private var albumThumb: some View {
        if let img = player.nowAlbum {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Image("Albumdefault").resizable().aspectRatio(contentMode: .fill)
        }
    }
    
    /// 一行显示「歌名 - 歌手」，歌手段压暗，让歌名成为视觉主体。
    ///
    /// 不用 `Text + Text`（macOS 26 已废弃）而是 HStack 拼。
    /// 这里不再写任何上限：宽度由 body 里的 leftBudget 统一给；歌名靠 layoutPriority 差异先被截断，
    /// 歌手自己超长时才 tail 截断，不会顶穿居中列。
    ///
    /// ⚠️ 两个都已经逐像素坐实的坑：
    /// ① 歌名**绝对不能加 `.frame(maxWidth: .infinity)`**：那会把歌名撑成一个占满预算的盒子，
    ///    歌手名被推到最右端，歌名与歌手之间拉出一道空白（离屏探针：正常长歌名下左组墨迹
    ///    仍然顶满 316，与超长歌名完全同宽，就是这个现象）。
    /// ② 歌手那个 box 若限宽只能用 `alignment: .leading`；写 .trailing 会把短歌手名推到盒子右端。
    private var titleLine: some View {
        let parts = titleComponents
        return HStack(spacing: 0) {
            Text(parts.title)
                .foregroundColor(ink)
                .lineLimit(1)
                .truncationMode(.middle)
            if let artist = parts.artist {
                Text(" - " + artist)
                    .foregroundColor(secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
        .lineLimit(1)
    }
    
    @ViewBuilder
    private var trailingGroup: some View {
        switch trailingControl {
            case .playlist: playlistChip
            case .superShuffle: superShuffleSwitch
        }
    }
    
    /// Super Shuffle 开关。走 setSuperShuffle 而不是直接改标志位：
    /// 打开要停当前歌并随机拉起、关闭要还原旧队列，这些都是副作用，
    /// 绑定到一个纯 setter 上才能保证开关两边行为对称。
    private var superShuffleSwitch: some View {
        Button { player.setSuperShuffle(!player.superShuffle) } label: {
            HStack(spacing: 8) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Super Shuffle")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                switchGlyph(on: player.superShuffle)
            }
            .foregroundColor(player.superShuffle ? ink : secondaryInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                Capsule().stroke(player.superShuffle ? accent.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("全库随机：打开后所有歌单合并成一个大池子随机播放，歌单与歌曲列表同时锁定")
    }
    
    /// 开关的胶囊本身。⚠️ 不能用 `Toggle().toggleStyle(.switch)`：那是 NSSwitch，
    /// 轨道与滑块取的是**系统外观**的色，跟 material 同一个坑（黑主题下系统若是 Light
    /// 就会串出一块浅色轨道）。本项目所有表面色都是显式给的，这里也自己画。
    private func switchGlyph(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? accent : trackBackground)
                .frame(width: 30, height: 16)
            Circle()
                .fill(on ? .white : secondaryInk)
                .frame(width: 12, height: 12)
                .padding(.horizontal, 2)
        }
        .animation(.easeInOut(duration: 0.18), value: on)
        .accessibilityElement()
        .accessibilityLabel("Super Shuffle")
        .accessibilityValue(on ? "开启" : "关闭")
    }
    
    /// Song.title 就是去掉扩展名的文件名（PlaylistLoader 从不读 ID3），
    /// 所以「歌手」只能按文件名里的第一个 " - " 拆出来；拆不到就只显示整串。
    private var titleComponents: (artist: String?, title: String) {
        let raw = player.currentSong?.title ?? "未在播放"
        guard let range = raw.range(of: " - ") else { return (nil, raw) }
        let artist = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let title = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return (nil, raw) }
        return (artist, title)
    }
    
    private var playlistChip: some View {
        Button(action: onTogglePlaylist) {
            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 13, weight: .medium))
                Text("歌单")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(chipSurface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 数值与配色
    
    /// 拖动期间跟手指，否则跟真实播放头。
    private var currentFraction: Double {
        clampFraction(displayTime / max(player.totalDuration, 0.001))
    }
    
    private var displayTime: Double {
        isScrubbing ? scrubFraction * player.totalDuration : player.currentTime
    }
    
    private func clampFraction(_ value: Double) -> Double {
        min(max(value.isNaN ? 0 : value, 0), 1)
    }
    
    private func mmss(_ time: Double) -> String {
        let seconds = Int(max(time.isFinite ? time : 0, 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    
    private var isLightSurface: Bool { palette.surface.isLight }
    
    /// 主题色只上进度条（填充 + 圆点），其余保持中性，避免整条被专辑色糊满。
    private var accent: Color { palette.bgPalette }
    
    private var ink: Color { isLightSurface ? .black : .white }
    
    private var secondaryInk: Color {
        isLightSurface ? Color.black.opacity(0.55) : Color.white.opacity(0.6)
    }
    
    private var surface: Color {
        isLightSurface ? Color.black.opacity(0.028) : Color.black.opacity(0.22)
    }
    
    private var chipSurface: Color {
        isLightSurface ? Color.white.opacity(0.86) : Color.white.opacity(0.14)
    }
    
    private var hairline: Color {
        isLightSurface ? Color.black.opacity(0.10) : Color.white.opacity(0.16)
    }
    
    private var trackBackground: Color {
        isLightSurface ? Color.black.opacity(0.14) : Color.white.opacity(0.20)
    }
}

/// 有回调才套 Button，没回调就原样返回。同一个开关在两个页面能共用一套调用点：
/// 正在播放页不传 onAlbumTap，封面就只是一张图。
private struct OptionalTap: ViewModifier {
    var onTap: (() -> Void)?
    
    func body(content: Content) -> some View {
        if let onTap {
            Button(action: onTap) {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}
