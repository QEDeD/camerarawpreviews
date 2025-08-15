module.exports = {
  root: true,
  extends: [
    '@nextcloud/eslint-config',
  ],
  env: {
    browser: true,
    es2021: true,
  },
  parserOptions: {
    ecmaVersion: 2021,
    sourceType: 'module',
  },
  ignorePatterns: [
    'build/**',
    'vendor/**',
    'nextcloud/**',
  ],
  overrides: [
    {
      files: ['js/register-viewer.js'],
      rules: {
        'no-console': 'off',
      },
    },
  ],
}
