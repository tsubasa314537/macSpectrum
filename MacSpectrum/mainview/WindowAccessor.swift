//
//  WindowAccessor.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/14.
//

import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            if let window = view.window {
                
                // 1️⃣ 无边框
                window.styleMask = [.borderless]
                
                // 2️⃣ 透明背景
                window.isOpaque = false
                window.backgroundColor = .clear
                
                // 3️⃣ 不显示阴影（可选）
                window.hasShadow = false
                
                // 4️⃣ 可拖拽
                window.isMovableByWindowBackground = true
                
                // 5️⃣ 始终置顶（可选）
                 window.level = .floating
                
                // 6️⃣ 禁止成为主窗口（像桌面挂件）
                // window.level = .desktopIcon
                
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
