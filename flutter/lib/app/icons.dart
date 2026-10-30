import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/models.dart';
import 'lucide_icons.dart';

/// Interface icons drawn as Apple's SF Symbols-style glyphs (the cupertino_icons font) so the app reads
/// as iOS. Names stay the Lucide names used across the code; anything not listed here still falls back
/// to the bundled Lucide SVG. Category pictures are separate (3D emoji, see [CategoryIcon]).
const Map<String, IconData> sfIcons = {
  // 'search' deliberately falls back to the Lucide line icon: the SF glyph is much heavier than
  // the other Lucide strokes around the app (header buttons, search fields).
  'folder-search': CupertinoIcons.search,
  'plus': CupertinoIcons.add,
  'chevron-left': CupertinoIcons.chevron_left,
  'chevron-right': CupertinoIcons.chevron_right,
  'chevron-down': CupertinoIcons.chevron_down,
  'chevron-up-down': CupertinoIcons.chevron_up_chevron_down,
  'x': CupertinoIcons.xmark,
  'check': CupertinoIcons.checkmark_alt,
  'circle-x': CupertinoIcons.xmark_circle_fill,
  'circle-alert': CupertinoIcons.exclamationmark_circle,
  'info': CupertinoIcons.info,
  'trash': CupertinoIcons.trash,
  'pencil': CupertinoIcons.pencil,
  'calendar': CupertinoIcons.calendar,
  'text-align-start': CupertinoIcons.text_alignleft,
  'list-filter': CupertinoIcons.line_horizontal_3_decrease,
  'lock': CupertinoIcons.lock,
  'delete': CupertinoIcons.delete_left,
  'undo-2': CupertinoIcons.arrow_uturn_left,
  'refresh-cw': CupertinoIcons.arrow_2_circlepath,
  'arrow-left-right': CupertinoIcons.arrow_right_arrow_left,
  'arrow-up-right': CupertinoIcons.arrow_up_right,
  'arrow-down-left': CupertinoIcons.arrow_down_left,
  'equal': CupertinoIcons.equal,
  'split': CupertinoIcons.arrow_branch,
  'chart-pie': CupertinoIcons.chart_pie,
  'piggy-bank': CupertinoIcons.chart_pie,
  'receipt': CupertinoIcons.doc_text,
  'book-open': CupertinoIcons.book,
  'layout-grid': CupertinoIcons.square_grid_2x2,
  'upload': CupertinoIcons.square_arrow_up,
  'download': CupertinoIcons.square_arrow_down,
  'file-down': CupertinoIcons.square_arrow_down,
  'cloud': CupertinoIcons.cloud,
  'cloud-check': CupertinoIcons.cloud,
  'log-out': CupertinoIcons.square_arrow_right,
  'circle-user-round': CupertinoIcons.person_crop_circle,
  'user': CupertinoIcons.person,
  'users': CupertinoIcons.person_2,
  'sun-moon': CupertinoIcons.circle_lefthalf_fill,
  'languages': CupertinoIcons.globe,
  'shield-check': CupertinoIcons.checkmark_shield,
  'credit-card': CupertinoIcons.creditcard,
  'wallet': CupertinoIcons.creditcard,
  'wallet-cards': CupertinoIcons.creditcard,
  'banknote': CupertinoIcons.money_yen_circle,
  'tag': CupertinoIcons.tag,
  'archive': CupertinoIcons.archivebox,
  'ellipsis': CupertinoIcons.ellipsis,
  'store': CupertinoIcons.bag,
};

/// An interface icon: the SF-style glyph from [sfIcons] when there is one, otherwise the Lucide icon
/// (https://lucide.dev) drawn from the bundled SVG data in lucide_icons.dart.
class LIcon extends StatelessWidget {
  const LIcon(this.name, {super.key, this.size = 18, this.color, this.strokeWidth = 2, this.semanticLabel});

  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  static final Map<String, String> _cache = {};

