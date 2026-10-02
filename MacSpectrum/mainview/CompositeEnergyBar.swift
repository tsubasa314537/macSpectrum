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
        
        // ── 🎨 灰白主题：多层几何拟态 Blur 光晕 ─────────────────────────────
        
        // 1. 底层：超宽、极淡的“假 Blur 扩散层”（负责营造朦胧波浪感）
        let outerLineWidth = 2.0 + intensity * 8.0     // 爆破到 10.0px，极宽！
        let outerOpacity   = 0.05 + intensity * 0.25    // 极其微弱柔和的背景弥散
        
        // 2. 顶层：精致、高亮的“实体核心线”（负责保留打击感）
        let coreLineWidth  = 1.0 + intensity * 2.5     // 保持精致
        let coreOpacity    = 0.30 + intensity * 0.65    // 核心高亮
        
        // 🚀 【ZStack 层叠绘制】：自下而上层叠，摆脱 VStack 挤压
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 50)
                .frame(width: dynamicNeedleWidth, height: ellipseCalculatedHeight * 0.28)// * 0.25)
                .padding(.bottom, baseRectHeight + ellipseCalculatedHeight * 0.90 - 2.0)
            
            ZStack {
                // 🌟 第一层（外晕）：宽而透的“假 Blur”扩散圈
                // 它在极宽的线宽下，配合极低的透明度，视觉上会形成完美的渐隐烟雾感！
                Ellipse()
                    .stroke(
                        baseColor.opacity(outerOpacity),
                        lineWidth: outerLineWidth
                    )
                    .frame(width: bellyWidth * 0.85, height: ellipseCalculatedHeight * 0.90 + 2)
                
                // 🌟 第二层（内芯）：精致醒目的高能量核心
                Ellipse()
                    .stroke(
                        baseColor.opacity(coreOpacity),
                        lineWidth: coreLineWidth
                    )
                    .frame(width: bellyWidth * 0.8, height: ellipseCalculatedHeight * 0.90)
            }
            .padding(.top, baseRectHeight / 2.0)
//            .shadow(color: baseColor.opacity(0.8), radius: 4, x: 0, y: 0)
            
            
            // Layer 3: 最底部的矩形微型底座
            Rectangle()
                .frame(width: dynamicNeedleWidth * 1.5, height: baseRectHeight)
//                .foregroundColor(baseColor)
        }
        .fillGradient(barGradient)
        .frame(width: barWidth, height: height, alignment: .bottom)
        .animation(.linear(duration: 0.08), value: intensity)
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
