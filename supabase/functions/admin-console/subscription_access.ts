type Subscription = {
  subscription_plan?: string;
  subscription_status?: string;
  subscription_renews_at?: string | null;
};

export function activeSubscriptionPlan(profile: Subscription | undefined, now = Date.now()): string {
  if (!profile || !['pro', 'team'].includes(profile.subscription_plan ?? '')) return 'basic';
  if (!['active', 'trialing'].includes(profile.subscription_status ?? '')) return 'basic';
  const until = profile.subscription_renews_at == null
    ? Number.POSITIVE_INFINITY : Date.parse(profile.subscription_renews_at);
  return until > now ? profile.subscription_plan! : 'basic';
}
