//
//  AlbumImageView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import SwiftUI

struct AlbumImageView: View {
    
    let images: [NSImage]
    
    @State private var currentIndex = 0
    @State private var rotationTimer: Timer?
    
    @ObservedObject var palette: PaletteManager
    @ObservedObject var player: PlayerManager
    
    @Binding var themeType: String
    
    // 多张图时自动轮播间隔（秒）
    private let rotationInterval: TimeInterval = 5.0
    
    var body: some View {
        Group {
            if images.indices.contains(currentIndex) {
                Image(nsImage: images[currentIndex])
                    .resizable()
            } else {
                Image("Albumdefault")
                    .resizable()
            }
        }
        .onAppear {
//            startRotationIfNeeded()
            updatePalette()
        }
        .onDisappear {
            stopRotation()
        }
        // 外部 images 变化（切歌）时重置到第一张并重启计时器
        .onChange(of: images) { _, _ in
            currentIndex = 0
            stopRotation()
            startRotationIfNeeded()
            updatePalette()
        }
        
        .onChange(of: themeType) {
//            print("changed:=========\(themeType)")
            updatePalette()
        }
    }
    
    private func startRotationIfNeeded() {
        guard images.count > 1 else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationInterval,
                                             repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex = (currentIndex + 1) % images.count
            }
        }
    }
    
    private func stopRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
    
    private func updatePalette() {
        var image = NSImage(named: "Albumdefault")
        if !player.albumImages.isEmpty {
            let random = Int.random(in: 0..<player.albumImages.count)
            image = player.albumImages[random]
        }
        
        player.nowAlbum = image
      
        // ── macOS 架构 ──
#if os(macOS)
        if let albumImage = image,
         let avgNSColor = albumImage.averageColor {
            // 1. 让背景分析器换上提取出来的真·平均色
            let extractedColor = Color(avgNSColor)
            // 2. 直接切到新的专辑配色，不走 1.8s 渐变。
            // 以前这里写的是 animated: player.isAutopilotMode，但 updateAlbumColor 开头就是
            // `if isAutopilotActive { return }`——autopilot 开着的时候这个调用根本不会执行，
            // 所以那个表达式永远只在 false 时生效。颜色渐变实际只由 startAutopilotColors
            // 每 5s 一次的 triggerRandomAutopilotBlend 驱动，与专辑色无关。
            palette
                .updateAlbumColor(
                    extractedColor,
                    themeType,
                    animated: false
                )
        }
#else
        // ── iOS 架构 ──
        if let uiImage = UIImage(contentsOfFile: imagePath) {
            colorSelector.updatePalette(from: uiImage)
            let extractedColor = colorSelector.backgroundColor
            // iOS 分支同理：换歌直接变色，渐变留给 autopilot。
            palette.updateAlbumColor(extractedColor, themeType, animated: false)
        }
#endif
    }
}