  static String _svg(String name, double strokeWidth) {
    final key = '$name@$strokeWidth';
    return _cache.putIfAbsent(key, () {
      final body = lucideSvgs[name] ?? lucideSvgs['circle-question-mark']!;
      return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
          'stroke="currentColor" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final glyph = sfIcons[name];
    if (glyph != null) {
      // SF glyphs fill more of their box than Lucide's 24-unit grid; a heavier stroke asks for a bolder
      // glyph (e.g. chevrons drawn at 2.5), which the font gives through its weight.
      final icon = Icon(glyph, size: size * 1.05, color: resolved, weight: strokeWidth >= 2.5 ? 600 : 400);
      final sized = SizedBox(width: size, height: size, child: OverflowBox(maxWidth: size * 1.2, maxHeight: size * 1.2, child: icon));
      if (semanticLabel == null) return ExcludeSemantics(child: sized);
      return Semantics(label: semanticLabel, child: sized);
    }
    final picture = SvgPicture.string(
      _svg(name, strokeWidth),
      width: size,
      height: size,
      theme: SvgTheme(currentColor: resolved),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: picture);
    return Semantics(label: semanticLabel, child: picture);
  }
}

/// Two-tone line icon (Uxercon-style): the same Lucide geometry with rounded, slightly heavier strokes,
/// where the main outline is drawn at full colour and the inner details at reduced opacity. The main
/// shape is picked automatically as the element with the most drawing (longest markup).
class DuoIcon extends StatelessWidget {
  const DuoIcon(this.name, {super.key, this.size = 20, this.color, this.detailColor, this.strokeWidth = 2.1, this.detailOpacity = 0.45});
  final String name;
  final double size;
  final Color? color;

  /// Second colour for the details; without it they use [color] at [detailOpacity].
  final Color? detailColor;
  final double strokeWidth;
  final double detailOpacity;

  static final Map<String, String> _cache = {};
  static final RegExp _element = RegExp(r'<(path|circle|rect|line|polyline|polygon|ellipse)\b[^>]*/>');

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static String _svg(String name, double strokeWidth, double detailOpacity, Color? detail) {
    final key = '$name@$strokeWidth@$detailOpacity@${detail?.toARGB32()}';
    return _cache.putIfAbsent(key, () {
      final body = lucideSvgs[name] ?? lucideSvgs['circle-question-mark']!;
      final parts = _element.allMatches(body).map((m) => m.group(0)!).toList();
      var main = 0;
      for (var i = 1; i < parts.length; i++) {
        if (parts[i].length > parts[main].length) main = i;
      }
      final drawn = StringBuffer();
      for (var i = 0; i < parts.length; i++) {
        final secondary = detail == null ? ' stroke-opacity="$detailOpacity"/>' : ' stroke="${_hex(detail)}"/>';
        drawn.write(i == main || parts.length == 1 ? parts[i] : parts[i].replaceFirst('/>', secondary));
      }
      return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
          'stroke="currentColor" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">$drawn</svg>';
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black;
    return ExcludeSemantics(
      child: SvgPicture.string(_svg(name, strokeWidth, detailOpacity, detailColor), width: size, height: size, theme: SvgTheme(currentColor: resolved)),
    );
  }
}

/// Trial switch: show categories as emoji instead of Lucide line icons. Set to false to go back.
const bool useEmojiCategoryIcons = true;

/// A category's icon at [size]: an emoji while [useEmojiCategoryIcons] is on, otherwise the Lucide icon in [color].
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 18, this.color});
  final LedgerCategory category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final name = categoryIcon(category);
    if (!useEmojiCategoryIcons) return LIcon(name, size: size, color: color);
    return EmojiIcon(name, size: size);
  }
}

/// A category emoji, drawn with Apple's own emoji (Apple Color Emoji, the system font, native on iPhone
/// and Mac — the Trackly 得意記 look), centred in a square box. [name] is a category icon key (a Lucide
/// name) looked up in [categoryEmoji].
class EmojiIcon extends StatelessWidget {
  const EmojiIcon(this.name, {super.key, this.size = 18});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final box = size * 1.15;
    return ExcludeSemantics(
      child: SizedBox(
        width: box,
        height: box,
        child: Center(
          child: Text(
            categoryEmoji[name] ?? (isEmojiSymbol(name) ? name : '🏷️'),
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: size * 0.98, height: 1.0, fontFamilyFallback: const ['Apple Color Emoji']),
          ),
        ),
      ),
    );
  }
}

