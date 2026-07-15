import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type JsonRecord = Record<string, unknown>;

class HttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

Deno.serve(async (request) => {
  try {
    if (request.method === 'OPTIONS') return json({ ok: true });
    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const authorization = request.headers.get('Authorization') ?? '';
    const user = await authenticatedUser(authorization);
    const body = await readJsonBody(request);
    const code = firstString(body.code);
    if (!code) throw new HttpError('Введите промокод.', 400);

    const client = createClient(
      requireEnv('SUPABASE_URL'),
      requireEnv('SUPABASE_ANON_KEY'),
      {
        auth: { autoRefreshToken: false, persistSession: false },
        global: { headers: { Authorization: authorization } },
      },
    );
    const result = await client.rpc('redeem_promo', { p_code: code });
    if (result.error) {
      throw new HttpError(normalizeDatabaseError(result.error.message), 400);
    }

    const row = Array.isArray(result.data) ? result.data[0] : result.data;
    const data = asRecord(row);
    return json({
      plan: firstString(data.subscription_plan) ?? 'pro',
      renewsAt: firstString(data.subscription_renews_at),
      title: firstString(data.promo_title),
      userId: user.id,
    });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    console.error(error);
    return json(
      {
        error:
          error instanceof HttpError
            ? error.message
            : 'Не удалось применить промокод. Повторите попытку.',
      },
      status,
    );
  }
});

async function authenticatedUser(authorization: string) {
  const token = authorization.replace(/^Bearer\s+/i, '').trim();
  if (!token) throw new HttpError('Требуется авторизация.', 401);
  const result = await adminClient().auth.getUser(token);
  if (result.error || !result.data.user) {
    throw new HttpError('Сессия не подтверждена. Войдите снова.', 401);
  }
  return result.data.user;
}

function adminClient() {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

async function readJsonBody(request: Request): Promise<JsonRecord> {
  try {
    const value = await request.json();
    return asRecord(value);
  } catch {
    return {};
  }
}

function asRecord(value: unknown): JsonRecord {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as JsonRecord;
  }
  return {};
}

function firstString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized || null;
}

function normalizeDatabaseError(message: string) {
  return message
    .replace(/^ERROR:\s*/i, '')
    .replace(/\n.*$/s, '')
    .trim();
}

function json(payload: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}
