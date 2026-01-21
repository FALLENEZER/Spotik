/* eslint-env node */
require('@rushstack/eslint-patch/modern-module-resolution')

module.exports = {
  root: true,
  extends: ['plugin:vue/vue3-essential', 'eslint:recommended', '@vue/eslint-config-prettier'],
  parserOptions: {
    ecmaVersion: 'latest',
  },
  env: {
    node: true,
    browser: true,
  },
  overrides: [
    {
      files: ['**/*.config.js', '**/*.config.cjs'],
      env: {
        node: true,
      },
      globals: {
        require: 'readonly',
        __dirname: 'readonly',
      },
    },
    {
      files: ['src/test/**/*.js', '**/*.test.js', '**/*.spec.js'],
      env: {
        node: true,
        browser: true,
      },
      globals: {
        global: 'writable',
        vi: 'readonly',
      },
    },
  ],
  rules: {
    'vue/multi-word-component-names': 'off',
    'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    'no-console': process.env.NODE_ENV === 'production' ? 'warn' : 'off',
    'no-debugger': process.env.NODE_ENV === 'production' ? 'warn' : 'off',
  },
}
