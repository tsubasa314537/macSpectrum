//
//  SpectrumAnalyser.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/13.
//

import SwiftUI
import Combine

struct SpectrumAnalyser: View {
    @ObservedObject var audio: AudioManager
    @ObservedObject var palette: PaletteManager
    
    private let barWidthWhite:    CGFloat = 6
    private let barWidthBlack:    CGFloat = 10
    
    private let barSpacingWhite:  CGFloat = 10
    private let barSpacingBlack:  CGFloat = 6
    
    private let maxHeight:   CGFloat = 95
    private let minHeight:   CGFloat = 1
    
    @Binding var themeType: String
    
    var body: some View {
        ZStack {
            Color.clear
            HStack(alignment: .bottom, spacing: 0) {
                // ── 左声道 ─────────────────────────────────────────
                HStack(alignment: .bottom, spacing: themeType == "black" ? barSpacingBlack : barSpacingWhite) {
                    ForEach(Array(audio.leftMagnitudes.reversed().enumerated()), id: \.offset) { index, value in
                        bar(value: value, colorPos: 1.0 - Double(index) / Double(audio.leftMagnitudes.count - 1))
                    }
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: themeType == "black" ? barSpacingBlack : barSpacingWhite, height: maxHeight)
                    .padding(.horizontal, 0.1)
                
                // ── 右声道 ─────────────────────────────────────────
                HStack(alignment: .bottom, spacing: themeType == "black" ? barSpacingBlack : barSpacingWhite) {
                    ForEach(audio.rightMagnitudes.indices, id: \.self) { i in
                        bar(value: audio.rightMagnitudes[i], colorPos: Double(i) / Double(audio.rightMagnitudes.count - 1))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 3)
            .padding(.horizontal, 16)
        }
        .frame(minWidth: 1100, minHeight: 150)
    }
    
    // MARK: - 高性能单层能量喷泉（绝对高度像素级渐变修正）
    @ViewBuilder
    private func bar(value: Float, colorPos: Double) -> some View {
        let intensity = CGFloat(max(0.0, min(1.0, value)))
        let height = max(minHeight, intensity * maxHeight)
        let baseColor = palette.color(position: colorPos, intensity: Double(value))
        
        if themeType == "black" {
            // 🚀 【核心巧思】：实时计算当前柱子的高度比例
            // 为了防止极端的边界情况导致除以 0，我们加个安全保护
            let heightRange = maxHeight - minHeight
            let ratio = heightRange > 0 ? (height - minHeight) / heightRange : 0.0
            
            // 🎯 线性映射：将占比 (0.0~1.0) 完美映射到模糊度区间 (3.0 ~ 7.0)
            // 越矮越接近 3.0 (清晰)，越高越接近 7.0 (高能模糊)
            //        let blurRadius = 3.0 + (Double(ratio) * (7.0 - 3.0))
            
            let blurRadius =
            themeType == "black" ?
            
            //尚可(对86度角)
            6.0 + (Double(ratio) * (-4.0))
            
            //OK(3,7)(对85度角)
            //        7.0 + (Double(ratio) * (-4.0))
            
            :
            
            3.0 + (Double(ratio) * (-2.0))
            
            
            SmoothPentagon()
                .fill(baseColor)
                .frame(width: barWidthBlack)
                .frame(height: height)
            // 将自适应模糊挂载在最下面，并且跟随 value（或者高度）同步丝滑渐变！
                .blur(radius: blurRadius)
            //            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.7, blendDuration: 0), value: value)
                .animation(
                    .spring(
                        response: 0.15,
                        dampingFraction: 1.0,
                        blendDuration: 0
                    ),
                    value: value
                )
        } else {
            QQCompositeEnergyBar(
                height: height,
                intensity: intensity,
                barWidth: barWidthWhite,
                baseColor: baseColor,
                maxH: maxHeight,
                minH: minHeight
            )
        }
        

    }
    
    
    struct SmoothPentagon: Shape {
        // 尖角底部的夹角（默认 75 度）
        var baseAngle: Double = 86.8
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            
            let w = rect.width
            let h = rect.height
            
            // 计算等腰三角形的高度： h = (w/2) * tan(75°)
            // 注意：这里计算的是理论直线高度，用于定位顶点
            let radians = baseAngle * .pi / 180
            let triangleHeight = (w / 2) * tan(radians)
            
            // 关键坐标点
            let topTip = CGPoint(x: w / 2, y: 0) // 顶点
            let leftShoulder = CGPoint(x: 0, y: triangleHeight) // 左肩
            let rightShoulder = CGPoint(x: w, y: triangleHeight) // 右肩
            let bottomLeft = CGPoint(x: 0, y: h) // 左下角
            let bottomRight = CGPoint(x: w, y: h) // 右下角
            
            // 1. 从左下角开始
            path.move(to: bottomLeft)
            
            // 2. 向上画到左肩
            path.addLine(to: leftShoulder)
            
            // 3. 绘制左侧圆滑腰部 (使用二次贝塞尔曲线)
            // 控制点设在左肩上方，稍微向中间靠拢，可以调整圆润度
            let leftControl = CGPoint(x: 0, y: triangleHeight * 0.5)
            path.addQuadCurve(to: topTip, control: leftControl)
            
            // 4. 绘制右侧圆滑腰部
            let rightControl = CGPoint(x: w, y: triangleHeight * 0.5)
            path.addQuadCurve(to: rightShoulder, control: rightControl)
            
            // 5. 向下画到右下角并闭合
            path.addLine(to: bottomRight)
            path.closeSubpath()
            
            return path
        }
    }
}
