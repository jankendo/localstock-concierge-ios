import SwiftUI

enum StockTheme {
    static let coral = Color(red: 0.98, green: 0.32, blue: 0.27)
    static let mint = Color(red: 0.00, green: 0.72, blue: 0.63)
    static let sky = Color(red: 0.12, green: 0.53, blue: 0.95)
    static let lemon = Color(red: 1.00, green: 0.76, blue: 0.20)
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.18)
    static let softBackground = Color(red: 0.98, green: 0.97, blue: 0.93)
}

struct StatusPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.2), lineWidth: 1)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: Circle())
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(StockTheme.ink)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
    }
}
