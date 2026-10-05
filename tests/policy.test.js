import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateSandboxPayment, initialData } from '../src/console/model.js';

const agent = initialData.agents[0];
const request = overrides => ({ agent, amount: 145, vendor: 'AWS', asset: 'USDC', spentToday: 0, ...overrides });

test('executes an allowed payment under the approval threshold', () => {
  assert.equal(evaluateSandboxPayment(request()).outcome, 'approved');
});

test('holds an otherwise valid payment above the approval threshold', () => {
  assert.equal(evaluateSandboxPayment(request({ amount: 880 })).outcome, 'review');
});

test('blocks a suspended agent and unapproved counterparties or assets', () => {
  assert.equal(evaluateSandboxPayment(request({ agent: { ...agent, status: 'Suspended' } })).reason, 'Agent account is suspended');
  assert.equal(evaluateSandboxPayment(request({ vendor: 'Unknown' })).reason, 'Counterparty is not approved');
  assert.equal(evaluateSandboxPayment(request({ asset: 'BTC' })).reason, 'Asset is not allowed');
});

test('blocks requests that cross transaction, daily, or balance limits', () => {
  assert.equal(evaluateSandboxPayment(request({ amount: 1100 })).reason, 'Transaction limit exceeded');
  assert.equal(evaluateSandboxPayment(request({ amount: 145, spentToday: 4900 })).reason, 'Daily limit exceeded');
  assert.equal(evaluateSandboxPayment(request({ amount: 19000 })).reason, 'Insufficient agent balance');
});
