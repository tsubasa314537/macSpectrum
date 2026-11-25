//
//  NowPlayingView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/16.
//

import SwiftUI
import Combine
import AppKit

/// 「正在播放」全屏视图，自上而下三段：
/// 上半区（按主题分叉，见 `upperArea`）+ 光柱 150 + 常驻播控条 78
///
/// 1. 灰白主题 = 左歌词 + 右上角黑胶旋转唱片（原几何未动）
/// 2. 纯黑主题 = 左方形静止专辑图 + 右歌词
/// 3. 播控条常驻在光柱下方，**不做 hover 上抬**——光柱是本页主角，不能被遮挡
///
/// 通过 Cmd+N 从 MainPlayerView 进入，按 Esc 或播控条左端的回主界面按钮退出
/// （Esc 的路由逻辑由 MainPlayerView 顶层的全局键盘监听统一处理）。
struct NowPlayingView: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    @ObservedObject var lyricManager: LyricManager
    
    // ⏱️ 偏移提示闪现控制：每次 timeOffset 变化后显示 1s 自动消失。
    @State private var showOffsetHint: Bool = false
    
    // 📜 当前歌单侧滑面板的开关。
    @State private var showPlaylist: Bool = false
    
    // 🔄 唱片的角度基准。存在这一层而不是 RotatingAlbumView 里：upperArea 按主题分叉，
    // 每次 Cmd+T 都会销毁重建唱片子树，本地 @State 一复位封面就瞬间转回 0°。
    // NowPlayingView 本身不在分支里，它的 @State 能活过主题切换。
    @State private var discParkedAngle: Double = 0
    @State private var discParkDate: Date = Date()
    
    var body: some View {
        VStack(spacing: 0) {
            // ── 上半区：按主题分叉 ───────────────────────────────
            upperArea
            
            // ── 中段：光柱 ───────────────────────────────────────
            SpectrumAnalyser(
                audio: player.spectrum,
                palette: palette,
                themeType: $player.themeType,
                isAutopilot: player.isAutopilotMode
            )
            .frame(height: 150)
            
            // ── 底部：常驻播控条 ─────────────────────────────────
            PlaybackControlBar(
                player: player,
                palette: palette,
                onTogglePlaylist: { showPlaylist.toggle() },
                onExit: { player.nowPlayingShown = false },
                // 顶部那条 1px 分隔线也不要了（和主界面一致）。底色仍由组件自己铺，
                // 这页没有外层圆角面板可以接棒，所以 drawsSurface 保持默认 true。
                showsTopDivider: false
            )
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
                    // 光柱 150 + 播控条 78 + 12 余量：提示要浮在播控条之上，不能被压住。
                    .padding(.bottom, 240)
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
    
    // MARK: - 上半区（主题分叉）
    
    /// 黑主题方图边长：固定不随窗口变。320 → 368（+15%，用户要求），
    /// 上半区最小高 495 装得下：居中 63.5 + 下沉 24 + 368 = 455.5，仍留 39 呼吸。
    private let blackAlbumSide: CGFloat = 368
    /// 黑主题方图与歌词之间的间距。方图不再钉左边，改成**在左半区居右**（对齐 QQ 黑胶机位）：
    /// 之前 `blackAlbumLeading = 150` 让方图贴死左半区、右边空出一大片，看着就是"太靠左"。
    /// 48 → 96：间距翻倍，1300 宽时方图 x∈[234, 602]，歌词从 698 起拿 570 宽。
    private let blackAlbumGap: CGFloat = 96
    /// 黑主题方图额外下沉量。**纯视觉补偿**：实测方图已经严格居中
    /// （上半区 471pt 时上隙 75.5 / 下隙 75.5，逐像素量自用户截图），
    /// 但方图下方到柱尖之间那段空白比上方大得多，看上去就偏上。想调回去改这一个数。
    private let blackAlbumDownBias: CGFloat = 24
    
    /// 白主题黑胶：面积比上一版（640）再大 30% → 直径 ×√1.3 = 730。
    private let whiteDiscSize: CGFloat = 730
    /// 黄金比：圆心到上边 ÷ 到右边 = 0.618（用户指定）。上一版 75:230 = 0.33，
    /// 盘沿右边界只盖到 y=298 而盘下缘在 395 → 右上角那一条有 25% 盘高是白的（用户圈的蓝框）。
    private let whiteDiscRatio: CGFloat = 0.618
    /// 圆心位置（相对上半区左上角）。这两个值是联立解出来的，不是拍出来的：
    /// 面积 +30% 与 0.618 两个约束下，若把圆心钉在旧下缘（dy=35）可见面积反而只剩 37%（牙状），
    /// dy=128 时可见面积 234k ≈ 现在的 1.29 倍，同时右边界白缝从 25% 压到 13%。
    private let whiteDiscCenterY: CGFloat = 128
    private var whiteDiscCenterX: CGFloat { whiteDiscCenterY / whiteDiscRatio }   // 207
    /// 由圆心反解容器参数：topTrailing 对齐下，盘心 = (W − outset − r, lift + r)。
    private var whiteDiscOutset: CGFloat { whiteDiscSize / 2 - whiteDiscCenterX }  // 158
    private var whiteDiscLift: CGFloat { whiteDiscSize / 2 - whiteDiscCenterY }    // 237
    /// 容器宽：必须 ≥ 可见宽（discSize − outset = 572），否则盘的左弧会被容器左边切掉。
    /// 600 给到 28pt 余量，歌词块拿 W − 600 = 700（54%）。
    private let whiteDiscContainerWidth: CGFloat = 600
    
    /// 上半区最小高：取两个主题里更紧的那个。
    /// 白主题黑胶下缘 = centerY 128 + 半径 365 = **493pt**（旧值 395）；黑主题方图固定 368。
    /// 取 495 留余量 —— 这个值直接决定整窗高度下限（见下方 minWindowHeight），
    /// 因为 `.windowResizability(.contentSize)` 是从内容的 min 尺寸反推 contentMinSize 的。
    static let upperMinHeight: CGFloat = 495
    /// 整窗最小高 = 上半区 + 光柱 150 + 播控条 78 + 实测余量 32（标题栏安全区那部分）。
    /// 495 + 150 + 78 + 32 = 755。
    static var minWindowHeight: CGFloat { upperMinHeight + 150 + PlaybackControlBar.height + 32 }
    /// 进页时不够高就放大到这个尺寸：比下限多 25pt，让盘下缘与光柱之间留一点呼吸。
    static let preferredWindowHeight: CGFloat = 780
    
    /// 灰白 = 左歌词 + 右上角黑胶唱片；纯黑 = 左方形静止专辑图 + 右歌词。
    ///
    /// 用一层 GeometryReader 量出上半区尺寸再分叉：灰白那边圆盘容器的宽高本来就是
    /// 「父给多少算多少」；黑主题方图已经改成固定边长，不再读 geo。
    @ViewBuilder
    private var upperArea: some View {
        GeometryReader { geo in
            if player.themeType == "black" {
                HStack(spacing: 0) {
                    // 居右：先让方图吃掉左半区的全部弹性宽度并右对齐，再和歌词之间留 gap。
                    // offset 不参与布局，所以方图自己的垂直下沉不会挪动歌词。
                    albumSquare(side: blackAlbumSide)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, blackAlbumGap)
                    lyricBlock(leadingInset: 0)
                        .padding(.trailing, 32)
                }
            } else {
                HStack(spacing: 0) {
                    lyricBlock(leadingInset: 40)
                    discContainer(height: geo.size.height)
                }
            }
        }
        // ⚠️ 窗口的高度下限只能由这条 minHeight 提供。MacSpectrumApp 用的是
        // `.windowResizability(.contentSize)`，AppKit 的 contentMinSize 由内容的 min 尺寸推导；
        // 反过来命令式去写 window.contentMinSize 会被下一次布局重算盖掉（上一版就是这么失效的）。
        // 高度方向原本全是 maxHeight: .infinity，没有推导源，所以能被无限压扁到唱片被裁；
        // 宽度一直有效是因为 SpectrumAnalyser 自带 minWidth: 1100。
        // 离屏实测：这里填 0 / 320 / 400 → contentMinSize 高度 260 / 580 / 660，严格线性。
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: Self.upperMinHeight, maxHeight: .infinity)
        .clipped()
    }
    
    /// 歌词块：两个主题都**靠左渲染**（QQ 音乐就是这样，当前行钉在一条竖轴上，
    /// 而不是每行按自身宽度居中、换行时整墙左右晃）。
    /// `leadingInset` 是这块相对自己起点的左内缩——黑主题紧跟在方图之后（间距已经由
    /// `blackAlbumGap` 给足，填 0），白主题直接贴窗口左边，需要自己让出一点边距。
    private func lyricBlock(leadingInset: CGFloat) -> some View {
        LyricView(
            lyricManager: lyricManager,
            player: player,
            themeType: $player.themeType,
            palette: palette
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, leadingInset)
    }
    
    /// 黑胶容器：尺寸全部由上面的四个旋钮给出，不再散着写魔法数。
    /// 圆盘固有直径大于容器，溢出部分交给 .clipped() —— 它的布局尺寸恒定是
    /// containerWidth × height，不会因为 discSize 变大而反过来撑大 HStack。
    private func discContainer(height: CGFloat) -> some View {
        RotatingAlbumView(player: player, palette: palette,
                          parkedAngle: $discParkedAngle, parkDate: $discParkDate,
                          discSize: whiteDiscSize)
            .frame(width: whiteDiscContainerWidth, height: height, alignment: .topTrailing)
            .offset(x: whiteDiscOutset, y: -whiteDiscLift)
            .frame(width: whiteDiscContainerWidth, height: height)
            .clipped()
            .gesture(windowDragGesture)
    }
    
    /// 纯黑主题的方图：不转、不裁、尺寸固定（不跟窗口高度走，避免拖窗口时图跟着抽）。
    /// 上下位置 = HStack 默认居中（已逐像素证实对称）再叠加 `blackAlbumDownBias` 的视觉下沉。
    /// offset 不参与布局，所以不会动到右边歌词的位置。
    @ViewBuilder
    private func albumSquare(side: CGFloat) -> some View {
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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.40), radius: 20, x: 0, y: 10)
        .offset(y: blackAlbumDownBias)
        .gesture(windowDragGesture)
    }
    
    /// 拖拽专辑图区域 → 移动窗口（与 MainPlayerView.albumView、原唱片容器同样的体验）
    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                NSApp.keyWindow?.performDrag(with: NSApp.currentEvent!)
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
                        .onTapGesture {
                            // 🌀 Super Shuffle 期间这个面板列的是整个库，用户要求它跟着锁定。
                            // 同样不能靠 .disabled：行是 onTapGesture 实装的，对手势无效。
                            guard !player.superShuffle else { return }
                            player.play(song: song)
                        }
                    }
                }
                .padding(.vertical, 6)
                .opacity(player.superShuffle ? 0.4 : 1)
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
        // 逐图 + 取均色 + 换主题色这条链已抽进 PaletteManager，主界面也走同一份。
        // animated: false —— 换歌要的是「到新歌就直接变色」，1.8s 渐变只留给 autopilot 混色。
        player.nowAlbum = palette.applyAlbumImages(player.albumImages, themeType: player.themeType)
    }
}

