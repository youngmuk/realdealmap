/**
 * 배경지도 스타일(style-ko.json)을 만든다.
 *
 *   node packages/ingest/scripts/build-basemap-style.mjs [출력경로]
 *
 * **왜 손으로 만드나.** Protomaps 기본 테마를 그대로 쓰면 안드로이드에서
 * 라벨이 한 글자도 나오지 않는다. 실기기에서 확인한 원인이 두 가지다.
 *
 * 1. **PGF 표현식.** 테마 v4의 라벨은 `pgf:name`·`script` 같은 속성을 읽는
 *    Protomaps Glyph Format 표현식이다. GL JS 전용이라 maplibre 네이티브가
 *    평가하지 못하고, 그 심볼 레이어는 **조용히 라벨 없이** 그려진다.
 *    타일을 뜯어보면 `name`과 `name:ko`에 한글 지명이 그대로 들어 있으므로
 *    coalesce(name:ko, name)로 갈아 끼운다.
 * 2. **한글 글리프 부재.** Protomaps가 공개한 글리프 서버는 한글 범위를
 *    요청하면 29바이트짜리 빈 PBF를 돌려준다(44032-44287, 49408-49663에서 확인).
 *    그래서 Noto Sans KR(OFL)로 SDF 글리프를 직접 구워 R2에 얹고 이쪽을 가리킨다.
 *    한글에는 이탤릭이 없어 이탤릭 지정은 Regular로 접는다.
 *
 * 굽는 방법과 업로드 절차는 `Doc/배경지도-구성.html`에 적어 두었다.
 */
import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const themes = require('protomaps-themes-base');

/** 공개 버킷. 비밀이 아니다 — 앱에도 같은 주소가 들어간다. */
const BASE = 'https://pub-3d1c47ba21f4453e8b5ab29c6746ea9d.r2.dev/v1/basemap';

/** 배경지도 타일. 날짜가 붙어 있어 새 빌드를 올려도 캐시가 섞이지 않는다. */
const PMTILES = `${BASE}/korea-20260907.pmtiles`;

/** 라벨에 쓸 이름. 한국어가 없으면 원래 이름으로 떨어진다. */
const NAME = ['coalesce', ['get', 'name:ko'], ['get', 'name']];

/** 테마가 부르는 글꼴 → R2에 올린 글꼴. */
const FONT = {
  'Noto Sans Regular': 'NotoSansKR-Regular',
  'Noto Sans Medium': 'NotoSansKR-Medium',
  'Noto Sans Italic': 'NotoSansKR-Regular',
};
const DEFAULT_FONT = FONT['Noto Sans Regular'];

/** 표현식으로 된 text-font를 평평하게 편다. 네이티브는 표현식을 못 읽는다. */
const flattenFont = (value) => {
  if (Array.isArray(value) && value.every((x) => typeof x === 'string')) return value;
  const found = JSON.stringify(value ?? '').match(/Noto Sans [A-Za-z]+/g);
  return found ? found.slice(0, 1) : ['Noto Sans Regular'];
};

/**
 * 건물 외곽선을 넣는다.
 *
 * 테마의 `buildings`는 **fill 하나뿐이다.** 그래서 건물이 서로 맞닿은 동네에서는
 * 회색 한 덩어리가 되고 어디까지가 한 채인지 보이지 않는다. 실기기에서 확인했다.
 *
 * `fill-outline-color` 대신 line 레이어를 따로 둔다. 그쪽은 굵기를 못 정해
 * 항상 1px인데, 건물이 작게 보이는 배율에서는 그 1px이 면을 거의 덮어 버린다.
 * 여기서는 줌에 따라 가늘게 시작해 굵어지게 한다.
 *
 * 채우기 **바로 위**에 넣는다. 더 위에 두면 도로와 라벨을 가린다.
 */
const addBuildingOutline = (layers) => {
  const at = layers.findIndex((l) => l.id === 'buildings');
  // 테마가 바뀌어 레이어 이름이 달라지면 조용히 넘어가지 않는다. 외곽선이
  // 없는 것은 화면만 봐서는 "원래 그런가 보다"와 구별되지 않는다.
  if (at < 0) throw new Error('buildings 레이어를 찾지 못했다');

  layers.splice(at + 1, 0, {
    id: 'buildings-outline',
    type: 'line',
    source: 'protomaps',
    'source-layer': 'buildings',
    filter: layers[at].filter,
    // 건물 타일 자체가 z11부터다. 그보다 낮은 배율에서는 건물이 점만 해서
    // 선을 그어도 얼룩으로만 보인다.
    minzoom: 15,
    paint: {
      'line-color': '#9E9689',
      'line-width': ['interpolate', ['linear'], ['zoom'], 15, 0.3, 17, 0.7, 20, 1.2],
      'line-opacity': ['interpolate', ['linear'], ['zoom'], 15, 0.35, 17, 0.8],
    },
  });
  return 1;
};

const buildStyle = () => {
  const layers = themes.layersWithCustomTheme('protomaps', themes.namedTheme('light'), 'ko');
  let labels = 0;
  let fonts = 0;

  for (const layer of layers) {
    if (layer.type !== 'symbol' || !layer.layout) continue;

    const before = JSON.stringify(layer.layout['text-font']);
    const mapped = flattenFont(layer.layout['text-font']).map((n) => FONT[n] ?? DEFAULT_FONT);
    layer.layout['text-font'] = [...new Set(mapped)];
    if (JSON.stringify(layer.layout['text-font']) !== before) fonts += 1;

    // 건물 번지 라벨은 이름이 아니라 addr_housenumber다. 그대로 둔다.
    if (layer.id === 'address_label') continue;
    const field = JSON.stringify(layer.layout['text-field'] ?? '');
    if (field.includes('pgf:') || field.includes('"script"')) {
      layer.layout['text-field'] = NAME;
      labels += 1;
    }
  }

  const outlines = addBuildingOutline(layers);

  return {
    outlines,
    style: {
      version: 8,
      name: '실거래가 지도 배경',
      glyphs: `${BASE}/fonts/{fontstack}/{range}.pbf`,
      sprite: `${BASE}/sprite/light`,
      sources: {
        protomaps: {
          type: 'vector',
          url: `pmtiles://${PMTILES}`,
          attribution:
            '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        },
      },
      layers,
    },
    labels,
    fonts,
  };
};

const main = () => {
  const [out = 'style-ko.json'] = process.argv.slice(2);
  const { style, labels, fonts, outlines } = buildStyle();
  const json = JSON.stringify(style);

  // 테마 API를 잘못 부르면 색이 null로 채워진 스타일이 나온다. 그러면 앱은
  // "ParseStyle: Expected color but found null"만 남기고 **빈 지도를 그린다.**
  // 실제로 그렇게 한 회차가 있어서 여기서 막는다.
  if (json.includes('null')) throw new Error('스타일에 null이 남아 있다');
  // 바꾸지 못한 글꼴이 있으면 그 레이어만 라벨이 사라진다. 조용히 넘기지 않는다.
  if (json.includes('Noto Sans ')) throw new Error('바꾸지 못한 글꼴이 남아 있다');

  writeFileSync(out, json);
  console.log(
    `${out} — 레이어 ${style.layers.length} · 라벨 ${labels} · 글꼴 ${fonts} · ` +
      `외곽선 ${outlines} · ` +
      `${(json.length / 1024).toFixed(1)}KB`,
  );
};

main();
