import SwiftUI

struct AuthorAvatar: View {
    let name: String
    let email: String
    var size: CGFloat = 24

    private var initials: String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "?" }
        let words = cleaned.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private var color: Color {
        let hash = email.lowercased().unicodeScalars.reduce(0) { (result: UInt64, scalar: Unicode.Scalar) -> UInt64 in
            result &* 31 &+ UInt64(scalar.value)
        }
        return Self.palette[Int(hash % UInt64(Self.palette.count))]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
    }

    /// 12 saturated hues that read clearly at small sizes.
    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.55, blue: 0.92),
        Color(red: 0.95, green: 0.45, blue: 0.30),
        Color(red: 0.30, green: 0.70, blue: 0.45),
        Color(red: 0.85, green: 0.40, blue: 0.80),
        Color(red: 0.95, green: 0.70, blue: 0.20),
        Color(red: 0.50, green: 0.45, blue: 0.92),
        Color(red: 0.20, green: 0.72, blue: 0.72),
        Color(red: 0.92, green: 0.35, blue: 0.55),
        Color(red: 0.50, green: 0.72, blue: 0.30),
        Color(red: 0.72, green: 0.50, blue: 0.30),
        Color(red: 0.35, green: 0.50, blue: 0.85),
        Color(red: 0.78, green: 0.55, blue: 0.85),
    ]
}

#Preview {
    HStack(spacing: 8) {
        AuthorAvatar(name: "Alvaro Guerra Freitas", email: "alvaro@warwarelabs.com")
        AuthorAvatar(name: "Anne Frank", email: "anne@example.com")
        AuthorAvatar(name: "Carlos", email: "carlos@example.com")
        AuthorAvatar(name: "  ", email: "anon@example.com")
        AuthorAvatar(name: "Alvaro Guerra Freitas", email: "alvaro@warwarelabs.com", size: 36)
    }
    .padding()
}
