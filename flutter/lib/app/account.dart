import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'components.dart';
import 'icons.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// 设置 → 账号: sign-in entry when signed out; account details and iCloud sync when signed in.
/// Layout follows Copilot's settings "Account" group (plain rows, chevrons, log-out row).
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  void _openSignIn(BuildContext context) {
    final store = StoreScope.read(context);
    showCwSheet<void>(context, (_) => StoreScope(store: store, child: const SignInSheet()));
  }

  Future<void> _signOut(BuildContext context) async {
    final store = StoreScope.read(context);
    final ok = await confirmDestructive(context, tr('退出后本机账本仍会保留，但不再通过 iCloud 同步。'), tr('退出登录'));
    if (ok) store.update(() => store.account = null);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final account = store.account;

    if (account == null) {
      return FormSection(
        title: tr('账号'),
        footer: tr('登录后，账本通过你的 iCloud 在 iPhone 和 Mac 之间同步。不登录也能完整使用，数据保存在本机。'),
        children: [
          Pressable(
            onTap: () => _openSignIn(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                _Avatar(icon: 'circle-user-round', palette: p),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('登录 Centwise'), style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(tr('同步你的账本，换设备不丢数据'), style: cw(IOSText.footnote, color: p.muted)),
                  ]),
                ),
                LIcon('chevron-right', size: 16, color: p.muted.withValues(alpha: 0.7)),
              ]),
            ),
          ),
        ],
      );
    }

    final synced = account.lastSynced;
    return FormSection(
      title: tr('账号'),
      footer: store.isDemo ? tr('预览模式：这是演示账号，没有真正连接 iCloud。') : null,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            _Avatar(icon: 'circle-user-round', palette: p),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(account.name, style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
                const SizedBox(height: 2),
                Text(account.email, style: cw(IOSText.footnote, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        FormRow(
          icon: 'cloud',
          label: tr('iCloud 同步'),
          trailing: IOSSwitch(
            value: account.syncEnabled,
            onChanged: (on) => store.update(() => account.syncEnabled = on),
          ),
        ),
        if (account.syncEnabled)
          FormRow(
            icon: 'refresh-cw',
            label: tr('立即同步'),
            trailing: Text(synced == null ? tr('尚未同步') : tr('上次 {time}', {'time': _time(synced)}), style: cw(IOSText.subheadline, color: p.muted)),
            onTap: () => store.update(() => account.lastSynced = DateTime.now()),
          ),
        FormRow(icon: 'log-out', label: tr('退出登录'), chevron: true, onTap: () => _signOut(context)),
      ],
    );
  }

  static String _time(DateTime t) {
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) return tr('今天 {time}', {'time': hm});
    return '${fmtMonthDay(t)} $hm';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.icon, required this.palette});
  final String icon;
  final Palette palette;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: palette.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Center(child: LIcon(icon, size: 24, color: palette.accent)),
      );
}

/// Sign-in sheet, modelled on Copilot's "Welcome back" screen: title, short line of copy,
/// a black "Sign in with Apple" button. Sync goes through the user's own iCloud, so there is no email / password.
class SignInSheet extends StatelessWidget {
  const SignInSheet({super.key});

  Future<void> _signInWithApple(BuildContext context) async {
    final store = StoreScope.read(context);
    if (store.isDemo) {
      store.update(() => store.account = AccountInfo(name: tr('演示账号'), email: 'demo@privaterelay.appleid.com', lastSynced: DateTime.now()));
      Navigator.of(context).pop();
      return;
    }
    await showCwAlert(
      context,
      tr('暂未开放'),
      tr('Apple 登录与 iCloud 同步需要 Apple 开发者账号和 iCloud 权限，接入后即可使用。\n\n在此之前，可以用「导出完整备份」在设备之间转移账本。'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetScaffold(
      title: tr('登录'),
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(24, 28, 24, 32), children: [
        Text(tr('欢迎使用 Centwise'), textAlign: TextAlign.center, style: cw(24, weight: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 8),
        Text(tr('登录后，你的账本会通过 iCloud\n在 iPhone 和 Mac 之间保持同步。'),
            textAlign: TextAlign.center, style: cw(IOSText.body, color: p.muted, height: 1.5)),
        const SizedBox(height: 32),
        AppleSignInButton(onTap: () => _signInWithApple(context)),
        const SizedBox(height: 28),
        CwCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: [
            _Benefit(icon: 'cloud-check', title: tr('存在你自己的 iCloud'), detail: tr('Centwise 没有服务器，不经手你的账本。')),
            Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
            _Benefit(icon: 'refresh-cw', title: tr('多设备自动同步'), detail: tr('在 iPhone 记一笔，Mac 上马上能看到。')),
            Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
            _Benefit(icon: 'shield-check', title: tr('不登录也能用'), detail: tr('所有功能照常可用，数据只保存在本机。')),
          ]),
        ),
      ]),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.detail});
  final String icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: LIcon(icon, size: 18, color: p.accent)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 2),
            Text(detail, style: cw(IOSText.footnote, color: p.muted, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

/// "通过 Apple 登录" button following Apple's Sign in with Apple guidelines: black in light mode,
/// white in dark mode, Apple logo + label. The logo is Apple's mark (path from simple-icons, CC0),
/// the one icon that is not from Lucide because Apple requires its own logo on this button.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({super.key, required this.onTap});
  final VoidCallback onTap;

  static const String _logo =
      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg>';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? Colors.white : Colors.black;
    final foreground = dark ? Colors.black : Colors.white;
    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      semanticLabel: tr('通过 Apple 登录'),
      child: Container(
        height: 52,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SvgPicture.string(_logo, width: 18, height: 18, theme: SvgTheme(currentColor: foreground)),
          const SizedBox(width: 8),
          Text(tr('通过 Apple 登录'), style: cw(IOSText.headline, weight: FontWeight.w600, color: foreground)),
        ]),
      ),
    );
  }
}
