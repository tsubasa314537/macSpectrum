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
    
    private let barWidthWhite:    CGFloat = 4
    private let barWidthBlack:    CGFloat = 8
    
    private let barSpacingWhite:  CGFloat = 8
    private let barSpacingBlack:  CGFloat = 5
    
    private let maxHeight:   CGFloat = 75
    private let minHeight:   CGFloat = 1
    
    @Binding var themeType: String
    
    // 是否处于 autopilot 极简模式。
    // 色源已由 PaletteManager 按主题派生好（core/wash/accent/glow），此处仅作为上下文透传。
    var isAutopilot: Bool = false
    
    var body: some View {
        ZStack {
            Color.clear

            // 🌊 灰白主题专属：底部一条由透到实的 wash 反光带，柱子像立在水面上。
            // 放在 HStack 之前，所以它始终在柱体下方，不抢识别度。
//            if themeType != "black" {
//                VStack(spacing: 0) {
//                    Spacer(minLength: 0)
//                    LinearGradient(
//                        colors: [palette.barWashColor.opacity(0.0), palette.barWashColor.opacity(0.70)],
//                        startPoint: .top,
//                        endPoint: .bottom
//                    )
//                    .frame(height: 16)
//                    .padding(.bottom, 3)
//                }
//                .allowsHitTesting(false)
//            }

            HStack(alignment: .bottom, spacing: 0) {
                // ── 左声道 ─────────────────────────────────────────
                HStack(alignment: .bottom, spacing: themeType == "black" ? barSpacingBlack : barSpacingWhite) {
                    ForEach(Array(audio.leftMagnitudes.reversed().enumerated()), id: \.offset) { index, value in
                        bar(value: value, colorPos: 1.0 - Double(index) / Double(audio.leftMagnitudes.count - 1),
                            fadeAmt: fadeAmount(distanceFromOuter: index))
                    }
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: themeType == "black" ? barSpacingBlack : barSpacingWhite, height: maxHeight)
                    .padding(.horizontal, 0.1)
                
                // ── 右声道 ─────────────────────────────────────────
                HStack(alignment: .bottom, spacing: themeType == "black" ? barSpacingBlack : barSpacingWhite) {
                    ForEach(audio.rightMagnitudes.indices, id: \.self) { i in
                        bar(value: audio.rightMagnitudes[i], colorPos: Double(i) / Double(audio.rightMagnitudes.count - 1),
                            fadeAmt: fadeAmount(distanceFromOuter: audio.rightMagnitudes.count - 1 - i))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 3)
            .padding(.horizontal, 16)
            .drawingGroup()
        }
        .frame(minWidth: 1100, minHeight: 150)
    }
    
    /// 外侧渐隐的等级：`distanceFromOuter` 从**最外那根**数起（0 = 最外），
    /// 单边前 12 根按 `pow(distance / 12, 0.8)` 指数衰减 —— 最外根 = 0（彻底淡出），
    /// 第 12 根 = 1（满亮度），再往里不衰减。单边 36 根，所以每侧只有最外 12 根参与渐变。
    ///
    /// ⚠️ 两个声道必须用**同一个刻度**：左声道渲染的是 reversed 数组（index 0 就是最外），
    /// 右声道是正序（index 最大才最外）。原先左声道传 `count - index`、右声道直接传 `index`，
    /// 差了整整一根：左边最外是 0 而右边最外是 pow(1/12, 0.8) = 0.155，两条渐隐带对不齐。
    private func fadeAmount(distanceFromOuter: Int) -> Double {
        let bandsToBeFaded = 12
        guard distanceFromOuter < bandsToBeFaded else { return 1 }
        return pow(Double(distanceFromOuter) / Double(bandsToBeFaded), 0.78)
    }
    
    // MARK: - 高性能单层能量喷泉（绝对高度像素级渐变修正）
    @ViewBuilder
    private func bar(value: Float, colorPos: Double, fadeAmt: Double) -> some View {
        let intensity = CGFloat(value)//CGFloat(max(0.0, min(1.32, value)))
        let height = max(minHeight, intensity * maxHeight)
        let baseColor = palette.barColor(
            position: colorPos,
            intensity: Double(value),
            themeType: themeType,
            isAutopilot: isAutopilot
        )
        
        // 🚀 【核心巧思】：实时计算当前柱子的高度比例
        // 为了防止极端的边界情况导致除以 0，我们加个安全保护
        let heightRange = maxHeight - minHeight
        let ratio = heightRange > 0 ? (height - minHeight) / heightRange : 0.0
        
        let blurRadius = 5.0 + (Double(ratio) * (-1.5))
        
        if themeType == "black" {
            
            SmoothPentagon()
                .fill(baseColor.opacity(fadeAmt))
                .frame(width: barWidthBlack)
                .frame(height: height)
                .blur(radius: 1.5, opaque: false)
                // 光晕也乘 fadeAmt：黑主题里柱子的体量几乎全靠这层 glow，只淡 fill 不淡它的话，
                // 外侧那几根会剩一圈全亮的光斑——“明暗差了、轮廓还在”，比不淡更难着。
                .shadow(color: baseColor.opacity(0.8 * fadeAmt), radius: blurRadius, x: 0, y: 0)
//                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.66, blendDuration: 0), value: value)
//                .animation(.snappy(duration: 0.18, extraBounce: 0.18), value: value)
                .animation(.linear(duration: 0.08), value: value)
        } else {
            CompositeEnergyBar(
                height: height,
                intensity: intensity,
                barWidth: barWidthWhite,
                baseColor: baseColor,
                // 变白用 ratio（和 CompositeEnergyBar 内部的 bulge 同一个公式）：
                // 肚子变大与颜色变白必须共用一个驱动量，否则会出现“大肚子但不白”的错帧。
                bellyColor: palette.barBellyColor(whiteness: ratio),
                glowColor: palette.barGlowColor,
                maxH: maxHeight,
                minH: minHeight
            )
            // 光晕分两层，各管一件事：
            // · 柱内的真 blur 跟能量走（radius 与不透明度都由 intensity 驱动）——负责“报的时候胖一圈”，
            //   颜色也全由它提供；
            // · 外层只是一道淡淡的黑色投影，给柱子一个落在背景上的重量感。
            // 颜色不能跑到阴影里：以前用 glow 色做 shadow，会和柱内 blur 叠成一片黄，喧宾夺主。
            // 取无偏移而不是 y:3：下偏的影会和底部 wash 反光带撞在一起，根部发浑。
            // 成本上酷黑主题早就是 blur + shadow 双通道每根柱，这里持平。
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 0)
            // 🍃 灰白主题的渐隐量就是**整根柱子的不透明度**。
            // 黑主题那边 opacity 只吃在一层 fill 上（柱子本来就是单色）；这根是「柔光 + 渐变肚子 +
            // 描边」三层叠出来的，挨个改 alpha 既要重算三层权重、又会让肚子和针尖淡得不一样快。
            // 直接给合成结果乘一个 opacity，等价于「整根柱子往页面底色里化开」——
            // 与黑主题往黑底里化开是同一种物理，曲线、力度、左右对齐两边完全一致。
            // ⚠️ 必须压在 .shadow 之后：放前面的话外层那道中性投影不跟着淡，
            // 外侧几根就剩一圈灰影（黑主题的 glow 同理，见上面 shadow 里的 0.8 * fadeAmt）。
            .opacity(fadeAmt)
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
