import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type JsonRecord = Record<string, unknown>;

Deno.serve(async (request) => {
  try {
    if (request.method === 'OPTIONS') {
      return json({ ok: true });
    }

    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const body = await readJsonBody(request);
    const action = typeof body.action === 'string' ? body.action : '';

    if (action === 'send') {
      return await sendCode(body);
    }
    if (action === 'verify') {
      return await verifyCode(body);
    }

    return json({ error: 'Unknown action' }, 400);
  } catch (error) {
    console.error(error);
    return json({ error: errorMessage(error) }, 500);
  }
});

async function sendCode(body: JsonRecord): Promise<Response> {
  const phone = normalizeRussianPhone(firstString(body.phone));
  const token = requireEnv('TELEGRAM_GATEWAY_TOKEN');
  const payload = firstString(body.payload) ?? crypto.randomUUID();

  const response = await telegramGateway('sendVerificationMessage', token, {
    phone_number: phone,
    code_length: 6,
    payload,
    ttl: 600,
  });

  const result = asRecord(response.result);
  const requestId = firstString(result.request_id, result.requestId, result.id);
  if (!requestId) {
    throw new Error('Telegram did not return request_id');
  }

  return json({
    requestId,
    phone,
    expiresIn: 600,
  });
}

async function verifyCode(body: JsonRecord): Promise<Response> {
  const phone = normalizeRussianPhone(firstString(body.phone));
  const code = firstString(body.code)?.replaceAll(/\D/g, '') ?? '';
  const requestId = firstString(body.requestId, body.request_id);
  if (!requestId) {
    return json({ error: 'requestId is missing' }, 400);
  }
  if (!/^\d{4,8}$/.test(code)) {
    return json({ error: 'Code is invalid' }, 400);
  }

  const token = requireEnv('TELEGRAM_GATEWAY_TOKEN');
  const response = await telegramGateway('checkVerificationStatus', token, {
    request_id: requestId,
    code,
  });

  if (!isVerificationAccepted(response)) {
    return json({ error: 'Код Telegram не подошёл' }, 401);
  }

  const purpose = firstString(body.purpose) ?? 'login';
  const session = await createOrUpdateSupabaseSession(phone, {
    requireExisting: purpose === 'reset',
  });
  return json({ phone, session });
}

async function createOrUpdateSupabaseSession(
  phone: string,
  options: { requireExisting: boolean },
) {
  const supabaseUrl = requireEnv('SUPABASE_URL').replace(/\/$/, '');
  const serviceRoleKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = requireEnv('SUPABASE_ANON_KEY');
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const digits = phone.replaceAll(/\D/g, '');
  const email = `phone-${digits}@auth.smetchik.local`;

  const mapping = await admin
    .from('phone_auth_accounts')
    .select('user_id')
    .eq('phone', phone)
    .maybeSingle();

  const profileUserId = await findProfileUserIdByPhone(admin, phone);
  let userId = profileUserId ?? firstString(asRecord(mapping.data).user_id);

  if (!userId) {
    const existingUser = await findUserByEmail(admin, email);
    if (existingUser?.id) {
      userId = existingUser.id;
    }
  }

  if (!userId && options.requireExisting) {
    throw new Error('Аккаунт с таким телефоном не найден');
  }

  if (userId) {
    const existing = await admin.auth.admin.getUserById(userId);
    if (existing.error) throw existing.error;

    const userEmail = existing.data.user?.email;
    if (userEmail) {
      await linkPhoneToUser(admin, phone, userId);
      return await createMagicLinkSession(admin, supabaseUrl, anonKey, userEmail);
    }
  } else {
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: {
        full_name: 'Мастер',
        phone_login: phone,
        auth_provider: 'telegram_gateway',
      },
    });
    if (created.error) throw created.error;
    userId = created.data.user?.id;
    if (!userId) throw new Error('Supabase user was not created');
  }

  await linkPhoneToUser(admin, phone, userId);
  return await createMagicLinkSession(admin, supabaseUrl, anonKey, email);
}

