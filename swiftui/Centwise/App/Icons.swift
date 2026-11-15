import SwiftUI

/// Interface icons as Apple's SF Symbols (so the app reads as iOS); names stay the Lucide names used
/// across the code, and anything not listed here is drawn from the bundled Lucide geometry.
let sfIcons: [String: String] = [
    "folder-search": "magnifyingglass",
    "plus": "plus",
    "chevron-left": "chevron.left",
    "chevron-right": "chevron.right",
    "chevron-down": "chevron.down",
    "chevron-up-down": "chevron.up.chevron.down",
    "x": "xmark",
    "check": "checkmark",
    "circle-x": "xmark.circle.fill",
    "circle-alert": "exclamationmark.circle",
    "info": "info",
    "trash": "trash",
    "pencil": "pencil",
    "calendar": "calendar",
    "text-align-start": "text.alignleft",
    "list-filter": "line.3.horizontal.decrease",
    "lock": "lock",
    "delete": "delete.left",
    "undo-2": "arrow.uturn.left",
    "refresh-cw": "arrow.2.circlepath",
    "arrow-left-right": "arrow.left.arrow.right",
    "arrow-up-right": "arrow.up.right",
    "arrow-down-left": "arrow.down.left",
    "equal": "equal",
    "split": "arrow.branch",
    "chart-pie": "chart.pie",
    "piggy-bank": "chart.pie",
    "receipt": "doc.text",
    "book-open": "book",
    "layout-grid": "square.grid.2x2",
    "upload": "square.and.arrow.up",
    "download": "square.and.arrow.down",
    "file-down": "square.and.arrow.down",
    "cloud": "cloud",
    "cloud-check": "cloud",
    "log-out": "rectangle.portrait.and.arrow.right",
    "circle-user-round": "person.crop.circle",
    "user": "person",
    "users": "person.2",
    "sun-moon": "circle.lefthalf.filled",
    "languages": "globe",
    "shield-check": "checkmark.shield",
    "credit-card": "creditcard",
    "wallet": "creditcard",
    "wallet-cards": "creditcard",
    "banknote": "yensign.circle",
    "tag": "tag",
    "archive": "archivebox",
    "ellipsis": "ellipsis",
    "store": "bag",
]

/// An interface icon: the SF Symbol from `sfIcons` when there is one, otherwise the Lucide line icon.
struct LIcon: View {
    let name: String
    var size: CGFloat = 18
    var color: Color = .cwInk
    var strokeWidth: CGFloat = 2

    init(_ name: String, size: CGFloat = 18, color: Color = .cwInk, strokeWidth: CGFloat = 2) {
        self.name = name; self.size = size; self.color = color; self.strokeWidth = strokeWidth
    }

    var body: some View {
        Group {
            if let symbol = sfIcons[name] {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.92, weight: strokeWidth >= 2.5 ? .semibold : .regular))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
            } else {
                SVGGlyphView(glyph: SVGGlyph.parse(lucideSVG[name] ?? lucideSVG["circle-question-mark"] ?? ""), color: color, strokeWidth: strokeWidth)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lucide geometry always (never the SF stand-in), e.g. for the header magnifier and cog.
struct LucideIcon: View {
    let name: String
    var size: CGFloat = 18
    var color: Color = .cwInk
    var strokeWidth: CGFloat = 2

    var body: some View {
        SVGGlyphView(glyph: SVGGlyph.parse(lucideSVG[name] ?? ""), color: color, strokeWidth: strokeWidth)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Font {
    /// The system font for emoji at `size`.
    ///
    /// Some simulator runtimes (iOS 26.3 here) look for the emoji font at a path the runtime does not
    /// ship, so every emoji draws as a boxed "?". In the simulator only, name the emoji font that the
    /// runtime does ship; devices keep the plain system font.
    static func emoji(size: CGFloat) -> Font {
        #if targetEnvironment(simulator)
        if let descriptor = SimulatorEmojiFont.descriptor { return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil)) }
        #endif
        return .system(size: size)
    }
}

#if targetEnvironment(simulator)
private enum SimulatorEmojiFont {
    /// The emoji font read straight from a file: the runtime's own copy, else the Mac's.
    static let descriptor: CTFontDescriptor? = {
        let root = ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? ""
        for path in [root + "/System/Library/Fonts/CoreAddition/AppleColorEmoji-160px.ttc", "/System/Library/Fonts/Apple Color Emoji.ttc"] {
            let url = URL(fileURLWithPath: path) as CFURL
            if let all = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor], let first = all.first { return first }
        }
        return nil
    }()
}
#endif

/// A category emoji drawn with Apple's own emoji, centred in a square box.
struct EmojiIcon: View {
    let name: String
    var size: CGFloat = 18

    init(_ name: String, size: CGFloat = 18) { self.name = name; self.size = size }

