import { fileURLToPath } from 'node:url';

import { defineConfig } from 'vitest/config';

const shared = fileURLToPath(new URL('./packages/shared/src/index.ts', import.meta.url));
const sharedCodes = fileURLToPath(
  new URL('./packages/shared/src/codes.generated.ts', import.meta.url),
);

export default defineConfig({
  resolve: {
    // 패키지 매니페스트는 Node 실행을 위해 dist를 가리킨다.
    // 테스트는 소스를 그대로 읽어야 커버리지가 실제 코드에 붙는다.
    // 서브패스가 먼저 와야 한다. 배럴 별칭이 앞서면 `@realdealmap/shared/codes`가
    // `.../index.ts/codes`로 잘못 풀린다.
    alias: [
      { find: '@realdealmap/shared/codes', replacement: sharedCodes },
      { find: '@realdealmap/shared', replacement: shared },
    ],
  },
  test: {
    include: ['packages/*/src/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['packages/*/src/**/*.ts'],
      // index.ts는 재수출만, types.ts는 타입 선언만이라 실행 코드가 없다.
      exclude: ['packages/*/src/**/*.test.ts', 'packages/*/src/index.ts', 'packages/*/src/types.ts'],
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});
