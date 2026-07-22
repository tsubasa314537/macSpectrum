//
//  MainPlayerView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import SwiftUI
import AppKit

struct MainPlayerView: View {
    
    // 🚀 彻底改为 @ObservedObject 接收主入口传入的唯一真实实例，绝不多开实例！
    @ObservedObject var player: PlayerManager
    @StateObject private var lyricManager = LyricManager()
    
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylist: Playlist?
    @ObservedObject var palette: PaletteManager
//    @State private var remoteHandler = MediaRemoteHandler()
    
    let rootPath = "/Users/guopeng/Documents/spectrumplayer/songs"
    let lrcPath = "/Users/guopeng/Documents/spectrumplayer/lyrics"
    
    var body: some View {
        // 🚀 用一个大外壳包裹，确保生命周期（.onAppear）在全软件运行期间只加载一次，永不被摧毁
        ZStack {
            HStack(spacing: 0) {
                if player.isAutopilotMode {
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
                            themeType: $player.themeType
                        )
                        .frame(height: 150)
                        .padding(.vertical, 0)
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            playlistView
                                .frame(width: 200)
                            
                            songListView
                            
                            albumView
                                .frame(width: 250)
                        }
                        
                        Divider()
                        themeSelector
                        Divider()
                        
                        SpectrumAnalyser(
                            audio: player.spectrum,
                            palette: palette,
                            themeType: $player.themeType
                        )
                        .frame(height: 150)
                        .padding(.vertical, 0)
                    }
                    .frame(width: 1000, height: 600)
                    
                    Divider()
                    
                    LyricView(
                        lyricManager: lyricManager,
                        player: player,
                        themeType: $player.themeType,
                        palette: palette
                    )
                    .onAppear {
                        if let title = player.currentSong?.title {
                            lyricManager.loadLyric(for: title)
                        }
                    }
                    .frame(width: 300)
                    .background(Color.clear)
                }
            }
        }
        // 🚀 牢牢把全局监听挂在最外层 ZStack 壳子上，无论内部如何切换自动驾驶，快捷键永不失效！
        .onAppear {
            if let window = NSApplication.shared.windows.first {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
            
//            remoteHandler.onPrevious  = { player.previousTrack() }
//            remoteHandler.onPlayPause = { player.isPlaying ? player.pause() : player.resume() }
//            remoteHandler.onNext      = { player.nextTrack() }
            
            let lrcDic = PlaylistLoader.loadLyrics(from: lrcPath)
            playlists = PlaylistLoader.load(from: rootPath, in: lrcDic)
            if let first = playlists.first {
                selectedPlaylist = first
                player.loadPlaylist(songs: first.songs)
            }
            
            // 全局快捷键大总管
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                
                switch event.keyCode {
                    case 40: // Cmd + K
                        if modifiers == .command && player.isAutopilotMode {
                            player.karaoke.toggle()
                            return nil
                        }
                        return event
                    case 9: // Cmd + V
                        if modifiers == .command {
                            player.isAutopilotMode.toggle()
                            return nil
                        }
                        return event
                    case 17: // Cmd + T
                        if !player.isAutopilotMode && modifiers == .command {
                            player.standardTheme.toggle()
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
            }
        }
        .background(
            Group {
                if !player.isAutopilotMode {
                    if player.themeType == "black" {
                        ZStack {
                            Rectangle().fill(Color.black.opacity(0.2))
                            Rectangle().fill(palette.bgPalette).opacity(0.15)
                        }
                        .ignoresSafeArea(.container, edges: .top)
                    } else {
                        ZStack {
                            Color(red: 0.85, green: 0.85, blue: 0.85)
                            if let img = player.nowAlbum {
                                Image(nsImage: img)
                                    .resizable()
                                    .blur(radius: 40, opaque: true)
                                    .opacity(0.2)
                                    .scaledToFill()
                            }
                        }
                        .clipped()
                    }
                }
            }
        )
    }
    
    private var playlistView: some View {
        List(playlists) { playlist in
            let selected = selectedPlaylist?.id == playlist.id
            Text(selected ? "\(playlist.name)  •" : playlist.name)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(forColor(nowPlaying: selected))
                .onTapGesture {
                    selectedPlaylist = playlist
                    if let plylst = selectedPlaylist?.songs {
                        player.loadPlaylist(songs: plylst)
                    }
                }
                .cornerRadius(8)
                .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
    }
    
    private var songListView: some View {
        ScrollViewReader { proxy in
            List(selectedPlaylist?.songs ?? []) { song in
                let nowPlaying = player.currentSong?.id == song.id
                Text(nowPlaying ? "\(song.title)  ▶︎" : song.title)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(forColor(nowPlaying: nowPlaying))
                    .onTapGesture {
                        player.play(song: song)
                    }
                    .listRowBackground(Color.clear)
                    .id(song.id)
            }
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
    
    private func forColor(nowPlaying: Bool) -> Color {
        if nowPlaying {
            return palette.bgPalette
        } else {
            return player.themeType == "black" ? Color.white : Color.black
        }
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
    
    private var themeSelector: some View {
        HStack(spacing: 15) {
            Spacer()
            Text("酷黑").foregroundColor(player.themeType == "black" ? .white : .black)
            
            Toggle("", isOn: $player.standardTheme)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(palette.bgPalette)
                .onChange(of: player.standardTheme) { _, select in
                    player.themeType = select ? "white" : "black"
                }
            
            Text("灰白").foregroundColor(player.themeType == "white" ? .black : .white)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
