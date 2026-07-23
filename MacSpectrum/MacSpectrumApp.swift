//
//  MacSpectrumApp.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/13.
//

import SwiftUI

@main
struct MacSpectrumApp: App {
    // 🚀 全局唯一的指挥官单例
    @StateObject private var player: PlayerManager
<<<<<<< HEAD
=======
    
    @StateObject private var lyric: LyricManager
    
>>>>>>> modi
    @StateObject private var palette = PaletteManager()
    
    let songsURL: URL
    let lyricsURL: URL
    
    init() {
        let fileManager = FileManager.default
        let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 动态构建通用路径：~/Documents/spectrumplayer/songs & lyrics
        let baseFolder = docURL.appendingPathComponent("spectrumplayer", isDirectory: true)
        
        let songsDir   = baseFolder.appendingPathComponent("songs", isDirectory: true)
        let lyricsDir  = baseFolder.appendingPathComponent("lyrics", isDirectory: true)
        
        self.songsURL = songsDir
        self.lyricsURL = lyricsDir
        
        // 初始化 PlayerManager，把准备好的路径喂给它
        self._player = StateObject(wrappedValue: PlayerManager(songsURL: songsDir, lyricsURL: lyricsDir))

        self._lyric = StateObject(wrappedValue: LyricManager(path: lyricsDir.path))

    }
    
    var body: some Scene {
        WindowGroup {
            // 🚀 核心关键：必须把这个唯一的 player 和 palette 实体，通过参数强行喂给 MainPlayerView！
            MainPlayerView(
                player: player,
                palette: palette,
                lyricManager: lyric
            )
                .environmentObject(player)
                .environmentObject(palette)
                .environmentObject(lyric)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .toolbar) { }
        }
        
        // ── 🏝️ Mac 专属状态任务栏（保持昨天的精致縮小版不变） ──
        MenuBarExtra {
            Toggle(isOn: $player.isAutopilotMode) {
                Text("极简模式")
            }
            Toggle(isOn: $player.karaoke) {
                Text("卡啦OK")
            }
            .disabled(!player.isAutopilotMode)
            
            Divider()
            
            Button(action: {
                if player.themeType == "black" {
                    player.themeType = "white"
                    player.standardTheme = true
                } else {
                    player.themeType = "black"
                    player.standardTheme = false
                }
            }) {
                HStack {
                    Text(player.themeType == "black" ? "主题: 酷黑" : "主题: 灰白")
                    Image(systemName: player.themeType == "black" ? "moon.fill" : "sun.max.fill")
                }
            }
            
            Divider()
            
            Button("退出 macSpectrum") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            
        } label: {
            if let originalImg = player.albumImages.first,
               let tinyIcon = resizeImage(image: originalImg, targetSize: NSSize(width: 22, height: 22), isAppIcon: false) {
                Image(nsImage: tinyIcon)
            } else {
                defaultAppIconPlaceholder
            }
        }
    }
    
    private var defaultAppIconPlaceholder: some View {
        Group {
            if let rawAppIcon = NSApplication.shared.applicationIconImage,
               let tinyAppIcon = resizeImage(image: rawAppIcon, targetSize: NSSize(width: 22, height: 22), isAppIcon: true) {
                Image(nsImage: tinyAppIcon)
            } else {
                Image(systemName: "waveform.path.ecg")
            }
        }
    }
    
    private func resizeImage(image: NSImage, targetSize: NSSize, isAppIcon: Bool) -> NSImage? {
        if isAppIcon {
            let targetRect = NSRect(origin: .zero, size: NSSize(width: 32, height: 32))
            if let rep = image.bestRepresentation(for: targetRect, context: nil, hints: nil) {
                let matchedImage = NSImage(size: rep.size)
                matchedImage.addRepresentation(rep)
                return scaleAndClipImage(matchedImage, to: targetSize, cornerRadius: 4)
            }
        }
        return scaleAndClipImage(image, to: targetSize, cornerRadius: 3)
    }
    
    private func scaleAndClipImage(_ image: NSImage, to targetSize: NSSize, cornerRadius: CGFloat) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: targetSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
