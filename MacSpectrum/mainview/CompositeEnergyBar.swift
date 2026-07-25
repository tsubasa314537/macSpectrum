//
//  QQCompositeEnergyBar.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/7/21.
//

import SwiftUI

// 👴 老爷子专属：两腰内凹的优雅双曲三角形 Shape
struct ConcaveTriangleShape: Shape {
    /// 凹陷程度控制系数 (0.0 ~ 1.0)
    /// 0.25~0.35 为非常性感优雅的收腰弧线；值越大腰越细！
    var concavity: CGFloat = 0.30
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let topCenter = CGPoint(x: rect.midX, y: rect.minY)       // 顶部尖端
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)     // 左下角（落于椭圆切线）
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)    // 右下角（落于椭圆切线）
        
        // 1. 起点：顶部尖端
        path.move(to: topCenter)
        
        // 2. 左腰内凹贝塞尔曲线（控制点向内部收拢）
        let leftControlPoint = CGPoint(
            x: rect.minX + (rect.width * concavity),
            y: rect.midY
        )
        path.addQuadCurve(to: bottomLeft, control: leftControlPoint)
        
        // 3. 底部横线（与下面的椭圆平滑接轨）
        path.addLine(to: bottomRight)
        
        // 4. 右腰内凹贝塞尔曲线
        let rightControlPoint = CGPoint(
            x: rect.maxX - (rect.width * concavity),
            y: rect.midY
        )
        path.addQuadCurve(to: topCenter, control: rightControlPoint)
        
        path.closeSubpath()
        return path
    }
}

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
        let needleHeight: CGFloat   = 10.0               // 针尖固定高度
        
        // 膨胀腰腹宽度
        let bellyWidth = barWidth * (0.85 + intensity * 1.5)
        
        let ellipseCalculatedHeight = max(4.0, height - baseRectHeight - needleHeight + 4.0) * 0.9
        
        // 🎯 动态计算内凹三角形顶端的高度（跟随能量感向上延伸，越爆破拉得越长！）
        let triangleDynamicHeight = max(8.0, ellipseCalculatedHeight * 0.75) * 0.9
        
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
        
        // 🚀 【ZStack 层叠绘制】：自下而上层叠
        ZStack(alignment: .bottom) {
            
            // 🌟 Layer 1: 最顶部的【内凹收腰三角形】
            // 宽度完全对接内芯椭圆 (bellyWidth * 0.8)，底部精准卡在椭圆的上半部位
            ConcaveTriangleShape(concavity: 0.32)
                .frame(width: bellyWidth * 0.8, height: triangleDynamicHeight)
                .padding(.bottom, baseRectHeight + ellipseCalculatedHeight - (triangleDynamicHeight * 0.3))
            
            // 🌟 中间的椭圆光晕层
            ZStack {
                // 0. 🎯【新增】实心遮罩椭圆：专门用来把穿透进来的针尖遮住！
                // 不加 stroke，只用纯填充，颜色用底色或纯色，把它当遮罩
                Ellipse()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85)) // 或者是灰白主题的背景色/配合渐变
                    .frame(width: bellyWidth * 0.7, height: ellipseCalculatedHeight)
                
                // 1. 外晕：宽而透的“假 Blur”扩散圈
                Ellipse()
                    .stroke(
                        baseColor.opacity(outerOpacity),
                        lineWidth: outerLineWidth
                    )
                    .frame(width: bellyWidth * 0.85, height: ellipseCalculatedHeight + 2)
                
                // 2. 内芯：精致醒目的高能量核心
                Ellipse()
                    .stroke(
                        baseColor.opacity(coreOpacity),
                        lineWidth: coreLineWidth
                    )
                    .frame(width: bellyWidth * 0.8, height: ellipseCalculatedHeight)
            }
            .padding(.top, baseRectHeight / 2.0)
            
            // 🌟 Layer 3: 最底部的矩形微型底座
            Rectangle()
                .frame(width: bellyWidth * 0.5, height: baseRectHeight)
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
