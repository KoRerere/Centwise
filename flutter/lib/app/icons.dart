import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/models.dart';
import 'lucide_icons.dart';

/// A Lucide icon (https://lucide.dev) drawn from the bundled SVG data in lucide_icons.dart.
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
    // Fluent Emoji 3D artwork (bundled PNGs), so emoji look the same on iPhone and Mac. The art has
    // little padding, so it is drawn slightly larger than the line icons it replaces.
    return Emoji3DIcon(name, size: size);
  }
}

/// The Fluent Emoji 3D picture for a category icon key (a Lucide name, see [categoryEmoji3D]).
class Emoji3DIcon extends StatelessWidget {
  const Emoji3DIcon(this.name, {super.key, this.size = 18});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = categoryEmoji3D[name] ?? 'label';
    // The art has little padding, so it is drawn slightly larger than the line icons it replaces.
    return ExcludeSemantics(
      child: Image.asset('assets/emoji3d/$file.png',
          width: size * 1.15, height: size * 1.15, filterQuality: FilterQuality.medium, gaplessPlayback: true),
    );
  }
}

/// Fluent Emoji 3D file (`assets/emoji3d/NAME.png`, Microsoft, MIT licence) for each Lucide category
/// icon. Same choices as the earlier system-emoji set.
const Map<String, String> categoryEmoji3D = {
  'utensils': 'fork_and_knife_with_plate', 'coffee': 'hot_beverage', 'apple': 'red_apple', 'beer': 'beer_mug',
  'cake': 'birthday_cake', 'pizza': 'pizza', 'hamburger': 'hamburger', 'train-front': 'metro', 'bus': 'bus',
  'car': 'automobile', 'bike': 'bicycle', 'fuel': 'fuel_pump', 'square-parking': 'p_button',
  'plane': 'airplane', 'hotel': 'hotel', 'map-pin': 'round_pushpin', 'ticket': 'admission_tickets',
  'shopping-bag': 'shopping_bags', 'shopping-basket': 'basket', 'shirt': 't-shirt',
  'footprints': 'running_shoe', 'gem': 'gem_stone', 'package': 'package', 'store': 'convenience_store',
  'house': 'house', 'sofa': 'couch_and_lamp', 'bath': 'bathtub', 'wrench': 'wrench', 'trash': 'wastebasket',
  'lightbulb': 'light_bulb', 'zap': 'high_voltage', 'droplet': 'droplet', 'flame': 'fire',
  'wifi': 'antenna_bars', 'phone': 'telephone', 'smartphone': 'mobile_phone', 'laptop': 'laptop',
  'tv': 'television', 'app-window': 'mobile_phone_with_arrow', 'pill': 'pill', 'stethoscope': 'stethoscope',
  'heart': 'red_heart', 'dumbbell': 'person_lifting_weights', 'scissors': 'scissors', 'sparkles': 'sparkles',
  'gamepad-2': 'video_game', 'film': 'clapper_board', 'music': 'musical_note', 'mic': 'studio_microphone',
  'palette': 'artist_palette', 'book-open': 'books', 'graduation-cap': 'graduation_cap', 'baby': 'baby_bottle',
  'dog': 'dog_face', 'fish': 'fish', 'users': 'busts_in_silhouette', 'user': 'slightly_smiling_face',
  'gift': 'wrapped_gift', 'receipt': 'receipt', 'shield-check': 'shield', 'landmark': 'classical_building',
  'wallet': 'purse', 'wallet-cards': 'credit_card', 'credit-card': 'credit_card', 'briefcase': 'briefcase',
  'trending-up': 'chart_increasing', 'hand-coins': 'money_bag', 'banknote': 'dollar_banknote',
  'piggy-bank': 'pig_face', 'ellipsis': 'pushpin', 'layout-grid': 'card_index_dividers',
  'folder-search': 'card_index_dividers', 'tag': 'label',
};

/// Emoji for each Lucide category icon.
const Map<String, String> categoryEmoji = {
  'utensils': '🍽️', 'coffee': '☕', 'apple': '🍎', 'beer': '🍺', 'cake': '🎂', 'pizza': '🍕', 'hamburger': '🍔',
  'train-front': '🚇', 'bus': '🚌', 'car': '🚗', 'bike': '🚲', 'fuel': '⛽', 'square-parking': '🅿️', 'plane': '✈️',
  'hotel': '🏨', 'map-pin': '📍', 'ticket': '🎟️',
  'shopping-bag': '🛍️', 'shopping-basket': '🧺', 'shirt': '👕', 'footprints': '👟', 'gem': '💎', 'package': '📦', 'store': '🏪',
  'house': '🏠', 'sofa': '🛋️', 'bath': '🛁', 'wrench': '🔧', 'trash': '🗑️', 'lightbulb': '💡',
  'zap': '⚡', 'droplet': '💧', 'flame': '🔥', 'wifi': '📶', 'phone': '☎️', 'smartphone': '📱', 'laptop': '💻', 'tv': '📺', 'app-window': '📲',
  'pill': '💊', 'stethoscope': '🩺', 'heart': '❤️', 'dumbbell': '🏋️', 'scissors': '✂️', 'sparkles': '✨',
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

/// Icons offered when creating a category.
/// Icons offered when creating or editing a category: one per distinct 3D picture.
final List<String> categoryIconChoices = () {
  final seen = <String>{};
  return [
    for (final e in categoryEmoji3D.entries)
      if (seen.add(e.value)) e.key
  ];
}();
