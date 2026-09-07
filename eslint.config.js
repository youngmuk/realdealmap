import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['**/dist/**', '**/node_modules/**', 'packages/shared/raw/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      'no-console': 'off',
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
  {
    files: ['**/scripts/**/*.mjs'],
    languageOptions: { globals: { console: 'readonly', process: 'readonly', Buffer: 'readonly', fetch: 'readonly', URLSearchParams: 'readonly', TextDecoder: 'readonly', setTimeout: 'readonly', AbortSignal: 'readonly' } },
  },
);
