import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/search/place_search.dart';
import '../../data/search/umd_index.dart';
import '../../data/sync/geo.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'map_focus.dart';

/// 지도 위 검색창 — 주소를 쳐서 그 자리로 간다.
///
/// **평소에는 돋보기 하나다.** 입력창을 늘 펼쳐 두면 지도 위쪽을 계속 덮는다.
/// 지도는 이 앱의 본체이고, 검색은 가끔 쓰는 일이다 — 가끔 쓰는 것이 늘 쓰는
/// 것을 가리면 안 된다.
///
/// **결과를 고르기 전에는 아무것도 움직이지 않는다.** 치는 동안 지도가 따라
/// 움직이면, 사용자는 자기가 보던 자리를 잃는다. 되돌릴 방법도 없다.
class MapSearchBox extends ConsumerStatefulWidget {
  const MapSearchBox({super.key});

  @override
  ConsumerState<MapSearchBox> createState() => _MapSearchBoxState();
}

class _MapSearchBoxState extends ConsumerState<MapSearchBox> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _open = false;
  Timer? _debounce;

  UmdIndex? _umds;
  List<LocalPlace> _local = const [];
  List<PlaceHit> _hits = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 색인과 이 지역 자리들은 **열 때** 챙긴다.
  ///
  /// 앱을 켤 때 미리 받으면, 검색을 한 번도 안 쓰는 사람에게 268KB를 물린다.
  Future<void> _prepare() async {
    final sggCd = ref.read(selectedRegionProvider);
    final umds = await ref.read(umdIndexStoreProvider).load();
    final rows = sggCd == null
        ? const <LocalPlace>[]
        : (await ref.read(databaseProvider).searchablePlaces(sggCd))
              .map(
                (r) => LocalPlace(
                  umdNm: r.umdNm,
                  jibun: r.jibun,
                  name: r.name,
                  center: LatLng(r.lat, r.lng),
                ),
              )
              .toList();
    if (!mounted) return;
    setState(() {
      _umds = umds;
      _local = rows;
    });
    _run(_controller.text);
  }

  void _onChanged(String value) {
    // 한 번 훑는 데 1ms가 채 안 되지만(전국 18,696개, 실측 0.92ms), 빠르게 치는
    // 동안 매 글자 세는 것은 그만큼 배터리다. 멈춘 뒤 한 번만 센다.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _run(value));
  }

  void _run(String value) {
    if (!mounted) return;
    final hits = searchPlaces(
      query: value,
      regions: ref.read(regionIndexProvider).value,
      umds: _umds,
      local: _local,
    );
    setState(() => _hits = hits);
  }

  void _toggle() {
    final next = !_open;
    setState(() {
      _open = next;
      if (!next) {
        _controller.clear();
        _hits = const [];
      }
    });
    if (next) {
      _focus.requestFocus();
      unawaited(_prepare());
    } else {
      _focus.unfocus();
    }
  }

  void _choose(PlaceHit hit) {
    // 고르고 나면 닫는다. 열린 채로 두면 방금 간 자리를 검색창이 덮는다.
    setState(() {
      _open = false;
      _hits = const [];
    });
    _controller.clear();
    _focus.unfocus();

    switch (hit.kind) {
      // 시군구는 그 지역 전체가 보이게 연다. 중심점 한 곳으로 확대해 버리면
      // "강남구로 갔다"가 아니라 "강남구 어딘가로 갔다"가 된다.
      case PlaceKind.region:
        ref
            .read(selectedRegionProvider.notifier)
            .select(hit.sggCd, name: hit.title);
        ref.read(regionFocusProvider.notifier).request();
      // 법정동은 그 동으로 간다. 다른 지역이면 지역까지 바꿔야 그 지역 거래가
      // 내려온다 — 안 바꾸면 빈 지도로 데려다 놓는 셈이 된다.
      case PlaceKind.umd:
        if (hit.sggCd != ref.read(selectedRegionProvider)) {
          ref
              .read(selectedRegionProvider.notifier)
              .select(hit.sggCd, name: hit.subtitle.split(' ').last);
        }
        ref
            .read(mapFocusProvider.notifier)
            .request(hit.center.lat, hit.center.lng);
      case PlaceKind.place:
        ref
            .read(mapFocusProvider.notifier)
            .request(hit.center.lat, hit.center.lng);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: Alignment.centerRight,
        child: _RoundButton(icon: Icons.search, label: '주소 검색', onTap: _toggle),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Palette.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.search, size: 20, color: Palette.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  style: const TextStyle(fontSize: 15, color: Palette.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '동 이름 · 단지 이름 (예: 중곡동, ㅈㄱㄷ)',
                    hintStyle: TextStyle(fontSize: 14, color: Palette.ink3),
                  ),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: _toggle,
                icon: const Icon(Icons.close, size: 20, color: Palette.ink3),
              ),
            ],
          ),
        ),
        if (_controller.text.trim().length >= kMinQueryLength)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Results(
              hits: _hits,
              onPick: _choose,
              unavailable: searchUnavailable(
                ref.watch(regionIndexProvider).value,
              ),
            ),
          ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.hits,
    required this.onPick,
    required this.unavailable,
  });

  final List<PlaceHit> hits;
  final void Function(PlaceHit) onPick;

  /// 지역 목록을 아직 못 받았다 — 찾은 것이 없는 것과 다르다
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return Material(
        color: Palette.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            // 자료를 못 받은 것을 "없습니다"로 말하면 거짓말이 된다. 사용자는
            // 동 이름을 잘못 안 줄 알고 몇 번이고 다시 친다.
            unavailable
                ? '지역 목록을 아직 받지 못했습니다. 연결을 확인하고 잠시 뒤 다시 해 주세요.'
                // 못 찾았을 때 **무엇까지 찾을 수 있는지** 밝힌다. 그러지 않으면
                // 사용자는 도로명을 쳐 보고, 안 되면 앱이 고장 났다고 읽는다.
                : '찾는 것이 없습니다. 시·군·구와 동 이름, 그리고 지금 보는 지역의 '
                      '단지·지번을 찾습니다. 도로명(예: 테헤란로 123)은 찾지 못합니다.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Palette.ink3,
            ),
          ),
        ),
      );
    }

    return Material(
      color: Palette.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final hit in hits)
            InkWell(
              onTap: () => onPick(hit),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(_iconOf(hit.kind), size: 16, color: Palette.ink3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Palette.ink,
                            ),
                          ),
                          if (hit.subtitle.isNotEmpty)
                            Text(
                              hit.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Palette.ink3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData _iconOf(PlaceKind kind) => switch (kind) {
  PlaceKind.region => Icons.map_outlined,
  PlaceKind.umd => Icons.location_city_outlined,
  PlaceKind.place => Icons.place_outlined,
};

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: Palette.surface,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.search, size: 22, color: Palette.ink),
        ),
      ),
    ),
  );
}
