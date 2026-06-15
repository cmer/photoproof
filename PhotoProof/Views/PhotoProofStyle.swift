// PhotoProofStyle.swift
// Shared colors, surfaces, and compact UI elements for PhotoProof's visual system.

import SwiftUI

enum PhotoProofStyle {
    static let accent = Color(red: 0.29, green: 0.45, blue: 0.98)
    static let cyan = Color(red: 0.16, green: 0.72, blue: 0.88)
    static let mint = Color(red: 0.20, green: 0.78, blue: 0.59)
    static let amber = Color(red: 0.98, green: 0.64, blue: 0.20)

    static let heroGradient = LinearGradient(
        colors: [accent, Color(red: 0.42, green: 0.31, blue: 0.94), cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PhotoProofBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Circle()
                .fill(PhotoProofStyle.accent.opacity(0.12))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: -330, y: -260)

            Circle()
                .fill(PhotoProofStyle.cyan.opacity(0.10))
                .frame(width: 460, height: 460)
                .blur(radius: 100)
                .offset(x: 380, y: 300)
        }
        .ignoresSafeArea()
    }
}

struct ProofIcon: View {
    let systemName: String
    var color: Color = PhotoProofStyle.accent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3))
    }
}

struct ProofPill: View {
    let title: String
    let systemName: String
    var color: Color = PhotoProofStyle.accent

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.11), in: Capsule())
    }
}

private struct ProofSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

extension View {
    func proofSurface(padding: CGFloat = 20, cornerRadius: CGFloat = 18) -> some View {
        modifier(ProofSurfaceModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
