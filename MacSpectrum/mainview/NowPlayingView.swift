//
//  NowPlayingView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/16.
//

import SwiftUI
import Combine
import AppKit

/// 「正在播放」全屏视图：
/// 上半部分 = 左侧滚动歌词 + 右上角黑胶唱片式旋转专辑图
/// 下半部分 = 从 MainPlayerView 迁移过来的 SpectrumAnalyser 光柱
///
/// 通过 Cmd+N 从 MainPlayerView 进入，按 Esc 退出（路由逻辑由 MainPlayerView 顶层的
/// 全局键盘监听统一处理，本视图本身只负责渲染与歌词首次加载）。
struct NowPlayingView: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    @ObservedObject var lyricManager: LyricManager
    
    // ⏱️ 偏移提示闪现控制：每次 timeOffset 变化后显示 1s 自动消失。
    @State private var showOffsetHint: Bool = false
    
    // 📜 当前歌单侧滑面板的开关。
    @State private var showPlaylist: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // ── 上半区：歌词 + 旋转唱片 ─────────────────────────────
            HStack(spacing: 0) {
                LyricView(
                    lyricManager: lyricManager,
                    player: player,
                    themeType: $player.themeType,
                    palette: palette
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 🎯 用 GeometryReader 把唱片容器尺寸锁死为"父给多少就是多少"：GeometryReader 永远
                // 只接受父级提议的尺寸、忽略子视图（圆盘）的固有尺寸。因此无论 discSize 调多大、
                // offset 怎么移，圆盘溢出部分都被 .clipped() 裁掉，view 尺寸恒定不被撑大。
                GeometryReader { geo in
                    RotatingAlbumView(player: player, palette: palette)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
                        .offset(x: 130, y: -180)
                }
                .frame(width: 460)
                .frame(maxHeight: .infinity)
                .clipped()
                // 拖拽唱片区域 → 移动窗口（与 MainPlayerView.albumView 保持同样的体验）
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            NSApp.keyWindow?.performDrag(with: NSApp.currentEvent!)
                        }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 🎚️ 唱片下方的「歌单」小按钮：点开右侧滑出当前歌单列表。
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showPlaylist.toggle()
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(player.themeType == "black" ? .white : .black)
                        .frame(width: 42, height: 42)
                        .background(chipSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
//            Divider()
            
            // ── 下半区：光柱 ───────────────────────────────────────
            SpectrumAnalyser(
                audio: player.spectrum,
                palette: palette,
                themeType: $player.themeType,
                isAutopilot: player.isAutopilotMode
            )
            .frame(height: 150)
        }
        // ⚠️ 使用 maxWidth/maxHeight: .infinity + ignoresSafeArea(edges: .top) 让 VStack 填满从窗口顶端到底端的完整区域，
        // 避免之前 frame(height: 600) 被 ZStack 居中布局顶起 14pt 导致光柱不贴底。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        // ⚠️ 把 colorScheme 绑到 app 自己的主题。注意它**驱动不了 macOS 的材质**
        // （.regularMaterial / .ultraThinMaterial 背后是 NSVisualEffectView，只看窗口/系统外观），
        // 所以本页的面板、胶囊、分隔线已全部改成显式主题色（见 panelSurface / chipSurface / hairline）。
        // 这一行仍然保留：它管的是 SwiftUI 层的语义色与滚动条、选区高亮那一类跟随环境的控件。
        .environment(\.colorScheme, player.themeType == "black" ? .dark : .light)
        // 📜 右侧滑出的当前歌单面板 + 点击外部关闭的透明遮罩。
        .overlay {
            if showPlaylist {
                ZStack(alignment: .trailing) {
                    // 透明遮罩：铺满整个正在播放 view，点它任意位置 → 收起面板。
                    Color.primary.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { showPlaylist = false }
                        .transition(.opacity)
                    
                    // 面板本体：贴右侧、全高，列出当前歌单，点任意歌曲直接播放（不关面板）。
                    playlistPanel
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showPlaylist)
        // ⏱️ 手动偏移提示：每次按 ↑/↓ 后闪现 1s 自动消失（挂在最外层，不碰 ScrollView 区域）。
        .overlay(alignment: .bottomLeading) {
            if showOffsetHint {
                Text(String(format: "歌词偏移 %+.1fs", lyricManager.timeOffset))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(player.themeType == "black" ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(chipSurface, in: Capsule())
                    .padding(.leading, 16)
                    .padding(.bottom, 162)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showOffsetHint)
        // 🔄 .task(id:) 在 timeOffset 每次变化时取消上一个未完成的隐藏调度，重新走 1s。
        .task(id: lyricManager.timeOffset) {
            guard abs(lyricManager.timeOffset) > 0.001 else {
                showOffsetHint = false
                return
            }
            showOffsetHint = true
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                showOffsetHint = false
            } catch {
                // 被下一次变化取消，什么都不做。
            }
        }
        .onAppear {
            // 首次进入时主动加载一次当前歌曲歌词，避免 currentSong 未变化时
            // LyricView 内部的 .onChange 不触发导致的空白。
            if let song = player.currentSong {
                lyricManager.loadLyric(for: song.title)
            }
            // 首次进入也需主动刷一次调色盘，避免 NowPlaying 从 MainPlayer 未调色场景进入时拿到默认 cyan。
            updatePalette()
        }
        // 在 NowPlayingView 中 albumView 被分支销毁，AlbumImageView 中的 updatePalette 逻辑不再运行；
        // 这里补上同样的联动，保证切歌后专辑主色重新提取、背景模糊专辑与主题色同步刷新。
        .onChange(of: player.albumImages) { _, _ in
            updatePalette()
        }
    }
    
    // 📜 右侧滑出的当前歌单面板：点任意歌曲直接播放，面板不关（靠外部遮罩关闭）。
    private var playlistPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(player.currentPlaylistName.isEmpty ? "当前歌单" : player.currentPlaylistName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(player.themeType == "black" ? .white : .black)
                Spacer()
                Text("\(player.currentPlaylist.count) 首")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(player.themeType == "black" ? Color.white.opacity(0.55) : Color.black.opacity(0.62))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // 不用 Divider：它的 separatorColor 同样跟系统外观，系统 Dark 时会在白面板上发白。
            Rectangle()
                .fill(hairline)
                .frame(height: 1)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(player.currentPlaylist) { song in
                        let nowPlaying = player.currentSong?.id == song.id
                        HStack(spacing: 8) {
                            Image(systemName: nowPlaying ? "speaker.wave.2.fill" : "music.note")
                                .font(.system(size: 11))
                                .foregroundColor(nowPlaying ? palette.bgPalette : (player.themeType == "black" ? Color.white.opacity(0.45) : Color.black.opacity(0.55)))
                                .frame(width: 16)
                            Text(song.title)
                                .font(.system(size: 14, weight: nowPlaying ? .semibold : .regular, design: .rounded))
                                .foregroundColor(nowPlaying ? palette.bgPalette : (player.themeType == "black" ? .white : .black))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { player.play(song: song) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // ⚠️ 表面色必须自带，不能用 .regularMaterial：材质取的是**系统外观**的色（本机系统为 Dark），
        // 而列表文字按 app 的 themeType 写死 .black，两者一错配就是截图里那种
        // “纯白页面 + 深灰面板 + 黑字”。就算系统切到 Light，面板背后那张深色唱片也会被磨砂模糊成灰，
        // 所以这里干脆不依赖材质：灰白主题给一张比页面亮一档的白卡片，深色主题给一档抬高的深色。
        .background(panelSurface)
        .overlay(alignment: .leading) {
            Rectangle().fill(hairline).frame(width: 1)
        }
    }
    
    // 🎨 主题化表面三色。app 已有自己的主题系统，这些层不能再混用系统自适应材质。
    private var panelSurface: Color {
        palette.surface.isLight
            ? Color.white.opacity(0.94)
            : Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.96)
    }
    
    /// 小胶囊/圆按钮的底色：比页面略亮（浅底）或略抬（深底），靠图标对比而不是磨砂拉开层次。
    private var chipSurface: Color {
        palette.surface.isLight ? Color.white.opacity(0.86) : Color.white.opacity(0.14)
    }
    
    /// 分隔线。原来用 Color.primary，它同样跟系统外观——系统 Dark 时会在白面板上变成白线而看不见。
    private var hairline: Color {
        palette.surface.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.16)
    }
    
    private func updatePalette() {
        var image = NSImage(named: "Albumdefault")
        if !player.albumImages.isEmpty {
            let random = Int.random(in: 0..<player.albumImages.count)
            image = player.albumImages[random]
        }
        
        player.nowAlbum = image
        
        if let albumImage = image,
           let avgNSColor = albumImage.averageColor {
            let extractedColor = Color(avgNSColor)
            // 🎨 animated: false —— 正在播放页换歌要的是“到新歌就直接变色”，不要 1.8s 渐变。
            // 颜色渐变只留给 autopilot 极简模式（由 startAutopilotColors 每 5s 随机混色驱动）。
            palette.updateAlbumColor(
                extractedColor,
                player.themeType,
                animated: false
            )
        }
    }
}

// MARK: - 黑胶唱片式旋转专辑图
///
/// 渲染组成：
/// 1. 黑胶外环（半透明深色衬底，按主题分档：灰白 0.85 / 深色 0.6）
/// 2. 3 圈沟槽装饰环（不等间距，白色略明显，营造唱片纹理）
/// 3. 居中专辑封面（Circle mask）
/// 4. 中心小圆孔 + 主题色细描边
///
/// 动效：用 `TimelineView(.animation(paused:))` 把角度由真实经过时间直接算出（渲染路径不写 state）——
/// 播放即转、暂停即冻结、恢复即以恢复点为时间基准继续，天然按屏幕刷新率逐帧插值，
/// 比固定 30Hz 定时器手动步进更顺滑，也不会在续转时跳变。
private struct RotatingAlbumView: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    
    /// 角度基准：最后一次“停靠”时的累计角度，与停靠那一刻。
    /// 只有低频事件（出现/暂停/恢复/唤醒）会写这两个 state，渲染路径里一个都不写——
    /// 原来每帧在 onChange(of: timeline.date) 里连写 lastTick 和 displayAngle，
    /// SwiftUI 会报 "onChange(of: Date) action tried to update multiple times per frame"，
    /// 而且每帧双重失效本身是无谓的主线程开销。
    @State private var parkedAngle: Double = 0
    @State private var parkDate: Date = Date()
    /// 秒/圈：黑胶既视感（约 4.3 RPM）
    private let revolutionDuration: Double = 14
    /// 圆盘固有直径（不再靠增大它来撑布局，隐去效果交给外层容器裁剪）
    private let discSize: CGFloat = 580
    /// 沟槽装饰环的半径比例：只留 3 条，且**间距不等**——从外圈起第一、二条靠得近（0.05），
    /// 第三条拉开（0.14）。等距 7 圈会把唱片铺成刻度盘，反而不像黑胶。
    /// 封面外缘在 0.66，所以 0.775 仍落在黑胶环带内。
    private let grooveRatios: [CGFloat] = [0.965, 0.915, 0.775]
    
    var body: some View {
        TimelineView(.animation(paused: !player.isPlaying)) { timeline in
            // 角度就地算出：暂停时 timeline 不再推进，extra 直接取 0，圆盘停在停靠值上。
            let extra = player.isPlaying
                ? max(timeline.date.timeIntervalSince(parkDate), 0)
                : 0
            let angle = parkedAngle + extra / revolutionDuration * 360.0
            ZStack {
                // 黑胶外环：灰白主题下压到 0.85——0.6 的半透黑叠在近白背景上只剩浅灰，
                // 整张唱片发灰发花（用户形容“像 kingsman 的裤子”）。
                // 深色主题维持 0.6：那里背景本身就是黑的，压深了反而看不出唱片边界。
                Circle()
                    .fill(Color.black.opacity(player.themeType == "black" ? 0.6 : 0.85))
                    .frame(width: discSize, height: discSize)
                
                // 沟槽装饰环：白色略明显（opacity 0.14，线宽 1），营造唱片纹理
                ForEach(grooveRatios, id: \.self) { ratio in
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        .frame(width: discSize * ratio, height: discSize * ratio)
                }
                
                // 专辑封面
                Group {
                    if let img = player.nowAlbum {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image("Albumdefault")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: discSize * 0.66, height: discSize * 0.66)
                .clipShape(Circle())
                
                // 中心圆孔
//                Circle()
//                    .fill(Color.black)
//                    .frame(width: 26, height: 26)
//                Circle()
//                    .stroke(palette.bgPalette.opacity(0.6), lineWidth: 1.5)
//                    .frame(width: 26, height: 26)
            }
            .frame(width: discSize, height: discSize)
            // 🚀 静态圆盘一次栅格化为 GPU 纹理（无 ScrollView，安全）。
            .drawingGroup()
            .rotationEffect(.degrees(angle))
        }
        .frame(width: discSize, height: discSize)
        .onAppear { parkDate = Date() }
        // 暂停/恢复都把已转过的时间结算进 parkedAngle，再以当下为新基准：
        // 续转既不跳，也不会把暂停那一段算成旋转。
        .onChange(of: player.isPlaying) { _, playing in
            let now = Date()
            if playing {
                parkDate = now
            } else {
                parkedAngle += max(now.timeIntervalSince(parkDate), 0) / revolutionDuration * 360.0
                parkDate = now
            }
        }
        // 休眠唤醒：这段时间里 timeline 不推进、音频也是停的，所以只把基准挪到当下、
        // 不结算角度——等价于原来对巨大 dt 的钳制，封面不会瞬跳。
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            parkDate = Date()
        }
    }
}