/// Apple emoji for each Lucide category icon. Only emoji that draw in colour by default: symbols from
/// the older text range (✈ ☎ ✂ ❤ 🅿) can render as black glyphs, so emoji-only stand-ins are used.
const Map<String, String> categoryEmoji = {
  'utensils': '🍽️', 'coffee': '☕', 'apple': '🍎', 'beer': '🍺', 'cake': '🎂', 'pizza': '🍕', 'hamburger': '🍔',
  'train-front': '🚇', 'bus': '🚌', 'car': '🚗', 'bike': '🚲', 'fuel': '⛽', 'square-parking': '🚙', 'plane': '🛫',
  'hotel': '🏨', 'map-pin': '📍', 'ticket': '🎟️',
  'shopping-bag': '🛍️', 'shopping-basket': '🧺', 'shirt': '👕', 'footprints': '👟', 'gem': '💎', 'package': '📦', 'store': '🏪',
  'house': '🏠', 'sofa': '🛋️', 'bath': '🛁', 'wrench': '🔧', 'trash': '🗑️', 'lightbulb': '💡',
  'zap': '⚡', 'droplet': '💧', 'flame': '🔥', 'wifi': '📶', 'phone': '📞', 'smartphone': '📱', 'laptop': '💻', 'tv': '📺', 'app-window': '📲',
  'pill': '💊', 'stethoscope': '🩺', 'heart': '💗', 'dumbbell': '🏋️', 'scissors': '💈', 'sparkles': '✨',
  'gamepad-2': '🎮', 'film': '🎬', 'music': '🎵', 'mic': '🎙️', 'palette': '🎨', 'book-open': '📚', 'graduation-cap': '🎓',
  'baby': '🍼', 'dog': '🐶', 'fish': '🐟', 'users': '👥', 'user': '🙂', 'gift': '🎁',
  'receipt': '🧾', 'shield-check': '🛡️', 'landmark': '🏛️', 'wallet': '👛', 'wallet-cards': '💳', 'credit-card': '💳',
  'briefcase': '💼', 'trending-up': '📈', 'hand-coins': '💰', 'banknote': '💵', 'piggy-bank': '🐷',
  'ellipsis': '📌', 'layout-grid': '🗂️', 'folder-search': '🗂️', 'tag': '🏷️',
};

/// Lucide icon for a category. New categories store a Lucide name; backups from the SwiftUI
/// version store SF Symbol names, and Money Pro imports a neutral default — both are mapped here,
/// falling back to keywords in the category name.
String categoryIcon(LedgerCategory category) {
  final symbol = category.symbol;
  // Any emoji chosen in the full emoji picker is stored as the emoji itself.
  if (isEmojiSymbol(symbol)) return symbol;
  if (lucideSvgs.containsKey(symbol) && symbol != 'layout-grid') return symbol;
  final mapped = _sfSymbols[symbol];
  if (mapped != null && mapped != 'layout-grid') return mapped;
  for (final rule in _nameRules) {
    if (rule.$1.any(category.name.toLowerCase().contains)) return rule.$2;
  }
  return category.kind == EntryKind.income ? 'banknote' : 'layout-grid';
}

const Map<String, String> _sfSymbols = {
  'fork.knife': 'utensils',
  'tram.fill': 'train-front',
  'bag.fill': 'shopping-bag',
  'house.fill': 'house',
  'sparkles': 'sparkles',
  'ellipsis.circle': 'ellipsis',
  'briefcase.fill': 'briefcase',
  'gift.fill': 'gift',
  'heart.fill': 'heart',
  'book.fill': 'book-open',
  'square.grid.2x2': 'layout-grid',
  'questionmark.folder': 'folder-search',
};