async function createMagicLinkSession(
  admin: ReturnType<typeof createClient>,
  supabaseUrl: string,
  anonKey: string,
  email: string,
) {
  const link = await admin.auth.admin.generateLink({
    type: 'magiclink',
    email,
  });
  if (link.error) throw link.error;

  const properties = asRecord(link.data.properties);
  const tokenHash = firstString(properties.hashed_token);
  if (!tokenHash) {
    throw new Error('Supabase magic link token was not created');
  }

  const publicClient = createClient(supabaseUrl, anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const verified = await publicClient.auth.verifyOtp({
    token_hash: tokenHash,
    type: 'email',
  });
  if (verified.error) throw verified.error;

  const session = verified.data.session;
  if (!session) throw new Error('Supabase phone session was not created');
  return session;
}

async function linkPhoneToUser(
  admin: ReturnType<typeof createClient>,
  phone: string,
  userId: string,
) {
  const upsert = await admin.from('phone_auth_accounts').upsert({
    phone,
    user_id: userId,
  });
  if (upsert.error) throw upsert.error;
}

async function findProfileUserIdByPhone(
  admin: ReturnType<typeof createClient>,
  phone: string,
) {
  const targetDigits = phone.replaceAll(/\D/g, '');
  const profiles = await admin
    .from('profiles')
    .select('id,phone')
    .not('phone', 'is', null)
    .range(0, 9999);
  if (profiles.error) throw profiles.error;

  for (const profile of profiles.data ?? []) {
    try {
      const profilePhone = normalizeRussianPhone(firstString(profile.phone));
      if (profilePhone.replaceAll(/\D/g, '') === targetDigits) {
        return firstString(profile.id);
      }
    } catch {
      // Ignore malformed profile phones.
    }
  }

  return null;
}

async function findUserByEmail(
  admin: ReturnType<typeof createClient>,
  email: string,
) {
  for (let page = 1; page <= 5; page++) {
    const response = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (response.error) throw response.error;
    const found = response.data.users.find((user) => user.email === email);
    if (found) return found;
    if (response.data.users.length < 1000) break;
  }
  return null;
}

async function telegramGateway(
  method: string,
  token: string,
  body: JsonRecord,
): Promise<JsonRecord> {
  const response = await fetch(`https://gatewayapi.telegram.org/${method}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.ok === false) {
    const description = firstString(payload.description, payload.error);
    throw new Error(description ?? `Telegram Gateway ${method} failed`);
  }

  return isRecord(payload) ? payload : {};
}

function isVerificationAccepted(payload: JsonRecord): boolean {
  const result = asRecord(payload.result);
  if (result.code_valid === true || result.verified === true) return true;

  const statusRecord = asRecord(result.verification_status);
  const status = firstString(
    result.status,
    result.verification_status,
    statusRecord.status,
  )?.toLowerCase();

  if (!status) return false;
  if (
    status.includes('invalid') ||
    status.includes('expired') ||
    status.includes('fail')
  ) {
    return false;
  }

  return status.includes('valid') || status.includes('verified');
}

function normalizeRussianPhone(raw: string | null): string {
  let digits = (raw ?? '').replaceAll(/\D/g, '');
  if (digits.length === 10) digits = `7${digits}`;
  if (digits.startsWith('8')) digits = `7${digits.slice(1)}`;
  if (digits.length !== 11 || !digits.startsWith('7')) {
    throw new Error('Введите российский номер телефона');
  }
  return `+${digits}`;
}

async function readJsonBody(request: Request): Promise<JsonRecord> {
  try {
    const payload = await request.json();
    return isRecord(payload) ? payload : {};
  } catch {
    return {};
  }
}

function json(payload: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function firstString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function asRecord(value: unknown): JsonRecord {
  return isRecord(value) ? value : {};
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
