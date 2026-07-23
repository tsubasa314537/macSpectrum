//
//  QQCompositeEnergyBar.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/7/21.
//原

import SwiftUI

struct CompositeEnergyBar: View {
    var height: CGFloat          // 外部算好的总高度
    var intensity: CGFloat       // 能量 (0.0 ~ 1.0)
    var barWidth: CGFloat        // 单元格宽度 (如 9)
    var baseColor: Color         // 主色
    
    var maxH: CGFloat
    var minH: CGFloat
    
    var body: some View {
        // 📐 尺寸精细定义
        let baseRectHeight: CGFloat = 2.0  // 底部矩形垫
        // 🚀 把椭圆高度增加到 8 像素，确保它的圆弧能完整露出来！
        //        let ellipseHeight: CGFloat  = max(4.0, min(10.0, height * 0.15))
        let needleHeight: CGFloat   = 10.0               // 针尖固定高度（足够长，才显得细锐）
        // 膨胀腰腹宽度
        let bellyWidth = barWidth * (0.85 + intensity * 1.5)
        //        let baseWidth  = barWidth * 0.85
        
        let ellipseCalculatedHeight = max(4.0, height - baseRectHeight - needleHeight + 4.0)
        
        let progress = max(0.0, min(1.0, (ellipseCalculatedHeight - minH) / (maxH - minH)))
        let dynamicNeedleWidth = 1.5 + progress * 1.5
        
        // 1. 动态计算线条粗细与透明度（随能量 intensity 呼吸跳动）
        // 能量低时线条细致精悍（2.0），能量高时线宽膨胀扩散（4.5），形成发光炸开的视觉假象！
        let dynamicLineWidth = 2.0 + intensity * 2.5
        
        // 2. 动态计算光晕透明度：能量越高，发光感越强！
        let dynamicOpacity = 0.45 + intensity * 0.55
        
        // 3. 构建能量响应的极轻量渐变
        let dynamicStrokeGradient = LinearGradient(
            colors: [
//                baseColor.opacity(dynamicOpacity),
//                baseColor.opacity(dynamicOpacity * 0.35),
                baseColor.opacity(dynamicOpacity)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        
        let barGradient = LinearGradient(
            colors: [
                baseColor.opacity(0.3),
                baseColor.opacity(0.8 + Double(intensity * 0.2)),
                baseColor.opacity(0.95),
                baseColor.opacity(0.2)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        
        // 🚀 【ZStack 层叠绘制】：自下而上层叠，摆脱 VStack 挤压
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 50)
                .frame(width: dynamicNeedleWidth, height: ellipseCalculatedHeight * 0.25/*(baseRectHeight + ellipseCalculatedHeight) * 1.2*/)
                .padding(.bottom, baseRectHeight + ellipseCalculatedHeight - 2.0)
//                .foregroundColor(baseColor)
//                .blur(radius: 1.0, opaque: false)
            // Layer 1: 顶天立地的内凹针尖（高度覆盖整体，底部直接插到底座上）
            //            QQNeedleShape(intensity: intensity)
            //                .frame(width: dynamicNeedleWidth, height: baseRectHeight + ellipseCalculatedHeight + 7.0)
            //                .padding(.bottom, baseRectHeight)
            // Layer 2: 原生饱满椭圆（压在针尖和底座之间，做完美的腰腹圆弧）
            Ellipse()
                .stroke(dynamicStrokeGradient, lineWidth: dynamicLineWidth)
                .frame(width: bellyWidth * 0.8, height: ellipseCalculatedHeight)
                .padding(.top, baseRectHeight / 2.0) // 严丝合缝压住针尖基部
//                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
//                .blur(radius: blurRatio * 0.3, opaque: false)
            // Layer 3: 最底部的矩形微型底座
            Rectangle()
                .frame(width: dynamicNeedleWidth * 1.5, height: baseRectHeight)
//                .foregroundColor(baseColor)
        }
        .fillGradient(barGradient)
        .frame(width: barWidth, height: height, alignment: .bottom)
        .animation(.linear(duration: 0.07), value: intensity)
    }
}

// MARK: - 3. 辅助拓展：给复合组件统一刷上 LinearGradient
extension View {
    @ViewBuilder
    func fillGradient(_ gradient: LinearGradient) -> some View {
        if #available(macOS 12.0, iOS 15.0, *) {
            self.foregroundStyle(gradient)
        } else {
            self.overlay(gradient).mask(self)
        }
    }
}
