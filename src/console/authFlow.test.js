import test from 'node:test';
import assert from 'node:assert/strict';
import { consoleRedirect, isRecoveryLink, recoveryRedirect, validateEmail, validatePassword } from './authFlow.js';

test('validates registration email and matching password', () => {
  assert.equal(validateEmail('person@example.com'), true);
  assert.equal(validateEmail('not-an-email'), false);
  assert.match(validatePassword('short', 'short'), /at least 8/);
  assert.equal(validatePassword('long-enough', 'different'), 'Passwords do not match.');
  assert.equal(validatePassword('long-enough', 'long-enough'), '');
});

test('uses the current origin for confirmation and recovery redirects', () => {
  assert.equal(consoleRedirect('https://fiducaro.com'), 'https://fiducaro.com/console/overview');
  assert.equal(recoveryRedirect('http://localhost:5173'), 'http://localhost:5173/console/reset-password');
});

test('recognizes recovery redirects from query or URL fragment', () => {
  assert.equal(isRecoveryLink({ search: '?type=recovery', hash: '' }), true);
  assert.equal(isRecoveryLink({ search: '', hash: '#access_token=token&type=recovery' }), true);
  assert.equal(isRecoveryLink({ search: '', hash: '#type=signup' }), false);
});
