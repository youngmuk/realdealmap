/**
 * 시군구 경계 폴리곤을 굽는다 (좌표 → 시군구 판정용).
 *
 *   node packages/ingest/scripts/build-region-boundaries.mjs <행정동geojson> <출력경로> [허용오차도]
 *
 * 결과는 **앱에 넣는 에셋**이다(`app/assets/regions/boundaries.json.gz`).
 * 받아 오지 않고 넣는 이유: 첫 실행에서 "지금 있는 곳"을 여는 것이 네트워크보다
 * 먼저 일어나야 하고, 경계는 행정 개편이 있을 때나 바뀌어 갱신할 일이 드물다.
 * 400KB를 얹는 대신 받기·캐시·무효화가 통째로 없어진다.
 *
 * **왜 필요한가.** 지금까지는 경계상자로 판정했다 — 그 시군구의 거래가 퍼져 있는
 * 사각형에 점이 들어가는지 보고, 여럿이 걸리면 중심이 가까운 것을 골랐다.
 * 이웃 구끼리 사각형이 겹쳐서 실측 오답이 **9.84%**였다(정확좌표 24,958개 표본).
 * 강남구가 송파구로, 경주시가 울주군으로 갔다.
 *
 * 원자료는 통계청 SGIS 행정동 경계(공공누리 제1유형)를 vuski/admdongkor이
 * 가공해 CC BY 4.0으로 배포하는 것이다. 출처 표기 의무가 있어 파일 안에 함께 싣고
 * 앱 정보 화면에도 남긴다.
 *
 * **행정동을 시군구로 합치지 않는다.** 합치려면 위상을 다루는 라이브러리가 필요한데,
 * 판정에는 필요가 없다 — 어느 행정동에 들었든 그 행정동의 시군구가 답이다.
 * 대신 같은 시군구의 조각들을 한 묶음으로 모아 둔다.
 */
import { gzipSync } from 'node:zlib';
import { readFileSync, writeFileSync } from 'node:fs';

/** 좌표를 소수점 몇 자리로 줄일지. 5자리면 약 1.1m라 시군구 경계에는 넘친다. */
const PRECISION = 5;

/**
 * 얼마나 성기게 만들 것인가. 실측으로 고른 값이다.
 *
 * 표본 24,836개(정확좌표, 시군구 10곳)로 잰 gzip 크기와 정답률:
 *
 *   0.0002도(22m)  1,279KB  99.96%
 *   0.001도(111m)    609KB  99.92%
 *   **0.002도(222m)  395KB  99.91%**
 *   0.003도(333m)    299KB  99.92%
 *   0.005도(555m)    207KB  97.77%
 *
 * 22m와 222m의 차이는 0.05%p인데 파일은 3.2배다. 반대로 555m부터는 무너진다.
 * 0.002를 고른 것은 0.003과 정답률이 같으면서 **점의 97.9%가 회수 없이 그냥
 * 폴리곤 안에 들어오기** 때문이다(0.003은 95.3%). 회수는 어림짐작이고
 * 담기는 것은 사실이라, 같은 값이면 사실 쪽이 많은 편이 낫다.
 */
const DEFAULT_TOLERANCE = 0.002;

/**
 * 폴리곤 밖으로 밀려난 점을 몇 도까지 주울 것인가 — 허용오차의 배수.
 *
 * 성기게 만들면 경계에서 최대 [허용오차]만큼 선이 안쪽으로 들어올 수 있고,
 * 그 띠에 있던 점은 자기 시군구 밖으로 떨어진다. 그 점을 **테두리가 가장
 * 가까운 시군구**로 되돌린다. 표본에서는 511개가 밀렸고 511개 전부
 * 제자리로 돌아왔다.
 *
 * **1.0도 같은 넓은 값을 쓰면 안 된다.** 그러면 바다 한가운데나 아직 배포되지
 * 않은 곳에 있는 사람에게도 억지로 지역을 붙이게 된다. 여기서 줍고 싶은 것은
 * 우리가 만든 오차뿐이라 그만큼만 준다.
 */
const SNAP_FACTOR = 1.5;

/**
 * 링 하나를 성기게 만든다 (Douglas-Peucker).
 *
 * 라이브러리를 쓰지 않는다. 여기서 필요한 것은 위상 보존이 아니라 **점 하나가
 * 안이냐 밖이냐**뿐이고, 그 판정은 링을 조금 흔들어도 경계에서 몇십 미터
 * 안에서만 달라진다. 지금 오차가 킬로미터 단위라 비교가 되지 않는다.
 */
const simplify = (points, tolerance) => {
  if (points.length <= 3) return points;

  const sqTol = tolerance * tolerance;
  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;

  // 재귀 대신 명시적 스택. 해안선 링은 점이 수만 개라 재귀로는 스택이 넘친다.
  const stack = [[0, points.length - 1]];
  while (stack.length > 0) {
    const [first, last] = stack.pop();
    let farthest = 0;
    let at = -1;
    for (let i = first + 1; i < last; i++) {
      const d = sqSegmentDistance(points[i], points[first], points[last]);
      if (d > farthest) {
        farthest = d;
        at = i;
      }
    }
    if (at >= 0 && farthest > sqTol) {
      keep[at] = 1;
      stack.push([first, at], [at, last]);
    }
  }

  const out = [];
  for (let i = 0; i < points.length; i++) if (keep[i]) out.push(points[i]);
  return out;
};

