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
    
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylist: Playlist?
    
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
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        playlistView
                            .frame(width: 267)
                        
                        songListView
                        
                        albumView
                            .frame(width: 250)
                    }
                    
//                    Divider()
                    
                    // 原底部的 SpectrumAnalyser 已迁移到 NowPlayingView，这里换成播控条。
                    controlBar
                }
                .frame(width: 1050, height: 600)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.nowPlayingShown)
        // 🚀 牢牢把全局监听挂在最外层 ZStack 壳子上，无论内部如何切换自动驾驶，快捷键永不失效！
        .onAppear {
            if let window = NSApplication.shared.windows.first {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
            
            let lrcDic = PlaylistLoader.loadLyrics(from: player.lyricsURL.path)
            playlists = PlaylistLoader.load(from: player.songsURL.path, in: lrcDic)
            if let first = playlists.first {
                selectedPlaylist = first
                player.loadPlaylist(songs: first.songs, name: first.name)
            }
            
            // 🎨 启动时先把当前主题同步给 palette，保证 ink 从一开始就是对着正确底色派生出来的。
            palette.applyTheme(player.themeType)
            
            // 全局快捷键大总管
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
//                print("code===\(event.keyCode)")
                switch event.keyCode {
                    case 8:
                        if player.isAutopilotMode && modifiers == .command {
                            if player.themeType == "black" {
                                player.themeType = "white"
                            } else {
                                player.themeType = "black"
                            }
                            return nil
                        }
                        
                        return event
                    case 45: // Cmd + N：从主视图进入 Now Playing
                        if modifiers == .command && !player.isAutopilotMode && !player.nowPlayingShown {
                            player.nowPlayingShown = true
                            return nil
                        }
                        return event
                    case 53: // Esc：从 Now Playing 返回主视图，同时主题恢复 black。
                        if player.nowPlayingShown {
                            player.nowPlayingShown = false
                            player.themeType = "black"
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
                    case 17: // Cmd + T（仅在 Now Playing 下生效）
                        if !player.isAutopilotMode && player.nowPlayingShown && modifiers == .command {
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
                    case 100, 49: // F8 或 空格
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
            
            if isAutopilot {
                palette.startAutopilotColors()
            } else {
                palette.stopAutopilotColors()
            }
            
            if let window = NSApplication.shared.windows.first {
                if isAutopilot {
                    window.setContentSize(NSSize(width: 1100, height: 150))
                    window.isOpaque = true
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.level = .floating
                    window.isMovableByWindowBackground = true
                } else {
                    window.setContentSize(NSSize(width: 1300, height: 600))
                    window.isOpaque = true
                    window.backgroundColor = .windowBackgroundColor
                    window.hasShadow = true
                    window.level = .normal
                    window.isMovableByWindowBackground = false
                }
                
                // 🎯 核心新增：改变尺寸后，立刻将窗口放回屏幕中心！
                window.center()
            }
        }
        .onChange(of: player.themeType) { _, newTheme in
            // 🎨 切主题必须重算派生色：以前没有任何入口触发重算，Cmd+T 切到灰白后
            // 拿到的仍然是为纯黑底算的那套高亮色，浅色相直接隐进背景。
            palette.applyTheme(newTheme)
        }
        .background(
            Group {
                if !player.isAutopilotMode {
                    if player.themeType == "black" {
                        ZStack {
                            Rectangle().fill(Color.black)
                            Rectangle().fill(palette.bgPalette).opacity(0.20)
                        }
                        .ignoresSafeArea(.container, edges: .top)
                    } else {
                        // 🎨 灰白主题底色：方案 A 从 #BFBFBF 提到近白（#F4F4F6）。
                        // 极淡的 wash 只有在高亮底上才“长”得出来，这正是对标 QQ 音乐的前提。
                        // 旧的「专辑图 blur(radius:30) + opacity(0.2)」模糊层已移除，日后重新设计配色时再说。
                        ThemeSurface.light.background
                            .ignoresSafeArea(.container, edges: .top)
                    }
                }
            }
        )
    }
    
    private var playlistView: some View {
        ScrollViewReader { proxy in
            List(playlists) { playlist in
                let selected = selectedPlaylist?.id == playlist.id
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selected ? palette.bgPalette : secondaryColor)
                        .frame(width: 20)
                    Text(playlist.name)
                        .font(.system(size: 15, weight: selected ? .semibold : .regular, design: .rounded))
                        .foregroundColor(selected ? palette.bgPalette : primaryColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? palette.bgPalette.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPlaylist = playlist
                    if let plylst = selectedPlaylist?.songs {
                        player.loadPlaylist(songs: plylst, name: playlist.name)
                    }
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
    
    private var songListView: some View {
        ScrollViewReader { proxy in
            List(selectedPlaylist?.songs ?? []) { song in
                let nowPlaying = player.currentSong?.id == song.id
                HStack(spacing: 10) {
                    Image(systemName: nowPlaying ? "speaker.wave.2.fill" : "music.note")
                        .font(.system(size: 12))
                        .foregroundColor(nowPlaying ? palette.bgPalette : secondaryColor)
                        .frame(width: 20)
                    Text(song.title)
                        .font(.system(size: 15, weight: nowPlaying ? .semibold : .regular, design: .rounded))
                        .foregroundColor(nowPlaying ? palette.bgPalette : primaryColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(nowPlaying ? palette.bgPalette.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    player.play(song: song)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .id(song.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: player.currentSong?.id) { _, newID in
                guard let targetID = newID else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
            .onAppear {
                if let currentID = player.currentSong?.id {
                    proxy.scrollTo(currentID, anchor: .center)
                }
            }
        }
    }
    
    // 🎨 主/次文字色：黑主题白字；灰白主题底色提到近白后，用接近黑的深灰代替纯黑、
    // 中灰代替 0.55 黑，避免大面积15pt 正文在白底上过于死硬。
    private var primaryColor: Color {
        player.themeType == "black" ? .white : Color(white: 0.12)
    }
    private var secondaryColor: Color {
        player.themeType == "black" ? Color.white.opacity(0.55) : Color(white: 0.42)
    }
    
    private var albumView: some View {
        VStack {
            Text("macSpectrum")
                .font(.system(size: 28, weight: .semibold))
                .bold()
                .foregroundColor(palette.bgPalette)
                .padding(.top, 30)
            
            AlbumImageView(
                images: player.albumImages,
                palette: palette,
                player: player,
                themeType: $player.themeType
            )
            .id(player.currentSong?.id)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
            
            if let song = player.currentSong {
                let parts = song.title.components(separatedBy: " - ")
                VStack(spacing: 2) {
                    Text(parts.count >= 2 ? parts[1].trimmingCharacters(in: .whitespaces) : song.title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(player.themeType == "black" ? .white : .black)
                        .lineLimit(1)
                    Text(parts.count >= 2 ? parts[0].trimmingCharacters(in: .whitespaces) : "未知歌手")
                        .font(.system(size: 14))
                        .foregroundColor(player.themeType == "black" ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
            Spacer()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    NSApp.keyWindow?.performDrag(with: NSApp.currentEvent!)
                }
        )
    }
    
    // MARK: - 播控条（取代原本主视图底部的 SpectrumAnalyser）
    private var controlBar: some View {
        HStack(spacing: 40) {
            Button(action: { player.previousTrack() }) {
                Image(systemName: "backward.fill").font(.title)
            }
            Button(action: { player.isPlaying ? player.pause() : player.resume() }) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
            }
            Button(action: { player.nextTrack() }) {
                Image(systemName: "forward.fill").font(.title)
            }
        }
        // macOS 默认 ButtonStyle 是 bordered，会带上一圈浅色背景；这里改为 plain 去掉背景。
        .buttonStyle(.plain)
        .foregroundColor(palette.bgPalette)
        .padding()
    }
}
