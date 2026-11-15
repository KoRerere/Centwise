import SwiftUI

/// The category icon picker: every Apple emoji in the system picker's order, a search field, and
/// section tabs at the bottom (like the emoji keyboard).
struct EmojiPicker: View {
    let selected: String
    let common: [String]
    let onSelected: (String) -> Void
    var height: CGFloat = 420

    @State private var query = ""
    @State private var activeTab = 0
    @State private var jump: Int?

    private static let tabIcons: [String: String] = [
        "common": "star", "smiley": "face.smiling", "paw": "pawprint", "food": "cart", "activity": "sportscourt",
        "travel": "car", "objects": "lightbulb", "symbols": "number", "flags": "flag",
    ]

    private var sections: [(String, String, [String])] {
        [(tr("常用"), "common", common)] + emojiGroups.map { (tr($0.title), $0.icon, $0.emojis.map(\.0)) }
    }

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let words = q.split(whereSeparator: \.isWhitespace).map(String.init)
        return emojiGroups.flatMap(\.emojis).filter { e in words.allSatisfy { e.1.contains($0) } }.map(\.0)
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 8)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Color.cwMuted)
                TextField("", text: $query, prompt: Text(tr("搜索表情")).foregroundStyle(Color.cwMuted)).font(.cw(IOSText.body))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cwMuted) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Capsule().fill(Color.cwTrack))
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)

            if !query.isEmpty {
                let found = matches
                if found.isEmpty {
                    Text(tr("没有找到表情")).cw(IOSText.subheadline, color: .cwMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 0) { ForEach(found, id: \.self) { cell($0) } }.padding(.horizontal, 10).padding(.vertical, 8)
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                                Text(s.0).cw(IOSText.footnote, .semibold, color: .cwMuted)
                                    .padding(.leading, 6).padding(.bottom, 6).frame(height: 34, alignment: .bottomLeading)
                                    .id(i)
                                    .onAppear { if jump == nil { activeTab = max(0, i - 1) } }
                                LazyVGrid(columns: columns, spacing: 0) { ForEach(Array(s.2.enumerated()), id: \.offset) { _, e in cell(e) } }
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { visible in
                        if let first = visible.min(), jump == nil { activeTab = first }
                    }
                    .onChange(of: jump) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.38)) { proxy.scrollTo(target, anchor: .top) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { jump = nil }
                    }
                }
            }
            Rectangle().fill(Color.cwStroke).frame(height: hairline)
            HStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                    let on = i == activeTab && query.isEmpty
                    Button {
                        Haptics.selection()
                        query = ""
                        activeTab = i
                        jump = i
                    } label: {
                        Image(systemName: Self.tabIcons[s.1] ?? "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(on ? Color.cwInk : .cwMuted)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(on ? Color.cwTrack : .clear))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 46)
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.cwCard))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func cell(_ emoji: String) -> some View {
        let on = emoji == selected
        return Button {
            Haptics.selection()
            onSelected(emoji)
        } label: {
            Text(emoji).font(.system(size: 26)).frame(width: 40, height: 40)
                .background(Circle().fill(on ? Color.cwTrack : .clear))
                .frame(maxWidth: .infinity).frame(height: 42)
                .animation(.easeOut(duration: 0.16), value: on)
        }
        .buttonStyle(.plain)
    }
}