const sqSegmentDistance = (p, a, b) => {
  let [x, y] = a;
  let dx = b[0] - x;
  let dy = b[1] - y;
  if (dx !== 0 || dy !== 0) {
    const t = ((p[0] - x) * dx + (p[1] - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      [x, y] = b;
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  dx = p[0] - x;
  dy = p[1] - y;
  return dx * dx + dy * dy;
};

const round = (n) => Number(n.toFixed(PRECISION));

const main = () => {
  const [src, out, toleranceArg] = process.argv.slice(2);
  if (!src || !out) {
    throw new Error('쓰임: build-region-boundaries.mjs <행정동geojson> <출력.json> [허용오차도]');
  }
  const tolerance = Number(toleranceArg ?? DEFAULT_TOLERANCE);

  const geo = JSON.parse(readFileSync(src, 'utf8'));
  const bySgg = new Map();

  for (const feature of geo.features) {
    const sggCd = feature.properties?.sgg;
    // 코드가 없는 줄은 조용히 버리지 않는다. 한 시군구가 통째로 빠지면
    // 그 지역 사용자에게만 예전 동작이 남아 화면만 봐서는 알 수 없다.
    if (!sggCd || sggCd.length !== 5) {
      throw new Error(`sgg 코드가 이상하다: ${JSON.stringify(feature.properties)}`);
    }
    const geometry = feature.geometry;
    if (!geometry) continue;

    const polygons =
      geometry.type === 'Polygon'
        ? [geometry.coordinates]
        : geometry.type === 'MultiPolygon'
          ? geometry.coordinates
          : null;
    if (polygons === null) throw new Error(`다룰 수 없는 도형: ${geometry.type}`);

    const entry = bySgg.get(sggCd) ?? { sggCd, polygons: [] };
    for (const rings of polygons) {
      const kept = [];
      for (const ring of rings) {
        const thin = simplify(ring, tolerance).map(([lng, lat]) => [round(lng), round(lat)]);
        // 삼각형도 못 되면 면적이 없다. 그런 조각은 어떤 점도 담지 못한다.
        if (thin.length >= 4) kept.push(thin);
      }
      // 바깥 링이 사라졌으면 구멍만 남으므로 통째로 버린다.
      if (kept.length > 0) entry.polygons.push(kept);
    }
    bySgg.set(sggCd, entry);
  }

  const regions = [...bySgg.values()].map((entry) => {
    let south = 90;
    let north = -90;
    let west = 180;
    let east = -180;
    let points = 0;
    // 경계상자를 함께 싣는다. 앱이 먼저 이것으로 걸러야 250개 시군구를
    // 전부 점검하지 않는다.
    for (const rings of entry.polygons) {
      for (const [lng, lat] of rings[0]) {
        if (lat < south) south = lat;
        if (lat > north) north = lat;
        if (lng < west) west = lng;
        if (lng > east) east = lng;
      }
      for (const ring of rings) points += ring.length;
    }
    return {
      sggCd: entry.sggCd,
      bbox: { south, north, west, east },
      // 평평하게 편다. [[lng,lat],...] 보다 [lng,lat,...] 쪽이 JSON에서 훨씬 짧다.
      polygons: entry.polygons.map((rings) => rings.map((ring) => ring.flat())),
      points,
    };
  });

  regions.sort((a, b) => (a.sggCd < b.sggCd ? -1 : 1));

  const payload = {
    schemaVersion: 1,
    // **출처 표기는 의무다.** 파일에 실어 두면 어디로 복사되든 따라간다.
    attribution:
      '통계청 통계지리정보서비스(SGIS, https://sgis.kostat.go.kr)가 공공누리 제1유형으로 ' +
      '개방한 행정동 경계를 가공한 것이며(가공: vuski/admdongkor, ' +
      'https://github.com/vuski/admdongkor), CC BY 4.0으로 배포됩니다.',
    toleranceDegrees: tolerance,
    snapDegrees: Number((tolerance * SNAP_FACTOR).toFixed(6)),
    regions: regions.map(({ points: _points, ...rest }) => rest),
  };

  const json = JSON.stringify(payload);
  // 끝이 .gz면 압축해서 쓴다. 앱에 넣는 것은 압축본이고, 눈으로 확인할 때만
  // 풀린 것을 쓴다 — 둘 다 늘 만들면 저장소에 안 쓰는 4MB가 남는다.
  const gz = gzipSync(json, { level: 9 });
  writeFileSync(out, out.endsWith('.gz') ? gz : json);

  const totalPoints = regions.reduce((sum, r) => sum + r.points, 0);
  console.log(
    `${out} — 시군구 ${regions.length} · 조각 ${regions.reduce((s, r) => s + r.polygons.length, 0)} · ` +
      `점 ${totalPoints.toLocaleString()} · 허용오차 ${tolerance}도(약 ${Math.round(tolerance * 111000)}m)`,
  );
  console.log(
    `  풀어서 ${(json.length / 1024).toFixed(0)} KB · gzip ${(gz.length / 1024).toFixed(0)} KB` +
      ` · 밖으로 밀린 점은 ${(payload.snapDegrees * 111000).toFixed(0)}m까지 줍는다`,
  );
};

main();
