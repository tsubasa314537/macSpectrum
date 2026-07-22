//
//  MacSpectrumCanvasView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/5/30.
//

import SwiftUI

import SwiftUI

struct MacSpectrumCanvasView: View {
    @ObservedObject var audio: AudioManager
    
    // ── 🎨 严格对齐您的 Mac 版配置 ──
    let barCount: Int = 48           // 双通道共 96 柱（每边 96 还是总共 96？这里代表单边循环次数，如果您总共 96 柱，单边就是 48。根据您的后置逻辑自行微调）
    let barWidth: CGFloat = 8        // 您最满意的 8 像素宽
    let barSpacing: CGFloat = 4      // 间距
    let maxHeight: CGFloat = 55      // 光柱最大高度
    let minHeight: CGFloat = 2       // 最小高度
    
    let blurRadius: CGFloat = 5      // 近视眼朦胧滤镜半径
    
    // 颜色主题
    let lowColor = Color(hue: 0.85, saturation: 1.0, brightness: 1.0)  // 低频中心侧
    let highColor = Color(hue: 0.55, saturation: 0.8, brightness: 1.0) // 高频外侧
    
    var body: some View {
        // 1️⃣ 第一步：完美继承您原版的 ZStack 容器，保证上面的组件该怎么顶就怎么顶
        ZStack {
            Color.clear
            
            // 2️⃣ 第二步：把 Canvas 塞进这个容器里，让它成为原版 HStack 的完美替身
            Canvas { context, size in
                // 开启 GPU 级别高斯模糊
                context.addFilter(.blur(radius: blurRadius))
                
                let totalWidth = size.width
                let centerX = totalWidth / 2
                
                // 🔒 智能降级安全锁：如果后端数组还没初始化好，或者长度不够，咱们不要交白卷，而是画一排静止的 minHeight 光柱，防止界面黑掉！
                let leftMagnitudes = audio.leftMagnitudes
                let rightMagnitudes = audio.rightMagnitudes
                let hasData = leftMagnitudes.count >= barCount && rightMagnitudes.count >= barCount
                
                // ── 右声道绘制 ──
                for i in 0..<barCount {
                    // 如果有数据就读数据，没数据就用 0 站位（保证静止时也能看见大排灯底座）
                    let rawValue = hasData ? rightMagnitudes[i] : 0
                    
                    let basePos = Double(i) / Double(barCount - 1)
                    let dynamicColorPos = basePos * 0.85 + Double(rawValue) * 0.15
                    let blendedColor = Color.lerp(from: lowColor, to: highColor, t: dynamicColorPos)
                    
                    let currentHeight = max(minHeight, CGFloat(rawValue) * maxHeight)
                    let xPos = centerX + CGFloat(i) * (barWidth + barSpacing) + barSpacing / 2
                    if xPos + barWidth > totalWidth { break }
                    
                    // 📐 核心对齐：贴着当前实际 size.height 的底部往上画
                    let barRect = CGRect(x: xPos, y: size.height - currentHeight, width: barWidth, height: currentHeight)
                    context.fill(Path(barRect), with: .color(blendedColor))
                }
                
                // ── 左声道绘制 ──
                for i in 0..<barCount {
                    let rawValue = hasData ? leftMagnitudes[i] : 0
                    
                    let basePos = Double(i) / Double(barCount - 1)
                    let dynamicColorPos = basePos * 0.85 + Double(rawValue) * 0.15
                    let blendedColor = Color.lerp(from: lowColor, to: highColor, t: dynamicColorPos)
                    
                    let currentHeight = max(minHeight, CGFloat(rawValue) * maxHeight)
                    let xPos = centerX - CGFloat(i) * (barWidth + barSpacing) - barSpacing / 2 - barWidth
                    if xPos < 0 { break }
                    
                    let barRect = CGRect(x: xPos, y: size.height - currentHeight, width: barWidth, height: currentHeight)
                    context.fill(Path(barRect), with: .color(blendedColor))
                }
            }
            // 3️⃣ 第三步：把您原汁原味的布局控制符一字不落地拍在 Canvas 屁股后面！
            // 这样 Canvas 就会像原版的 HStack 一样，死死地贴在底部，并且吃满多余空间！
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 20)
            .padding(.horizontal, 16)
        }
        // 4️⃣ 第四步：完美对齐您的 Mac 窗口最小宽度与高度保障！
        .frame(minWidth: 1100, minHeight: 150)
        .allowsHitTesting(false)
    }
}

// ── 🛠️ 超高性能颜色线性插值工具（免去 ColorPicker 树重绘开销） ──
extension Color {
    static func lerp(from start: Color, to end: Color, t: Double) -> Color {
        // 限制 t 在 0...1
        let pct = max(0, min(1, t))
        
        // 转换为原生 NSColor/UIColor 解析三原色
#if os(macOS)
        let nsStart = NSColor(start)
        let nsEnd = NSColor(end)
#else
        let nsStart = UIColor(start)
        let nsEnd = UIColor(end)
#endif
        
        let r = nsStart.redComponent + (nsEnd.redComponent - nsStart.redComponent) * CGFloat(pct)
        let g = nsStart.greenComponent + (nsEnd.greenComponent - nsStart.greenComponent) * CGFloat(pct)
        let b = nsStart.blueComponent + (nsEnd.blueComponent - nsStart.blueComponent) * CGFloat(pct)
        let a = nsStart.alphaComponent + (nsEnd.alphaComponent - nsStart.alphaComponent) * CGFloat(pct)
        
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}
