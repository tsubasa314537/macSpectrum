//
//  NowPlayingView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/16.
//

import SwiftUI
import Combine

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
                        .background(.ultraThinMaterial, in: Circle())
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
                    .background(.ultraThinMaterial, in: Capsule())
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
                    .foregroundColor(player.themeType == "black" ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider().opacity(0.4)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(player.currentPlaylist) { song in
                        let nowPlaying = player.currentSong?.id == song.id
                        HStack(spacing: 8) {
                            Image(systemName: nowPlaying ? "speaker.wave.2.fill" : "music.note")
                                .font(.system(size: 11))
                                .foregroundColor(nowPlaying ? palette.bgPalette : (player.themeType == "black" ? Color.white.opacity(0.4) : Color.black.opacity(0.4)))
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
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
        }
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
            palette.updateAlbumColor(
                extractedColor,
                player.themeType,
                animated: player.isAutopilotMode
            )
        }
    }
}

// MARK: - 黑胶唱片式旋转专辑图
///
/// 渲染组成：
/// 1. 黑胶外环（半透明深色亵底，本轮减淡，灰白主题上不至于死黑）
/// 2. 多圈沟槽装饰环（白色略明显，营造唱片纹理）
/// 3. 居中专辑封面（Circle mask）
/// 4. 中心小圆孔 + 主题色细描边
///
/// 动效：用 `TimelineView(.animation(paused:))` 基于真实经过时间累加角度——
/// 播放即转、暂停即冻结、恢复即以恢复点为时间基准继续，天然按屏幕刷新率逐帧插值，
/// 比固定 30Hz 定时器手动步进更顺滑，也不会在续转时跳变。
private struct RotatingAlbumView: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    
    /// 当前显示角度（基于时间累加）
    @State private var displayAngle: Double = 0
    /// 上一帧时间基准，用于算帧间隔
    @State private var lastTick: Date = Date()
    /// 秒/圈：黑胶既视感（约 4.3 RPM）
    private let revolutionDuration: Double = 14
    /// 圆盘固有直径（不再靠增大它来撑布局，隐去效果交给外层容器裁剪）
    private let discSize: CGFloat = 580
    /// 沟槽装饰环的半径比例（封面外缘 → 黑胶内缘之间均匀铺 7 圈）
    private let grooveRatios: [CGFloat] = (0...6).map { 0.70 + CGFloat($0) * 0.045 }
    
    var body: some View {
        TimelineView(.animation(paused: !player.isPlaying)) { timeline in
            ZStack {
                // 黑胶外环（减淡：0.88 → 0.6，灰白主题上更柔和）
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: discSize, height: discSize)
                
                // 沟槽装饰环：多圈 + 白色更明显（opacity 0.05 → 0.14，lineWidth 仍为 1）
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
            .rotationEffect(.degrees(displayAngle))
            // 每个刷新帧按真实经过时间累加角度（仅播放时 timeline 才推进 date）。
            .onChange(of: timeline.date) { _, newDate in
                let dt = newDate.timeIntervalSince(lastTick)
                lastTick = newDate
                // 夹一个大值防御（系统休眠唤醒导致的巨大 dt），避免角度瞬跳。
                let clamped = min(max(dt, 0), 0.1)
                displayAngle += clamped / revolutionDuration * 360.0
            }
        }
        .frame(width: discSize, height: discSize)
        .onAppear { lastTick = Date() }
        // 恢复播放时把时间基准对齐到当下，避免暂停期间 lastTick 过期导致续转跳变。
        .onChange(of: player.isPlaying) { _, playing in
            if playing { lastTick = Date() }
        }
    }
}
