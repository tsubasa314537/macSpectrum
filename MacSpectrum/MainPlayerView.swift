//
//  MainPlayerView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import SwiftUI
import AppKit

struct MainPlayerView: View {
    
    @ObservedObject var player: PlayerManager
    @ObservedObject var palette: PaletteManager
    @StateObject var lyricManager: LyricManager
    
    /// 「时长」列要真开文件读 header，787 首实测 0.4s，所以放后台扫、分批回填。
    @StateObject private var metadata = SongMetadataStore()
    
    /// 列表行的小封面：albums 目录只列一次建索引，解码走后台按 128px 出图。
    @StateObject private var albumArt = AlbumArtStore(albumsURL: Self.albumsDirectory)
    
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylist: Playlist?
    @State private var query: String = ""
    @State private var hoveredSong: Song.ID?
    /// 搜索命中后要定位的那首歌。歌曲列表用 ScrollViewReader 消费它，消费完立刻置 nil，
    /// 否则任何一次重算 body 都会把列表再滚回去一次。
    @State private var pendingScrollSong: Song.ID?
    
    /// 歌单列宽。左列（登录用户 + 歌单）整块就这个宽，右块吃剩下的。
    static let playlistColumnWidth: CGFloat = 267
    
    /// albums 目录。和 PlayerManager.albumsURL 同一个推导（都从 ~/Documents/spectrumplayer 走），
    /// 之所以自己算一份：@StateObject 的默认值里不能引用 self。
    private static let albumsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("spectrumplayer/albums", isDirectory: true)
    }()
    
    // 📐 主界面也改成随窗口自适应宽度：原先写死 .frame(width: 1050, height: 600)，
    // 在 1300 的窗口里居中，两侧各留 125 空白 —— 和光柱「窗口拉宽就两侧空空的」是同一个病。
    // idealWidth/idealHeight 负责启动时的默认尺寸，min 负责窗口下限（.windowResizability(.contentSize)
    // 只认内容侧的 min，命令式写 contentMinSize 会被盖掉）。
    // 1000 → 1300：最小宽度锁到当前默认宽度，只许放大不许缩。目标机型就是 14/16 寸 MBP，
    // 窄窗口那套排版不值得维护；光柱的柱宽/间距是写死的，靠缩窗口只会让两侧空得更多。
    // 自动驾驶（极简模式）那条 1100×150 的窗口不走这里，下限在 SpectrumAnalyser 里按 isAutopilot 分叉。
    static let minColumnWidth: CGFloat = 1300
    static let minColumnHeight: CGFloat = 420
    static let idealColumnWidth: CGFloat = 1300
    static let idealColumnHeight: CGFloat = 600
    
    // 歌曲列表各列的固定列宽。表头与数据行共用这一组常量，改一处两边一起动，不会错位。
    // 封面列取代了原先那列 music.note 小图标（用户要求「把专辑图摆到歌名之前」），
    // 字号也跟着封面一起放大：15/13 → 16/14，行高从 30 拉到 40+12。
    private let colCover: CGFloat = 40
    private let colArtist: CGFloat = 160
    private let colAlbum: CGFloat = 190
    private let colDuration: CGFloat = 60
    private let colSize: CGFloat = 68
    private let colGap: CGFloat = 14
    
    // 右块三块区域的几何：圆角、块间缝、面板内边距。
    private let panelCorner: CGFloat = 12
    private let panelGap: CGFloat = 10
    private let panelPadding: CGFloat = 16
    
    // 1. 获取当前系统登录用户的 Documents 目录真实路径
    let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    var body: some View {
        // 🚀 用一个大外壳包裹，确保生命周期（.onAppear）在全软件运行期间只加载一次，永不被摧毁
        // 🎚️ 三态顶层路由：Now Playing（Cmd+N） / Autopilot 极简 / 主视图
        ZStack {
            if player.nowPlayingShown {
                NowPlayingView(
                    player: player,
                    palette: palette,
                    lyricManager: lyricManager
                )
                .transition(.opacity)
            } else if player.isAutopilotMode {
                VStack(spacing: 0) {
                    if player.karaoke {
                        if player.currentSong != nil {
                            KaraokeLyricsView(
                                player: player,
                                lyricManager: lyricManager,
                                palette: palette
                            )
                            .frame(height: 120)
                        } else {
                            Text("让音乐带走时光...")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    SpectrumAnalyser(
                        audio: player.spectrum,
                        palette: palette,
                        themeType: $player.themeType,
                        isAutopilot: true
                    )
                    .frame(height: 150)
                    .padding(.vertical, 0)
                }
            } else {
                mainColumns
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.nowPlayingShown)
        // 🚀 牢牢把全局监听挂在最外层 ZStack 壳子上，无论内部如何切换自动驾驶，快捷键永不失效！
        .onAppear {
            // ① 标题栏与控制按钮恢复。以前只有一个界面的时候整条都藏了，
            // 现在按模式决定藏不藏（见 applyWindowChrome）。
            applyWindowChrome()
            
            let lyrics = PlaylistLoader.loadLyrics(from: player.lyricsURL.path)
            playlists = PlaylistLoader.load(from: player.songsURL.path, in: lyrics)
            // 🌀 全库大数组灌给 PlayerManager：Super Shuffle 与搜索都要它，
            // 但它是启动后就不再变的量，没必要 @Published。
            player.allSongs = playlists.flatMap { $0.songs }
            metadata.scan(player.allSongs)
            
            // 🎲 启动不再固定拿第一个歌单：随机一张，再从这张里随机一首「装上但不播」。
            // 以前只 loadPlaylist 不选歌，控制条那颗 ▶ 走的是空排程的 resume()，
            // 点下去一点声音都没有。prepare 之后当前曲、总时长、封面、主题色全都就位，
            // ▶ 直接把这一首唱出来。
            if let playlist = playlists.randomElement() ?? playlists.first {
                selectedPlaylist = playlist
                player.loadPlaylist(songs: playlist.songs, name: playlist.name)
                // 时长上面已经全库扫过了（playlist.songs 是 allSongs 的子集，scan 又是幂等的），
                // 这里只补封面：先把可见这张歌单的图排进后台解码队列，列表滚下去不用干等。
                albumArt.warm(playlist.songs)
                if let song = playlist.songs.randomElement() {
                    player.prepare(song: song)
                }
            }
            
            // 🎨 启动时先把当前主题同步给 palette，保证 ink 从一开始就是对着正确底色派生出来的。
            palette.applyTheme(player.themeType)
            // prepare 那一下 albumImages 赋值发生在本轮 body 之前，onChange 补不到，手动同步一次。
            syncAlbumColor()
            
            // 全局快捷键大总管
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                switch event.keyCode {
                    case 45: // Cmd + N：从主视图进入 Now Playing
                        if modifiers == .command && !player.isAutopilotMode && !player.nowPlayingShown {
                            enterNowPlaying()
                            return nil
                        }
                        return event
                    case 53: // Esc：从 Now Playing 返回主视图。主题不再强压回 black（见 enterNowPlaying 注释）。
                        if player.nowPlayingShown {
                            player.nowPlayingShown = false
                            return nil
                        }
                        return event
                    case 40: // Cmd + K
                        if modifiers == .command && player.isAutopilotMode {
                            player.karaoke.toggle()
                            return nil
                        }
                        return event
                    case 9: // Cmd + V（在 Now Playing 下屏蔽，避免与路由冲突）
                        if modifiers == .command && !player.nowPlayingShown {
                            player.isAutopilotMode.toggle()
                            if !player.isAutopilotMode {
                                player.themeType = "black"
                                player.standardTheme = true
                            } else {
                                player.themeType = "white"
                                player.standardTheme = false
                            }
                            return nil
                        }
                        return event
                    case 17: // Cmd + T（主视图与正在播放页都可用，极简模式下不响应）
                        // 以前锁在 nowPlayingShown 里，因为当时主界面只能黑底；现在两页共用同一套
                        // 主题，主界面也得能切，否则白着回到主界面就再也换不回黑。
                        if !player.isAutopilotMode && modifiers == .command {
                            if player.themeType == "black" {
                                player.themeType = "white"
                                player.standardTheme = false
                            } else {
                                player.themeType = "black"
                                player.standardTheme = true
                            }
                            return nil
                        }
                        return event
                        
                    case 98, 123:  // F7 或 左箭头
                        player.previousTrack()
                        return nil
                    case 100: // F8
                        player.isPlaying ? player.pause() : player.resume()
                        return nil
                    case 49: // 空格
                        // ⌨️ 正在打字时空格必须原样交回系统：五笔/拼音的候选上屏键就是空格。
                        // local monitor 在这里 return nil 等于把上屏键吞了，字永远打不出来。
                        if Self.isTextEditing() { return event }
                        player.isPlaying ? player.pause() : player.resume()
                        return nil
                    case 101, 124: // F9 或 右箭头
                        player.nextTrack()
                        return nil
                    case 126: // ↑：仅 NowPlaying 下拦截，减时间 0.5s（重算+滚动交给 LyricView 的 onChange）
                        if player.nowPlayingShown {
                            lyricManager.timeOffset -= 0.5
                            return nil
                        }
                        return event
                    case 125: // ↓：仅 NowPlaying 下拦截，加时间 0.5s
                        if player.nowPlayingShown {
                            lyricManager.timeOffset += 0.5
                            return nil
                        }
                        return event
                    default:
                        return event
                }
            }
        }
        .onChange(of: player.isAutopilotMode) { _, isAutopilot in
            player.standardTheme = false
            player.themeType = "black"
            player.karaoke = false
            
            if let window = NSApplication.shared.windows.first {
                if isAutopilot {
                    // 极简是条固定 1100×150 的横条。进之前先把当前内容尺寸存下来，
                    // 退出时原样还回去 —— 以前退出硬写 idealColumnWidth×idealColumnHeight，
                    // 用户自己拉大过的窗口会被一下打回 1300×600（反馈“切回主界面 size 不对”）。
                    if sizeBeforeAutopilot == nil, let content = window.contentView {
                        sizeBeforeAutopilot = content.frame.size
                    }
                    window.setContentSize(NSSize(width: 1100, height: 150))
                    window.isOpaque = true
                    window.hasShadow = false
                    window.level = .floating
                    window.isMovableByWindowBackground = true
                } else {
                    // 没记到（启动就在极简里）才回到 ideal。
                    let back = sizeBeforeAutopilot ?? NSSize(width: Self.idealColumnWidth,
                                                             height: Self.idealColumnHeight)
                    sizeBeforeAutopilot = nil
                    window.setContentSize(back)
                    window.isOpaque = true
                    window.hasShadow = true
                    window.level = .normal
                    window.isMovableByWindowBackground = false
                }
                
                // 🎯 核心新增：改变尺寸后，立刻将窗口放回屏幕中心！
                window.center()
            }
            // 底色与标题栏按钮归 applyWindowChrome 管，别再在这里分头写 window.backgroundColor。
            applyWindowChrome()
        }
        .onChange(of: player.nowPlayingShown) { _, shown in
            applyWindowChrome()
            
            guard !player.isAutopilotMode,
                  let window = NSApplication.shared.windows.first,
                  let content = window.contentView else { return }
            
            // ⚠️ 这里只负责“不够高就放大”，**不写 window.contentMinSize**：
            // `.windowResizability(.contentSize)` 会按内容 min 尺寸重算下限，命令式设进去会被盖掉。
            // 下限的真值在 NowPlayingView.upperArea 的 minHeight 上。
            if shown {
                if content.frame.height < NowPlayingView.minWindowHeight {
                    sizeBeforeNowPlaying = content.frame.size
                    window.setContentSize(NSSize(width: content.frame.width,
                                                 height: NowPlayingView.preferredWindowHeight))
                    window.center()
                }
            } else if let before = sizeBeforeNowPlaying {
                sizeBeforeNowPlaying = nil
                window.setContentSize(before)
                window.center()
            }
        }
        .onChange(of: player.themeType) { _, newTheme in
            // 🎨 切主题必须重算派生色：以前没有任何入口触发重算，Cmd+T 切到灰白后
            // 拿到的仍然是为纯黑底算的那套高亮色，浅色相直接隐进背景。
            palette.applyTheme(newTheme)
            applyWindowChrome()
            // 主题换了，同一张专辑图算出来的派生色也换了，必须重跑一遍。
            syncAlbumColor()
        }
        // ② 切歌必须重取专辑色。以前这条链挂在 AlbumImageView 上，主界面把那张大专辑图删了之后
        // 就没人调了，于是「切歌颜色不跟着变」；正在播放页自己有 updatePalette，所以只有主界面病。
        .onChange(of: player.albumImages) { _, _ in
            syncAlbumColor()
        }
        // 🌀 Super Shuffle 期间队列是全库大数组，当前歌多半不在显示的那张歌单里，“正在播放”
        // 那行永远看不见。切歌后把两块列表定位到它所属的歌单。
        .onChange(of: player.currentSong?.id) { _, _ in
            guard player.superShuffle, let song = player.currentSong else { return }
            locateForSuperShuffle(song)
        }
        // 关掉 Super Shuffle 后队列还原为打开前那张，选中项必须跟着回去，
        // 否则左列还停在随机落点、右块和真实队列两张皮。
        .onChange(of: player.superShuffle) { _, on in
            if !on { syncSelectionToCurrentQueue() }
        }
        .background(
            Group {
                if !player.isAutopilotMode {
                    if player.nowPlayingShown {
                        if player.themeType == "black" {
                            ZStack {
                                Rectangle().fill(Color.black)
                                Rectangle().fill(palette.bgPalette).opacity(0.20)
                            }
                            .ignoresSafeArea(.container, edges: .top)
                        } else {
                            // 🎨 灰白主题底色：顶部压一层主题色的互补色淡 tint，往下衰减。
                            // tint 与页面等亮度，所以不会动到任何已解好的对比度；具体三个约束见
                            // PaletteManager.backgroundGradient。
                            palette.backgroundGradient
                                .ignoresSafeArea(.container, edges: .top)
                        }
                    } else {
                        // ① 主界面底色：黑主题纯黑。专辑色不再糊满整块底，改由右块面板与控制条自己涂
                        //（见 panelFill / barFill），左列则干脆与底同色，看起来就是「浮在左方」。
                        // 仍然 ignoresSafeArea(.top)：标题栏那条透明区域也归这块底管。
                        mainBaseColor.ignoresSafeArea(.container, edges: .top)
                    }
                }
            }
        )
    }
    
    /// 进「正在播放」。
    ///
    /// 以前这里会把主题强压回 black（退出时也一样），目的是让主界面永远是黑底。但那一压
    /// 会在 `nowPlayingShown` 的 0.25s 过渡动画还没走完时同时改主题，palette 重算 ink、
    /// 唱片与光柱配色跟着中途翻面，看着就是“鬼畜”。现在改成主题全程不变：
    /// 在哪页选的颜色就带着它走，回主界面再进来仍是那一套。
    /// 启动时先到黑这件事由 `PlayerManager.themeType` 的默认值保证，不靠这里压。
    private func enterNowPlaying() {
        player.nowPlayingShown = true
    }
    
    /// 焦点是否落在文本输入上。
    ///
    /// SwiftUI 的 TextField 在 macOS 背后是 NSTextField，而真正接键盘的是它的
    /// **字段编辑器**（窗口共享的一个 NSTextView），所以 firstResponder 两种形态都要算：
    /// 编辑中是 NSTextView，刚点进去还没编辑是 NSTextField。输入法组词中的空格、回车
    /// 全部由这条链路处理，这里只负责判断“现在是不是在打字”。
    private static func isTextEditing() -> Bool {
        guard let responder = NSApplication.shared.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
    
    // MARK: - 窗口外框与专辑色
    
    /// 窗口外框按模式切换。主视图要「标题栏 + 三个控制按钮」；正在播放页与极简模式仍旧把按钮藏起来
    /// —— 那两页的内容本来就画到标题栏底下（唱片要占满上沿、极简条只有 150 高），按钮浮在上面会打架。
    /// 标题栏本身一直是透明的（.windowStyle(.hiddenTitleBar) 给的 fullSizeContentView），
    /// 所以「恢复标题栏」＝把按钮放回来 + 底色压成纯黑，而不是让系统那条灰白标题栏现形。
    private func applyWindowChrome() {
        guard let window = NSApplication.shared.windows.first else { return }
        let showChrome = !player.isAutopilotMode && !player.nowPlayingShown
        window.titlebarAppearsTransparent = true
        // 标题文字保持 hidden：App 没在别处设过窗口标题，.visible 会把 App 名“MacSpectrum”显在
        // 标题栏上，与内容区那个可拖窗的 macSpectrum 字样撞成两份标题。用户要恢复的是
        // 「标题栏那条底 + 三个控制按钮」，不含文字。想显出来只改这一行。
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = !showChrome
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !showChrome
        window.standardWindowButton(.zoomButton)?.isHidden = !showChrome
        window.backgroundColor = player.isAutopilotMode
            ? .clear
            : (player.themeType == "black" ? .black : .windowBackgroundColor)
    }
    
    /// 专辑图 → 主题色 + 控制条那颗小封面。切歌、切主题、启动都要走这里。
    private func syncAlbumColor() {
        if let image = palette.applyAlbumImages(player.albumImages, themeType: player.themeType) {
            player.nowAlbum = image
        }
    }
    
    // MARK: - 主体：左列 + 右块 + 控制条
    
    /// 按 QQ 音乐那张图分三块：
    /// ① 左列（登录用户 + 歌单）纯黑，与窗口底色同色，看起来就是「浮在主界面的左方」；
    /// ② 右块（搜索框 + 歌单名 + 歌曲列表）一块圆角面板，底色随专辑；
    /// ③ 控制条 另一块圆角面板，底色同样随专辑。
    /// 三块之间靠 panelGap 的缝分开；窗口本身仍然是黑的（见 body 的 .background），标题栏那条也是黑的。
    private var mainColumns: some View {
        HStack(spacing: 0) {
            leftColumn
            rightColumn
        }
        .frame(minWidth: Self.minColumnWidth,
               idealWidth: Self.idealColumnWidth,
               maxWidth: .infinity,
               minHeight: Self.minColumnHeight,
               idealHeight: Self.idealColumnHeight,
               maxHeight: .infinity)
    }
    
    private var leftColumn: some View {
        VStack(spacing: 0) {
            MainUserCell(palette: palette)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)
            playlistList
        }
        .frame(width: Self.playlistColumnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(mainBaseColor)
    }
    
    private var rightColumn: some View {
        VStack(spacing: panelGap) {
            contentPanel
            barPanel
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var contentPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MainSearchBar(player: player,
                              palette: palette,
                              allSongs: player.allSongs,
                              onPick: locateAndPlay,
                              query: $query)
                Spacer(minLength: 12)
                SpectrumWordmark(palette: palette)
            }
            .padding(.horizontal, panelPadding)
            .frame(height: 52)
            // ⚠️ 下拉挂在搜索框自己的 overlay 上往下长，而 VStack 里后声明的兄弟会画在先声明兄弟的
            // 溢出内容之上 —— 不给这一行抬 zIndex，下拉一展开就被歌单名和列表盖掉半截。
            .zIndex(1)
            
            playlistTitle
            songList      // 表头在 songList 里自带着，这里不能再挂一次 songListHeader
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelFill,
                    in: RoundedRectangle(cornerRadius: panelCorner, style: .continuous))
    }
    
    private var barPanel: some View {
        PlaybackControlBar(player: player,
                           palette: palette,
                           onExit: nil,
                           onAlbumTap: { enterNowPlaying() },
                           trailingControl: .superShuffle,
                           showsTopDivider: false,
                           drawsSurface: false)
            .background(barFill,
                        in: RoundedRectangle(cornerRadius: panelCorner, style: .continuous))
    }
    
    /// 右块面板底：黑底上压一层专辑色。0.18 是「一眼看出换了专辑」和「白字仍然 ≥ 12:1」的折中，
    /// 想更浓就往上加，低于 0.10 基本看不出在变。
    private var panelFill: Color {
        palette.surface.isLight ? palette.bgPalette.opacity(0.12) : palette.bgPalette.opacity(0.18)
    }
    
    /// 控制条比面板再浓一档，上下两块才分得开。
    private var barFill: Color {
        palette.surface.isLight ? palette.bgPalette.opacity(0.18) : palette.bgPalette.opacity(0.26)
    }
    
    /// 主界面底（整块底 + 左列共用一个值，所以左列读起来是「浮在主界面左方」而不是拼了一块黑斑）。
    /// 不能当作黑主题专属写死成 `Color.black`：浅主题下 `textPrimary` 是接近黑的深灰（见
    /// PaletteManager.textPrimary），黑底配深墨字会直接隐没，所以必须跟着 surface 分叉。
    private var mainBaseColor: Color {
        palette.surface.isLight ? palette.surface.background : Color.black
    }
    
    /// ④ 搜索框下方那块空档拿来放歌单名，字号明显大于列表 —— 它是这一块的标题。
    private var playlistTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(selectedPlaylist?.name ?? player.currentPlaylistName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, panelPadding)
        .padding(.top, 2)
        .padding(.bottom, 16)
    }
    
    // MARK: - 左列：歌单
    
    private var playlistList: some View {
        VStack(spacing: 0) {
            // ③ 「歌单列表」小标题去掉：登录用户与歌单同属左列那一块黑底，不需要再开一个列标题。
            // 列内容本身本轮不动（用户说的）。
            ScrollViewReader { proxy in
                List(playlists) { playlist in
                    let selected = selectedPlaylist?.id == playlist.id
                    HStack(spacing: 10) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selected ? palette.bgPalette : palette.textSecondary)
                            .frame(width: 20)
                        Text(playlist.name)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular, design: .rounded))
                            .foregroundColor(selected ? palette.bgPalette : palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? palette.bgPalette.opacity(0.16) : Color.clear)
                    )
                    // 置灰不再整块盖在 List 上：Super Shuffle 要联动定位到当前歌所在歌单，
                    // 选中那行保持满不透明度，才能读出“随机落在这张里”；其余行照旧置灰。
                    .opacity(player.superShuffle && !selected ? 0.4 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 🌀 Super Shuffle 期间整块锁定：不能靠 .disabled（行是 onTapGesture
                        // 实现的，.disabled 对手势无效），只能在动作里挡。
                        guard !player.superShuffle else { return }
                        selectedPlaylist = playlist
                        player.loadPlaylist(songs: playlist.songs, name: playlist.name)
                        metadata.scan(playlist.songs)
                        albumArt.warm(playlist.songs)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedPlaylist?.id) { _, newID in
                    guard let targetID = newID else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
                .onAppear {
                    if let currentID = selectedPlaylist?.id {
                        proxy.scrollTo(currentID, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - 右块：歌曲列表（封面 + 五列）
    
    private var songList: some View {
        VStack(spacing: 0) {
            songListHeader
            
            ScrollViewReader { proxy in
                List(selectedPlaylist?.songs ?? []) { song in
                    songRow(song)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: player.currentSong?.id) { _, newID in
                    guard let targetID = newID else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
                .onChange(of: pendingScrollSong) { _, target in
                    guard let target else { return }
                    // 先清待办再滑：不清的话每次重算 body 都会再滚一次。
                    pendingScrollSong = nil
                    // ⚠️ 异步一拍：Super Shuffle 联动时 selectedPlaylist 是同一轮里换掉的，
                    // 这一拍 List 还是旧内容、目标行根本不存在，同步 scrollTo 找不到锚点会直接空转。
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    if let currentID = player.currentSong?.id {
                        proxy.scrollTo(currentID, anchor: .center)
                    }
                }
            }
        }
    }
    
    private func songRow(_ song: Song) -> some View {
        let nowPlaying = player.currentSong?.id == song.id
        let hovered = hoveredSong == song.id
        return HStack(spacing: colGap) {
            cover(for: song, playing: nowPlaying && player.isPlaying)
            Text(song.songTitle)
                .font(.system(size: 16, weight: nowPlaying ? .semibold : .regular, design: .rounded))
                .foregroundColor(nowPlaying ? palette.bgPalette : palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(song.artist)
                .font(.system(size: 14))
                .foregroundColor(nowPlaying ? palette.bgPalette : palette.textSecondary)
                .lineLimit(1)
                .frame(width: colArtist, alignment: .leading)
            Text(song.album)
                .font(.system(size: 14))
                .foregroundColor(nowPlaying ? palette.bgPalette : palette.textSecondary)
                .lineLimit(1)
                .frame(width: colAlbum, alignment: .leading)
            Text(durationText(for: song))
                .font(.system(size: 14, design: .rounded))
                .monospacedDigit()
                .foregroundColor(nowPlaying ? palette.bgPalette : palette.textSecondary)
                .frame(width: colDuration, alignment: .trailing)
            Text(sizeText(for: song))
                .font(.system(size: 14, design: .rounded))
                .monospacedDigit()
                .foregroundColor(nowPlaying ? palette.bgPalette : palette.textSecondary)
                .frame(width: colSize, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground(playing: nowPlaying, hovered: hovered))
        // 同上：置灰从整块 List 改到逐行，大随机时当前那一行不被抹深，
        // 封面小光柱与主题色歌名才能完整读出“正在播”。
        .opacity(player.superShuffle && !nowPlaying ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !player.superShuffle else { return }
            player.play(song: song)
        }
        .onHover { inside in
            // 只认「离开的是自己」这一种情况清 hover：LazyVStack 复用行时，
            // 新行的 inside=true 会晚于旧行的 inside=false 到达，无脑置 nil 会把高亮丢掉。
            if inside {
                hoveredSong = song.id
            } else if hoveredSong == song.id {
                hoveredSong = nil
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .id(song.id)
    }
    
    /// 选中行是主题色胶囊，hover 行只加一层极淡的底 + 一道软影 —— 用户明确「不要表格线，
    /// 鼠标滑上去加个淡淡的阴影就行」。两者可以叠加，所以这里分先后：选中优先。
    @ViewBuilder
    private func rowBackground(playing: Bool, hovered: Bool) -> some View {
        if playing {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.bgPalette.opacity(0.16))
        } else if hovered {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.surface.isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.06))
                .shadow(color: .black.opacity(palette.surface.isLight ? 0.10 : 0.45), radius: 5, y: 2)
        } else {
            Color.clear
        }
    }
    
    /// 封面列。真正在播的那一行不显示封面，改成黑底 + 四根白条的小光柱
    ///（用户拿 QQ 正在播放里 Funky Stars 那行做的参照）。“播放时”按字面理解成
    /// isPlaying 而不是 currentSong：暂停时 AudioManager 不再发数据，光柱会卡在最后一帧的
    /// 高度上，看着像卡死，不如把封面还回来。当前行靠文字色与行底那层高亮区分，不丢。
    /// 确实没专辑图的歌一律走 Albumdefault：thumbnail 现在非可选，不再自造灰底音符占位。
    @ViewBuilder
    private func cover(for song: Song, playing: Bool) -> some View {
        ZStack {
            if playing {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black)
                MiniSpectrumBars(audio: player.spectrum)
            } else {
                Image(nsImage: albumArt.thumbnail(for: song))
                    .resizable().aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: colCover, height: colCover)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    
    private var songListHeader: some View {
        HStack(spacing: colGap) {
            Color.clear.frame(width: colCover, height: 1)
            Text("歌名").frame(maxWidth: .infinity, alignment: .leading)
            Text("艺术家").frame(width: colArtist, alignment: .leading)
            Text("专辑").frame(width: colAlbum, alignment: .leading)
            Text("时长").frame(width: colDuration, alignment: .trailing)
            Text("大小").frame(width: colSize, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundColor(palette.textSecondary)
        // ⚠️ 20 不是 12：数据行吃的是 listRowInsets(8) + padding(12)，而表头不在 List 里、
        // 拿不到那 8pt insets。写 12 的话表头会比下面每一行往左探出 8pt，六列全错位。
        .padding(.horizontal, 20)
        .frame(height: 30)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }
    
    // MARK: - 列数据格式化
    
    /// 时长由后台扫描回填。没扫到就显示 --:--，不写「未知」—— 那是一列数字，
    /// 混进中文会把等宽对齐打乱。
    private func durationText(for song: Song) -> String {
        guard let seconds = metadata.duration(of: song.url), seconds.isFinite else { return "--:--" }
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    
    /// 大小按 QQ 的写法：6.0M / 14.8M，不足 1M 走 K。
    private func sizeText(for song: Song) -> String {
        guard song.size > 0 else { return "未知" }
        let mb = Double(song.size) / 1_048_576
        if mb >= 1 { return String(format: "%.1fM", mb) }
        return String(format: "%.0fK", Double(song.size) / 1024)
    }
    
    // MARK: - 搜索命中后的联动
    
    /// 三件套：选中它所属的歌单 → 队列换成那个歌单 → 滚动定位并播放。
    private func locateAndPlay(_ song: Song) {
        guard let owner = playlists.first(where: { playlist in
            playlist.songs.contains(where: { $0.id == song.id })
        }) else {
            player.play(song: song)
            return
        }
        selectedPlaylist = owner
        player.loadPlaylist(songs: owner.songs, name: owner.name)
        metadata.scan(owner.songs)
        albumArt.warm(owner.songs)
        pendingScrollSong = song.id
        player.play(song: song)
    }
    
    // MARK: - Super Shuffle 的列表联动
    
    /// 只改视图侧的 selectedPlaylist，**绕开 loadPlaylist** —— 那个会把全库队列换成单张歌单，
    /// 随机逻辑当场就断了。打开大随机时 startSuperShuffle 马上会拉到第一首，
    /// 同一个 onChange 入口就把两块列表定位好，不用另开一处。
    private func locateForSuperShuffle(_ song: Song) {
        guard let owner = playlists.first(where: { playlist in
            playlist.songs.contains(where: { $0.id == song.id })
        }) else { return }
        if selectedPlaylist?.id != owner.id {
            selectedPlaylist = owner
            albumArt.warm(owner.songs)
        }
        pendingScrollSong = song.id
    }
    
    /// 关闭后按队列名对回去：endSuperShuffle 会把 currentPlaylistName 还原为打开前那张。
    /// 名字对不上（比如当时正停在“全部歌曲”）就维持现状，不猜。
    private func syncSelectionToCurrentQueue() {
        guard let match = playlists.first(where: { $0.name == player.currentPlaylistName }) else { return }
        selectedPlaylist = match
    }
    
    /// 进「正在播放」之前的窗口内容尺寸。只有“原本装不下、我确实改大了”才记下来，
    /// 退出时原样还回去；本来就够高的话根本不碰用户的窗口。
    @State private var sizeBeforeNowPlaying: NSSize?
    
    /// 进「极简模式」之前的窗口内容尺寸。极简必定改尺寸（拉到 1100×150），所以退出时
    /// 必须还原成进来之前的那个值，而不是写死 ideal。
    @State private var sizeBeforeAutopilot: NSSize?
}

// MARK: - 播放行的小光柱

/// 正在播那一行封面上的四根白条。拿的不是随机数，是真实频谱的四个采样点，
/// 所以它会跟着音乐动，而不是一个循环动画（用户参照的是 QQ 那行的效果）。
/// 只有这一行包着它，所以 60fps 的重绘只发生在这一行，不会拖整个列表。
private struct MiniSpectrumBars: View {
    @ObservedObject var audio: AudioManager

    /// 四个采样位（右声道）。运行期数组长度是 32，但 init 里按 bandCount=56 填过初值，
    /// 所以下标一律先夹住再取，不赌长度。
    private static let samplePoints = [2, 8, 15, 23]
    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2.5
    private static let maxHeight: CGFloat = 18
    /// 安静时的底高：给 0 会让柱子直接消失，行看起来像没在播。
    private static let minHeight: CGFloat = 2

    private static var totalWidth: CGFloat {
        CGFloat(samplePoints.count) * barWidth + CGFloat(samplePoints.count - 1) * barGap
    }

    var body: some View {
        // 改 Canvas 一笔画完，不再用四根 Shape 各自 `.animation(.linear(duration: 0.07))`：
        // 那个写法报上来的“跳跳动动跨底座”是真因 —— frame 高度变了 SwiftUI 会补间，
        // 而 Shape 的尺寸插值是绕**自身中心**做的，底部对齐却只在布局期成立，
        // 于是 70ms 补间里柱底会自己上下漂半个差值，四根各自漂，基线就散了。
        // Canvas 每个数据帧直接按基线重画，不产生任何隐式动画，底边永远钉在 18pt 处。
        Canvas { context, size in
            for (slot, point) in Self.samplePoints.enumerated() {
                let height = max(Self.minHeight, magnitude(at: point) * Self.maxHeight)
                let rect = CGRect(x: CGFloat(slot) * (Self.barWidth + Self.barGap),
                                  y: size.height - height,
                                  width: Self.barWidth,
                                  height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white))
            }
        }
        .frame(width: Self.totalWidth, height: Self.maxHeight)
    }

    private func magnitude(at index: Int) -> CGFloat {
        let bands = audio.rightMagnitudes
        guard index < bands.count else { return 0 }
        return CGFloat(bands[index])
    }
}
