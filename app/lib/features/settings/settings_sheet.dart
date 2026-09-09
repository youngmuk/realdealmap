/// 설정 (T6.7).
///
/// **참고용 고지가 여기로 왔다.** 전에는 머리말에 상시 노출했는데, 그 한 줄이
/// 지도 위쪽을 계속 차지하면서도 사용자가 하루에 한 번도 누르지 않는 자리였다.
/// G6가 요구하는 것은 "참고용 고지가 **표시된다**"이지 상시 노출이 아니다.
///
/// 다만 **닿기 어려우면 표시하지 않은 것과 같다.** 그래서 두 곳에 둔다 —
/// 여기(설정)와 [DetailSheet](금액을 실제로 읽는 자리). 설정 버튼은 지도
/// 오른쪽 아래에 늘 떠 있어 두 탭 어디서든 한 번에 닿는다.
library;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme.dart';
import '../about/about_sheet.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Palette.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const SettingsSheet(),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      // 아래는 모두 80%로 줄인 값이다. 글자만 줄이면 여백이 그대로 남아
      // 화면은 그대로인 채 글씨만 작아진다.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 29,
              height: 3,
              decoration: BoxDecoration(
                color: Palette.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '실거래지도',
            style: TextStyle(
              fontSize: 13.6,
              fontWeight: FontWeight.w800,
              color: Palette.ink,
            ),
          ),
          const SizedBox(height: 3),
          const _Version(),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Palette.rule),
          const SizedBox(height: 5),
          // 고지는 **가장 크게** 둔다. 이 화면에서 사용자가 눌러야 하는 것이
          // 이것 하나뿐이고, 작게 두면 설정 화면으로 옮긴 것이 곧 감춘 것이 된다.
          _Item(
            icon: Icons.info_outline,
            label: kNotice,
            onTap: () {
              Navigator.of(context).pop();
              AboutSheet.show(context);
            },
          ),
        ],
      ),
    ),
  );
}

/// 설치된 패키지에서 읽는다.
///
/// pubspec의 값을 소스에 베껴 두지 않는다 — 빌드번호는 배포 스크립트가
/// 올리므로 베껴 두면 **반드시 어긋난다.** 버그 신고에 적히는 숫자라
/// 어긋나면 어느 빌드인지 못 찾는다.
class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snapshot) {
      final info = snapshot.data;
      // 읽는 동안에도 자리를 지킨다. 비었다가 나타나면 화면이 튄다.
      final text = info == null
          ? '버전 확인 중'
          : '버전 ${info.version} (${info.buildNumber})';
      return Text(
        text,
        style: const TextStyle(fontSize: 10, color: Palette.ink3),
      );
    },
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 14.4, color: Palette.slate),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
                color: Palette.ink,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 14.4, color: Palette.ink3),
        ],
      ),
    ),
  );
}
