import assert from 'node:assert/strict';
import { test } from 'node:test';
import { activeSubscriptionPlan } from './subscription_access.ts';

const now = Date.parse('2026-10-22T10:00:00Z');
test('paid access requires an active status and an unexpired term', () => {
  for (const plan of ['pro', 'team']) {
    const base = { subscription_plan: plan, subscription_status: 'active' };
    assert.equal(activeSubscriptionPlan(base, now), plan);
    assert.equal(activeSubscriptionPlan({ ...base, subscription_renews_at: '2026-10-22T10:00:00Z' }, now), 'basic');
    assert.equal(activeSubscriptionPlan({ ...base, subscription_renews_at: '2026-10-21T10:00:00Z' }, now), 'basic');
    assert.equal(activeSubscriptionPlan({ ...base, subscription_renews_at: '2026-10-23T10:00:00Z' }, now), plan);
    assert.equal(activeSubscriptionPlan({ ...base, subscription_status: 'canceled' }, now), 'basic');
    assert.equal(activeSubscriptionPlan({ ...base, subscription_renews_at: 'invalid' }, now), 'basic');
  }
  assert.equal(activeSubscriptionPlan(undefined, now), 'basic');
});
