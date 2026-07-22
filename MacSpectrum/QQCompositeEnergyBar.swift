//
//  QQCompositeEnergyBar.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/7/21.
//原

import SwiftUI

// MARK: - 1. 彻底消灭牙签的针尖 Shape
//struct QQNeedleShape: Shape {
//    var intensity: CGFloat
//    
//    
//    var animatableData: CGFloat {
//        get { intensity }
//        set { intensity = newValue }
//    }
//    
//    func path(in rect: CGRect) -> Path {
//        var path = Path()
//        let w = rect.width
//        let h = rect.height
//        
//        if h <= 0.5 { return path }
//        
//        let centerX = w / 2.0
//        let topTip = CGPoint(x: centerX, y: 0)
//        
//        // 底部完全继承外层传进来的宽度 w
//        path.move(to: CGPoint(x: 0, y: h))
//        
//        // 腰身保留足够的体量感，顶部 30% 再内凹收紧
//        let shoulderY = h * 0.35
//        let shoulderWidth = w * 0.40
//        let leftShoulder = CGPoint(x: centerX - shoulderWidth / 2, y: shoulderY)
//        
//        // 左下 -> 左肩膀
//        path.addQuadCurve(to: leftShoulder, control: CGPoint(x: w * 0.15, y: h * 0.65))
//        
//        // 左肩膀 -> 针尖 topTip (内凹切削)
//        let leftTipControlX = centerX - (shoulderWidth / 2) * 0.25
//        path.addQuadCurve(to: topTip, control: CGPoint(x: leftTipControlX, y: shoulderY * 0.4))
//        
//        // 镜像右侧
//        let rightShoulder = CGPoint(x: centerX + shoulderWidth / 2, y: shoulderY)
//        let rightTipControlX = centerX + (shoulderWidth / 2) * 0.25
//        path.addQuadCurve(to: rightShoulder, control: CGPoint(x: rightTipControlX, y: shoulderY * 0.4))
//        
//        // 右肩膀 -> 右下
//        path.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w * 0.85, y: h * 0.65))
//        
//        path.closeSubpath()
//        return path
//    }
//}

// MARK: - 2. ZStack 绝对定位重叠组件
struct QQCompositeEnergyBar: View {
    var height: CGFloat          // 外部算好的总高度
    var intensity: CGFloat       // 能量 (0.0 ~ 1.0)
    var barWidth: CGFloat        // 单元格宽度 (如 9)
    var baseColor: Color         // 主色
    
    var maxH: CGFloat
    var minH: CGFloat
    
    var body: some View {
        // 📐 尺寸精细定义
        let baseRectHeight: CGFloat = 2.0  // 底部矩形垫片
        // 🚀 把椭圆高度增加到 8 像素，确保它的圆弧能完整露出来！
        //        let ellipseHeight: CGFloat  = max(4.0, min(10.0, height * 0.15))
        let needleHeight: CGFloat   = 10.0               // 针尖固定高度（足够长，才显得细锐）
        // 膨胀腰腹宽度
        let bellyWidth = barWidth * (0.85 + intensity * 1.5)
        //        let baseWidth  = barWidth * 0.85
        
        let ellipseCalculatedHeight = max(4.0, height - baseRectHeight - needleHeight + 4.0)
        
        let progress = max(0.0, min(1.0, (ellipseCalculatedHeight - minH) / (maxH - minH)))
        let dynamicNeedleWidth = 1.5 + progress * 1.5
        
        // 🚀 【ZStack 层叠绘制】：自下而上层叠，摆脱 VStack 挤压
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 50)
                .frame(width: dynamicNeedleWidth, height: (baseRectHeight + ellipseCalculatedHeight) * 1.2)
//                .padding(.bottom, baseRectHeight + ellipseCalculatedHeight - 2.0)
                .foregroundColor(baseColor)
//                .blur(radius: 1.0)
            // Layer 1: 顶天立地的内凹针尖（高度覆盖整体，底部直接插到底座上）
            //            QQNeedleShape(intensity: intensity)
            //                .frame(width: dynamicNeedleWidth, height: baseRectHeight + ellipseCalculatedHeight + 7.0)
            //                .padding(.bottom, baseRectHeight)
            // Layer 2: 原生饱满椭圆（压在针尖和底座之间，做完美的腰腹圆弧）
            Ellipse()
                .stroke(baseColor, lineWidth: 3.5)
                .frame(width: bellyWidth * 0.8, height: ellipseCalculatedHeight)
                .padding(.top, baseRectHeight / 2.0) // 严丝合缝压住针尖基部
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
//                .blur(radius: 1.0)
            // Layer 3: 最底部的矩形微型底座
            Rectangle()
                .frame(width: dynamicNeedleWidth * 1.5, height: baseRectHeight)
                .foregroundColor(baseColor)
        }
//        .blur(radius: 1.0, opaque: false)
        .frame(width: barWidth, height: height, alignment: .bottom)
        .animation(.linear(duration: 0.07), value: intensity)
    }
}