    var body: some View {
        Text(emojiFor(name))
            .font(.emoji(size: size * 0.98))
            .lineLimit(1)
            .fixedSize()
            .frame(width: size * 1.15, height: size * 1.15)
            .accessibilityHidden(true)
    }
}

/// A category's icon at `size`: its emoji.
struct CategoryIcon: View {
    let category: LedgerCategory
    var size: CGFloat = 18

    init(_ category: LedgerCategory, size: CGFloat = 18) { self.category = category; self.size = size }

    var body: some View { EmojiIcon(categoryIcon(category), size: size) }
}

/// Round flag for a currency (Assets.xcassets/Flags).
struct FlagIcon: View {
    let code: String
    var size: CGFloat = 20
    var body: some View {
        Image("Flags/\(code)").resizable().scaledToFit().frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

/// Apple emoji for each Lucide category icon (only emoji that draw in colour by default).
let categoryEmoji: [(String, String)] = [
    ("utensils", "🍽️"), ("coffee", "☕"), ("apple", "🍎"), ("beer", "🍺"), ("cake", "🎂"), ("pizza", "🍕"), ("hamburger", "🍔"),
    ("train-front", "🚇"), ("bus", "🚌"), ("car", "🚗"), ("bike", "🚲"), ("fuel", "⛽"), ("square-parking", "🚙"), ("plane", "🛫"),
    ("hotel", "🏨"), ("map-pin", "📍"), ("ticket", "🎟️"),
    ("shopping-bag", "🛍️"), ("shopping-basket", "🧺"), ("shirt", "👕"), ("footprints", "👟"), ("gem", "💎"), ("package", "📦"), ("store", "🏪"),
    ("house", "🏠"), ("sofa", "🛋️"), ("bath", "🛁"), ("wrench", "🔧"), ("trash", "🗑️"), ("lightbulb", "💡"),
    ("zap", "⚡"), ("droplet", "💧"), ("flame", "🔥"), ("wifi", "📶"), ("phone", "📞"), ("smartphone", "📱"), ("laptop", "💻"), ("tv", "📺"), ("app-window", "📲"),
    ("pill", "💊"), ("stethoscope", "🩺"), ("heart", "💗"), ("dumbbell", "🏋️"), ("scissors", "💈"), ("sparkles", "✨"),
    ("gamepad-2", "🎮"), ("film", "🎬"), ("music", "🎵"), ("mic", "🎙️"), ("palette", "🎨"), ("book-open", "📚"), ("graduation-cap", "🎓"),
    ("baby", "🍼"), ("dog", "🐶"), ("fish", "🐟"), ("users", "👥"), ("user", "🙂"), ("gift", "🎁"),
    ("receipt", "🧾"), ("shield-check", "🛡️"), ("landmark", "🏛️"), ("wallet", "👛"), ("wallet-cards", "💳"), ("credit-card", "💳"),
    ("briefcase", "💼"), ("trending-up", "📈"), ("hand-coins", "💰"), ("banknote", "💵"), ("piggy-bank", "🐷"),
    ("ellipsis", "📌"), ("layout-grid", "🗂️"), ("folder-search", "🗂️"), ("tag", "🏷️"),
]
let categoryEmojiMap: [String: String] = Dictionary(categoryEmoji, uniquingKeysWith: { a, _ in a })

/// True when a category symbol is an emoji itself rather than a Lucide / SF Symbol name.
func isEmojiSymbol(_ symbol: String) -> Bool { (symbol.unicodeScalars.first?.value ?? 0) > 0x7F }

func emojiFor(_ icon: String) -> String { categoryEmojiMap[icon] ?? (isEmojiSymbol(icon) ? icon : "🏷️") }

/// The icon key to store for an emoji: the Lucide key when it is a curated one, otherwise the emoji.
func iconKeyForEmoji(_ emoji: String) -> String { categoryEmoji.first { $0.1 == emoji }?.0 ?? emoji }

/// Icons offered when creating a category: one per distinct emoji.
let categoryIconChoices: [String] = {
    var seen = Set<String>()
    return categoryEmoji.filter { seen.insert($0.1).inserted }.map(\.0)
}()

private let sfCategorySymbols: [String: String] = [
    "fork.knife": "utensils", "tram.fill": "train-front", "bag.fill": "shopping-bag", "house.fill": "house", "sparkles": "sparkles",
    "ellipsis.circle": "ellipsis", "briefcase.fill": "briefcase", "gift.fill": "gift", "heart.fill": "heart", "book.fill": "book-open",
    "square.grid.2x2": "layout-grid", "questionmark.folder": "folder-search",
]

private let nameRules: [([String], String)] = [
    (["科技", "数码", "电子", "电脑"], "laptop"), (["社交", "朋友", "聚会"], "users"), (["杂货", "生活用品", "日用品"], "shopping-basket"),
    (["杂项"], "package"), (["店铺", "商业"], "store"), (["个护", "护发", "護髮", "美发", "理发"], "scissors"), (["个人"], "user"),
    (["鱼", "海鲜"], "fish"), (["鞋"], "footprints"), (["衛浴", "卫浴"], "bath"), (["傢俱", "家具", "家俱"], "sofa"),
    (["天然气", "燃气"], "flame"), (["上网", "宽带", "网费"], "wifi"), (["电话"], "phone"), (["有线电视", "电视"], "tv"),
    (["供水", "水费"], "droplet"), (["停车"], "square-parking"), (["维护", "维修", "保养"], "wrench"), (["書", "书籍"], "book-open"),
    (["音乐"], "music"), (["podcast", "播客"], "mic"), (["应用程序", "itunes"], "app-window"), (["税"], "landmark"),
    (["安全", "保安"], "shield-check"), (["垃圾"], "trash"), (["運動"], "dumbbell"), (["車"], "car"),
    (["住宅", "租金", "租房", "押金"], "house"), (["日常开支"], "wallet"), (["打工", "私单", "兼职"], "briefcase"), (["赠金", "赠"], "gift"),
    (["股息"], "trending-up"), (["咖啡", "奶茶", "饮料"], "coffee"), (["餐", "饭", "食", "外卖", "零食", "早点"], "utensils"),
    (["水果"], "apple"), (["酒"], "beer"), (["地铁", "公交", "交通"], "train-front"), (["打车", "车", "停车"], "car"),
    (["油", "加油"], "fuel"), (["机票", "旅", "出行"], "plane"), (["酒店", "住宿"], "hotel"), (["购物", "日用", "超市", "网购"], "shopping-bag"),
    (["衣", "服饰", "服装"], "shirt"), (["房租", "房贷", "居家", "住房", "物业", "家"], "house"), (["水电", "燃气", "电费"], "zap"),
    (["话费", "手机", "通讯", "网费"], "smartphone"), (["医", "药", "健康"], "pill"), (["运动", "健身"], "dumbbell"),
    (["娱乐", "休闲", "游戏"], "gamepad-2"), (["电影", "演出"], "film"), (["教育", "学习", "书", "培训"], "graduation-cap"),
    (["孩子", "宝宝", "育儿"], "baby"), (["宠物", "猫", "狗"], "dog"), (["礼", "红包", "人情"], "gift"), (["美容", "理发", "美发"], "scissors"),
    (["订阅", "会员", "软件"], "receipt"), (["保险"], "shield-check"), (["工资", "薪"], "briefcase"), (["奖金", "分红"], "gift"),
    (["理财", "利息", "投资", "收益"], "trending-up"), (["报销", "退款"], "hand-coins"), (["其他", "其它"], "ellipsis"),
    (["coffee", "tea", "drink"], "coffee"), (["food", "meal", "restaurant", "dining", "lunch", "dinner", "breakfast", "snack", "takeout"], "utensils"),
    (["fruit"], "apple"), (["beer", "wine", "bar"], "beer"), (["metro", "subway", "bus", "transit", "transport"], "train-front"),
    (["taxi", "uber", "car", "parking"], "car"), (["fuel", "gas"], "fuel"), (["flight", "travel", "trip"], "plane"),
    (["hotel", "lodging"], "hotel"), (["shopping", "grocer", "supermarket"], "shopping-bag"), (["cloth", "apparel", "shoe"], "shirt"),
    (["rent", "mortgage", "home", "house"], "house"), (["utilit", "electric", "water"], "zap"), (["phone", "mobile", "internet"], "smartphone"),
    (["medic", "health", "doctor", "pharma"], "pill"), (["gym", "fitness", "sport"], "dumbbell"), (["fun", "leisure", "game", "entertain"], "gamepad-2"),
    (["movie", "cinema", "concert"], "film"), (["educat", "school", "book", "course"], "graduation-cap"), (["kid", "child", "baby"], "baby"),
    (["pet"], "dog"), (["gift", "bonus"], "gift"), (["beauty", "hair"], "scissors"), (["subscri", "membership", "software"], "receipt"),
    (["insur"], "shield-check"), (["salary", "wage", "payroll"], "briefcase"), (["invest", "interest", "dividend"], "trending-up"),
    (["refund", "reimburs"], "hand-coins"), (["other"], "ellipsis"),
]

/// Icon key for a category: its own emoji / Lucide name, an old SF Symbol name mapped, or a keyword
/// match on the name.
func categoryIcon(_ category: LedgerCategory) -> String {
    let symbol = category.symbol
    if isEmojiSymbol(symbol) { return symbol }
    if lucideSVG[symbol] != nil && symbol != "layout-grid" { return symbol }
    if let mapped = sfCategorySymbols[symbol], mapped != "layout-grid" { return mapped }
    let lower = category.name.lowercased()
    for (words, icon) in nameRules where words.contains(where: { lower.contains($0) }) { return icon }
    return category.kind == .income ? "banknote" : "layout-grid"
}
