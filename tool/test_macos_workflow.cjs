const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const workflow = readFileSync(join(__dirname, '../.github/workflows/build.yml'), 'utf8');

function job(name) {
  const start = workflow.indexOf(`\n  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const content = workflow.slice(start + 1);
  const next = content.slice(1).search(/^  [a-z][a-z0-9_-]*:/m);
  return next === -1 ? content : content.slice(0, next + 1);
}

test('macOS tests and builds using the validated build label', () => {
  const macos = job('macos');
  assert.match(macos, /needs: prepare/);
  assert.match(macos, /BUILD_LABEL: \$\{\{ needs\.prepare\.outputs\.label \}\}/);
  assert.match(macos, /flutter test/);
  assert.match(macos, /flutter build macos --release/);
  assert.match(macos, /Flutify-\$\{BUILD_LABEL\}-macos\.zip/);
  assert.match(macos, /--keepParent build\/macos\/Build\/Products\/Release\/Flutify\.app/);
  assert.match(macos, /name: macos/);
});

test('unsigned macOS artifacts cannot enter the existing release', () => {
  const release = job('release');
  assert.match(release, /needs: \[prepare, android, windows\]/);
  assert.match(release, /pattern: '\{android,windows-\*\}'/);
  assert.match(release, /merge-multiple: true/);
  assert.match(release, /-eq 8/);
  assert.match(release, /sha256sum Flutify-\*/);
});