// MARK: - 黑胶唱片式旋转专辑图
///
/// 只在灰白主题出现（黑主题走 albumSquare），所以盘面颜不再按 themeType 分叉。
///
/// 渲染组成（自下而上，全部由专辑主色 bgPalette 派生）：
/// 1. 盘底径向渐变：中心收深 → 环带主色 → 外缘再收，做出体积而不是纯色平涂。
/// 2. 密沟槽：环带内 14 圈交替「暗线 + 受光线」，一条 RadialGradient 画完。
/// 3. 三条主沟槽：暗槽底 + 亮槽肩（明暗双线），间距不等。
/// 4. 方向性高光：斜向两道软光，只落在环带——封面是纸标，不吃这层反光。
/// 5. 边缘内阴影 + 外圈受光描边（左上亮、右下暗 = 固定光源）。
/// 6. 封面 label：外圈压槽 + 本体 + 边缘细暗线。
///
/// 动效：角度由 TimelineView 的真实经过时间算出（渲染路径不写 state）——播放即转、暂停即冻结、
/// 恢复即以恢复点为基准续转，天然按刷新率逐帧插值。
/// 而且**只有 label 在转**：沟槽是同心圆，转了也看不出来，把它留在静态层里，
/// 方向性高光才能钉死在世界的同一个方向，而不是跟着盘一起跑。
private struct RotatingAlbumView: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    /// 角度基准：最后一次“停靠”时的累计角度，与停靠那一刻。
    /// 只有低频事件（出现/暂停/恢复/唤醒）会写这两个值，渲染路径里一个都不写——
    /// 原来每帧在 onChange(of: timeline.date) 里连写 lastTick 和 displayAngle，
    /// SwiftUI 会报 "onChange(of: Date) action tried to update multiple times per frame"。
    ///
    /// ⚠️ 存在 NowPlayingView 而不是本视图的 @State：upperArea 换主题分支会销毁重建整棵子树，
    /// 本地 @State 一复位，封面就会在 Cmd+T 后瞬间转回 0°（与歌词归位是同一个病）。
    @Binding var parkedAngle: Double
    @Binding var parkDate: Date
    
    /// 秒/圈：黑胶既视感（约 4.3 RPM）
    private let revolutionDuration: Double = 14
    /// 圆盘固有直径（不再靠增大它来撑布局，隐去效果交给外层容器裁剪）。
    /// 由 NowPlayingView 的 `whiteDiscSize` 传入，与容器宽/越界量放在一处对算。
    var discSize: CGFloat = 640
    /// 封面 label 占盘直径的比例
    private let labelRatio: CGFloat = 0.66
    /// 主沟槽的半径比例：只留 3 条，且**间距不等**——从外圈起第一、二条靠得近（0.05），
    /// 第三条拉开（0.14）。等距会把唱片铺成刻度盘，反而不像黑胶。
    /// 封面外缘在 0.66，所以 0.775 仍落在黑胶环带内。
    private let grooveRatios: [CGFloat] = [0.965, 0.915, 0.775]
    /// 密沟槽圈数与明暗线不透明度（14 圈铺满 95pt 环带 ≈ 6.8pt 一圈）
    private let fineGrooves = 4
    private let fineDark = 0.18
    private let fineLight = 0.22
    /// 方向性高光强度 / 边缘内阴影深度 / 外缘亮度系数
    private let sheen = 0.40
    private let rimShadow = 0.40
    private let rimBri: CGFloat = 0.68
    /// 环带目标相对亮度：比它亮的主题色（明黄、亮青、浅粉）按 (target/L)^0.6 压下来，
    /// 色相与饱和度不动。黑胶本身是暗的——不统一亮度的话，暖色盘会画成一片木纹。
    private let bandTuneLum: CGFloat = 0.20
    
    private var radius: CGFloat { discSize / 2 }
    private var labelDiameter: CGFloat { discSize * labelRatio }
    
    /// 盘底某一处的颜色：亮度/饱和系数直接乘在专辑主色的 HSB 分量上。
    /// src 与 scale 在 body 里算一次传进来，避免逐帧重复走 Color → NSColor 反解。
    private func band(_ src: (h: CGFloat, s: CGFloat, b: CGFloat), _ briK: CGFloat,
                      _ satK: CGFloat, _ scale: CGFloat) -> Color {
        ThemeColorEngine.color(hue: src.h, sat: min(1, src.s * satK),
                               bri: max(0, min(1, src.b * briK * scale)))
    }
    
    /// 环带亮度系数：只有比目标亮度更亮的色相才会 <1，本来就深的盘一点不动。
    private func bandScale(_ src: (h: CGFloat, s: CGFloat, b: CGFloat)) -> CGFloat {
        let rgb = ThemeColorEngine.rgb(hue: src.h, sat: src.s, bri: src.b)
        let l = ThemeColorEngine.luminance(r: rgb.r, g: rgb.g, b: rgb.b)
        return l > bandTuneLum ? pow(bandTuneLum / l, 0.6) : 1.0
    }
    
    /// 密沟槽：一条 RadialGradient 画完 14 圈明暗线（共 30 个 stop）。
    /// 比叠 28 个 Circle().stroke 便宜得多，也不会把栅格化层撑成几十个子图层。
    private var grooveStops: [Gradient.Stop] {
        var stops: [Gradient.Stop] = [.init(color: .clear, location: 0)]
        for i in 0..<fineGrooves {
            let t = CGFloat(i) / CGFloat(fineGrooves - 1) * 0.93
            stops.append(.init(color: Color.black.opacity(fineDark), location: Double(t)))
            stops.append(.init(color: Color.white.opacity(fineLight), location: Double(t + 0.014)))
        }
        stops.append(.init(color: .clear, location: 1))
        return stops
    }
    
    /// 静态盘面：不随角度变，一次栅格化成 GPU 纹理。
    private func discTexture(_ src: (h: CGFloat, s: CGFloat, b: CGFloat), _ scale: CGFloat) -> some View {
        ZStack {
            // 盘底体积
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: band(src, 0.92, 1.06, scale), location: 0.00),
                    .init(color: band(src, 1.00, 1.00, scale), location: 0.62),
                    .init(color: band(src, 1.02, 0.98, scale), location: 0.82),
                    .init(color: band(src, rimBri, 1.10, scale), location: 1.00)
                ], center: .center, startRadius: 0, endRadius: radius))
                .frame(width: discSize, height: discSize)
            
            // 密沟槽：只从 label 外缘起画到盘边
            Circle()
                .fill(RadialGradient(stops: grooveStops, center: .center,
                                     startRadius: labelDiameter / 2 + 5, endRadius: radius))
            
            // 三条主沟槽：暗槽底 + 亮槽肩
            ForEach(grooveRatios, id: \.self) { ratio in
                let d = discSize * ratio
                ZStack {
                    Circle().stroke(Color.black.opacity(0.40), lineWidth: 2.0)
                        .frame(width: d, height: d)
                    Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                        .frame(width: d - 2.4, height: d - 2.4)
                }
            }
            
            // 方向性高光。⚠️ 必须用 Circle().fill(渐变)：裸 Circle() 作为 Shape 的默认填充
            // 是不透明黑，写成 Circle().overlay(渐变) 会在环带上多盖一张黑盘（原型里踩过）。
            Circle()
                .fill(LinearGradient(stops: [
                    .init(color: .white.opacity(sheen), location: 0.05),
                    .init(color: .white.opacity(0), location: 0.32),
                    .init(color: .white.opacity(sheen * 0.5), location: 0.60),
                    .init(color: .white.opacity(0), location: 0.86)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .mask(Circle()
                    .fill(RadialGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: Double((labelDiameter / 2 - 5) / radius)),
                        .init(color: .white, location: Double((labelDiameter / 2 + 5) / radius)),
                        .init(color: .white, location: 1)
                    ], center: .center, startRadius: 0, endRadius: radius)))
            
            // 边缘内阴影 + 外圈受光描边
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: .clear, location: 0.86),
                    .init(color: .black.opacity(rimShadow), location: 1.0)
                ], center: .center, startRadius: 0, endRadius: radius))
            Circle()
                .stroke(LinearGradient(stops: [
                    .init(color: .white.opacity(0.55), location: 0.00),
                    .init(color: .white.opacity(0.24), location: 0.42),
                    .init(color: .white.opacity(0.04), location: 1.00)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.6)
                .frame(width: discSize - 2, height: discSize - 2)
            
            // label 外圈的压槽：让封面像嵌在盘里，而不是贴在盘上
            Circle()
                .stroke(Color.black.opacity(0.32), lineWidth: 3)
                .frame(width: labelDiameter + 8, height: labelDiameter + 8)
        }
        .frame(width: discSize, height: discSize)
    }
    
    /// 会转的那一层：只有封面。纸标上的图案才是跟着盘走的东西。
    private var labelLayer: some View {
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
        .frame(width: labelDiameter, height: labelDiameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.24), lineWidth: 1))
    }
    
    var body: some View {
        TimelineView(.animation(paused: !player.isPlaying)) { timeline in
            // 角度就地算出：暂停时 timeline 不再推进，extra 直接取 0，圆盘停在停靠值上。
            let extra = player.isPlaying
                ? max(timeline.date.timeIntervalSince(parkDate), 0)
                : 0
            let angle = parkedAngle + extra / revolutionDuration * 360.0
            let src = ThemeColorEngine.hsb(of: palette.bgPalette)
            let scale = bandScale(src)
            ZStack {
                discTexture(src, scale)
                    // 🚀 静态盘面一次栅格化为 GPU 纹理（无 ScrollView，安全）。
                    .drawingGroup()
                labelLayer
                    // 🚀 单独栅格化后再转：沟槽与高光留在静态层里不跟着转，
                    // 这一层逐帧只做一个 GPU 纹理变换。
                    .drawingGroup()
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: discSize, height: discSize)
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
