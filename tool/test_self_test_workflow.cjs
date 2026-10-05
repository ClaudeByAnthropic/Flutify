const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const read = (path) => readFileSync(join(__dirname, '..', path), 'utf8').replace(/\r\n/g, '\n');
const workflow = () => read('.github/workflows/self-test.yml');

function job(name) {
  const source = workflow();
  const start = source.indexOf(`\n  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const rest = source.slice(start + 1);
  const next = rest.slice(1).search(/^  [a-z][a-z0-9_-]*:/m);
  return next === -1 ? rest : rest.slice(0, next + 1);
}

test('self-test runs on branch pushes, main PRs and manual requests, never tag pushes', () => {
  const source = workflow();
  assert.match(source, /push:\n    branches: \['\*\*'\]/);
  assert.match(source, /pull_request:\n    branches: \[main\]/);
  assert.match(source, /  workflow_dispatch:/);
  assert.doesNotMatch(source, /tags:|pull_request_target:|workflow_run:/);
});

test('self-test has read-only credentials and no production secrets or publication path', () => {
  const source = workflow();
  assert.match(source, /permissions:\n  contents: read/);
  assert.doesNotMatch(source, /contents: write|write-all|secrets[.[]|secrets: inherit/);
  assert.doesNotMatch(source, /action-gh-release|gh release|git push|publish_release|continue-on-error/);
  const checkouts = source.match(/uses: actions\/checkout@v4/g) || [];
  assert.ok(checkouts.length > 0);
  assert.equal((source.match(/persist-credentials: false/g) || []).length, checkouts.length);
});

test('quality checks run static analysis and every Flutter, Node and Python regression', () => {
  const quality = job('quality');
  assert.match(quality, /flutter analyze --no-pub --no-fatal-infos lib test/);
  assert.match(quality, /flutter test --no-pub/);
  assert.match(quality, /node --test tool\/test_\*\.cjs/);
  assert.match(quality, /python3 -m unittest discover -s tool -p 'test_\*\.py'/);
  assert.doesNotMatch(quality, /no-fatal-warnings|\|\| true/);
});

test('Android tests release builds using a disposable key and verifies all four APKs', () => {
  const android = job('android');
  assert.match(android, /needs: quality/);
  assert.match(android, /bash tool\/create_self_test_android_key\.sh/);
  assert.match(android, /flutter build apk --release --no-pub --split-per-abi/);
  assert.match(android, /flutter build apk --release --no-pub --build-number/);
  assert.match(android, /python3 tool\/verify_android_apks\.py build\/app\/outputs\/flutter-apk/);
  assert.match(android, /if: always\(\)\n        run: rm -f "\$RUNNER_TEMP\/flutify-self-test\.p12"/);
  assert.match(android, /Flutify-self-test-/);
  assert.match(android, /name: self-test-android/);
  assert.match(android, /if-no-files-found: error/);
  assert.match(android, /retention-days: 7/);
});

test('the separate release pipeline still requires fixed signing secrets and certificate checks', () => {
  const release = read('.github/workflows/build.yml');
  const gradle = read('android/app/build.gradle.kts');
  assert.match(release, /Missing Android signing secrets/);
  assert.match(release, /secrets\.ANDROID_KEYSTORE_BASE64/);
  assert.match(release, /secrets\.ANDROID_SIGNING_CERT_SHA256/);
  assert.match(release, /python3 tool\/verify_android_apks\.py/);
  assert.match(release, /if: needs\.prepare\.outputs\.publish == 'true'/);
  assert.doesNotMatch(release, /create_self_test_android_key|flutify-self-test\.p12/);
  assert.match(gradle, /check\(releaseSigningReady\)/);
  assert.match(gradle, /signingConfig = signingConfigs\.getByName\("release"\)/);
});