const List<(List<String>, String)> _nameRules = [
  // Specific names first, so they don't fall into a broader rule below (e.g. 书籍 before 书 → 教育).
  (['科技', '数码', '电子', '电脑'], 'laptop'),
  (['社交', '朋友', '聚会'], 'users'),
  (['杂货', '生活用品', '日用品'], 'shopping-basket'),
  (['杂项'], 'package'),
  (['店铺', '商业'], 'store'),
  (['个护', '护发', '護髮', '美发', '理发'], 'scissors'),
  (['个人'], 'user'),
  (['鱼', '海鲜'], 'fish'),
  (['鞋'], 'footprints'),
  (['衛浴', '卫浴'], 'bath'),
  (['傢俱', '家具', '家俱'], 'sofa'),
  (['天然气', '燃气'], 'flame'),
  (['上网', '宽带', '网费'], 'wifi'),
  (['电话'], 'phone'),
  (['有线电视', '电视'], 'tv'),
  (['供水', '水费'], 'droplet'),
  (['停车'], 'square-parking'),
  (['维护', '维修', '保养'], 'wrench'),
  (['書', '书籍'], 'book-open'),
  (['音乐'], 'music'),
  (['podcast', '播客'], 'mic'),
  (['应用程序', 'itunes'], 'app-window'),
  (['税'], 'landmark'),
  (['安全', '保安'], 'shield-check'),
  (['垃圾'], 'trash'),
  (['運動'], 'dumbbell'),
  (['車'], 'car'),
  (['住宅', '租金', '租房', '押金'], 'house'),
  (['日常开支'], 'wallet'),
  (['打工', '私单', '兼职'], 'briefcase'),
  (['赠金', '赠'], 'gift'),
  (['股息'], 'trending-up'),
  (['咖啡', '奶茶', '饮料'], 'coffee'),
  (['餐', '饭', '食', '外卖', '零食', '早点'], 'utensils'),
  (['水果'], 'apple'),
  (['酒'], 'beer'),
  (['地铁', '公交', '交通'], 'train-front'),
  (['打车', '车', '停车'], 'car'),
  (['油', '加油'], 'fuel'),
  (['机票', '旅', '出行'], 'plane'),
  (['酒店', '住宿'], 'hotel'),
  (['购物', '日用', '超市', '网购'], 'shopping-bag'),
  (['衣', '服饰', '服装'], 'shirt'),
  (['房租', '房贷', '居家', '住房', '物业', '家'], 'house'),
  (['水电', '燃气', '电费'], 'zap'),
  (['话费', '手机', '通讯', '网费'], 'smartphone'),
  (['医', '药', '健康'], 'pill'),
  (['运动', '健身'], 'dumbbell'),
  (['娱乐', '休闲', '游戏'], 'gamepad-2'),
  (['电影', '演出'], 'film'),
  (['教育', '学习', '书', '培训'], 'graduation-cap'),
  (['孩子', '宝宝', '育儿'], 'baby'),
  (['宠物', '猫', '狗'], 'dog'),
  (['礼', '红包', '人情'], 'gift'),
  (['美容', '理发', '美发'], 'scissors'),
  (['订阅', '会员', '软件'], 'receipt'),
  (['保险'], 'shield-check'),
  (['工资', '薪'], 'briefcase'),
  (['奖金', '分红'], 'gift'),
  (['理财', '利息', '投资', '收益'], 'trending-up'),
  (['报销', '退款'], 'hand-coins'),
  (['其他', '其它'], 'ellipsis'),
  // English category names
  (['coffee', 'tea', 'drink'], 'coffee'),
  (['food', 'meal', 'restaurant', 'dining', 'lunch', 'dinner', 'breakfast', 'snack', 'takeout'], 'utensils'),
  (['fruit'], 'apple'),
  (['beer', 'wine', 'bar'], 'beer'),
  (['metro', 'subway', 'bus', 'transit', 'transport'], 'train-front'),
  (['taxi', 'uber', 'car', 'parking'], 'car'),
  (['fuel', 'gas'], 'fuel'),
  (['flight', 'travel', 'trip'], 'plane'),
  (['hotel', 'lodging'], 'hotel'),
  (['shopping', 'grocer', 'supermarket'], 'shopping-bag'),
  (['cloth', 'apparel', 'shoe'], 'shirt'),
  (['rent', 'mortgage', 'home', 'house'], 'house'),
  (['utilit', 'electric', 'water'], 'zap'),
  (['phone', 'mobile', 'internet'], 'smartphone'),
  (['medic', 'health', 'doctor', 'pharma'], 'pill'),
  (['gym', 'fitness', 'sport'], 'dumbbell'),
  (['fun', 'leisure', 'game', 'entertain'], 'gamepad-2'),
  (['movie', 'cinema', 'concert'], 'film'),
  (['educat', 'school', 'book', 'course'], 'graduation-cap'),
  (['kid', 'child', 'baby'], 'baby'),
  (['pet'], 'dog'),
  (['gift', 'bonus'], 'gift'),
  (['beauty', 'hair'], 'scissors'),
  (['subscri', 'membership', 'software'], 'receipt'),
  (['insur'], 'shield-check'),
  (['salary', 'wage', 'payroll'], 'briefcase'),
  (['invest', 'interest', 'dividend'], 'trending-up'),
  (['refund', 'reimburs'], 'hand-coins'),
  (['other'], 'ellipsis'),
];

/// True when a category symbol is an emoji itself (picked from the full emoji set) rather than a
/// Lucide / SF Symbol name, which are plain ASCII.
bool isEmojiSymbol(String symbol) => symbol.isNotEmpty && symbol.runes.first > 0x7F;

/// The emoji a category icon key draws as (a Lucide key's mapped emoji, or the emoji itself).
String emojiFor(String icon) => categoryEmoji[icon] ?? (isEmojiSymbol(icon) ? icon : '🏷️');

/// The icon key to store for an emoji: the Lucide key when the emoji is one of the curated ones (so
/// existing data and the Lucide fallback keep working), otherwise the emoji itself.
String iconKeyForEmoji(String emoji) {
  for (final e in categoryEmoji.entries) {
    if (e.value == emoji) return e.key;
  }
  return emoji;
}

/// Icons offered when creating or editing a category: one per distinct emoji.
final List<String> categoryIconChoices = () {
  final seen = <String>{};
  return [
    for (final e in categoryEmoji.entries)
      if (seen.add(e.value)) e.key
  ];
}();
