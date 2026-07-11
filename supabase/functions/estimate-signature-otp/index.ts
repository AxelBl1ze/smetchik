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

    const userId = await authenticatedUserId(request);
    const body = await readJsonBody(request);
    const action = firstString(body.action);
    if (action === 'send') return await sendCode(userId, body);
    if (action === 'verify') return await verifyCode(userId, body);
    return json({ error: 'Unknown action' }, 400);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    console.error(error);
    return json({ error: errorMessage(error) }, status);
  }
});

async function sendCode(userId: string, body: JsonRecord): Promise<Response> {
  const estimateId = firstString(body.estimateId, body.estimate_id);
  if (!estimateId) throw new HttpError('Не указана смета.', 400);

  const admin = adminClient();
  const estimate = await ownedPendingEstimate(admin, userId, estimateId);
  const phone = normalizeRussianPhone(firstString(estimate.client.phone));

  const latest = await admin
    .from('estimate_signature_otp_challenges')
    .select('created_at')
    .eq('user_id', userId)
    .eq('estimate_id', estimateId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (latest.error) throw latest.error;
  const lastSentAt = Date.parse(firstString(asRecord(latest.data).created_at) ?? '');
  if (Number.isFinite(lastSentAt) && Date.now() - lastSentAt < 60000) {
    throw new HttpError('Повторный код можно запросить через минуту.', 429);
  }

  const challengeId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const response = await telegramGateway('sendVerificationMessage', {
    phone_number: phone,
    code_length: 6,
    payload: challengeId,
    ttl: 600,
  });
  const result = asRecord(response.result);
  const telegramRequestId = firstString(
    result.request_id,
    result.requestId,
    result.id,
  );
  if (!telegramRequestId) {
    throw new Error('Telegram не вернул номер запроса.');
  }

  const inserted = await admin.from('estimate_signature_otp_challenges').insert({
    id: challengeId,
    user_id: userId,
    estimate_id: estimateId,
    client_phone: phone,
    telegram_request_id: telegramRequestId,
    expires_at: expiresAt,
  });
  if (inserted.error) throw inserted.error;

  return json({
    challengeId,
    maskedPhone: maskPhone(phone),
    expiresIn: 600,
  });
}

async function verifyCode(userId: string, body: JsonRecord): Promise<Response> {
  const challengeId = firstString(body.challengeId, body.challenge_id);
  const code = firstString(body.code)?.replaceAll(/\D/g, '') ?? '';
  if (!challengeId || !/^\d{6}$/.test(code)) {
    throw new HttpError('Введите шестизначный код.', 400);
  }

  const admin = adminClient();
  const challengeResponse = await admin
    .from('estimate_signature_otp_challenges')
    .select('*')
    .eq('id', challengeId)
    .eq('user_id', userId)
    .maybeSingle();
  if (challengeResponse.error) throw challengeResponse.error;
  const challenge = asRecord(challengeResponse.data);
  if (Object.keys(challenge).length === 0) {
    throw new HttpError('Запрос кода не найден.', 404);
  }
  if (firstString(challenge.used_at)) {
    throw new HttpError('Этот код уже использован.', 409);
  }
  const expiresAt = Date.parse(firstString(challenge.expires_at) ?? '');
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new HttpError('Срок действия кода истёк. Запросите новый.', 410);
  }

  const response = await telegramGateway('checkVerificationStatus', {
    request_id: firstString(challenge.telegram_request_id),
    code,
  });
  if (!isVerificationAccepted(response)) {
    throw new HttpError('Код Telegram не подошёл.', 401);
  }

  const verifiedAt = new Date().toISOString();
  const updated = await admin
    .from('estimate_signature_otp_challenges')
    .update({ verified_at: verifiedAt })
    .eq('id', challengeId)
    .is('used_at', null);
  if (updated.error) throw updated.error;

  return json({ challengeId, verifiedAt });
}

async function authenticatedUserId(request: Request): Promise<string> {
  const authorization = request.headers.get('Authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '').trim();
  if (!token) throw new HttpError('Требуется авторизация.', 401);
  const response = await adminClient().auth.getUser(token);
  if (response.error || !response.data.user) {
    throw new HttpError('Сессия не подтверждена.', 401);
  }
  return response.data.user.id;
}

async function ownedPendingEstimate(
  admin: ReturnType<typeof createClient>,
  userId: string,
  estimateId: string,
) {
  const response = await admin
    .from('estimates')
    .select('id,status,client_signed_at,clients(name,phone)')
    .eq('id', estimateId)
    .eq('user_id', userId)
    .single();
  if (response.error) throw response.error;
  const estimate = asRecord(response.data);
  if (firstString(estimate.client_signed_at) || estimate.status !== 'sent') {
    throw new HttpError('Эта смета уже принята или недоступна для подписи.', 409);
  }
  const client = asRecord(estimate.clients);
  if (!firstString(client.name) || !firstString(client.phone)) {
    throw new HttpError('Для подписи у клиента нужны ФИО и телефон.', 400);
  }
  return { client };
}

function adminClient() {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

async function telegramGateway(method: string, body: JsonRecord) {
  const response = await fetch(`https://gatewayapi.telegram.org/${method}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${requireEnv('TELEGRAM_GATEWAY_TOKEN')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.ok === false) {
    throw new Error(
      firstString(payload.description, payload.error) ??
          `Telegram Gateway ${method} failed`,
    );
  }
  return asRecord(payload);
}

function isVerificationAccepted(payload: JsonRecord): boolean {
  const result = asRecord(payload.result);
  if (result.code_valid === true || result.verified === true) return true;

  const status = firstString(
    asRecord(result.verification_status).status,
    result.status,
    result.verification_status,
  )?.toLowerCase();

  if (!status) return false;
  if (
    status.includes('invalid') ||
    status.includes('expired') ||
    status.includes('fail') ||
    status.includes('max_attempts')
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
    throw new HttpError('Введите российский номер клиента.', 400);
  }
  return `+${digits}`;
}

function maskPhone(phone: string): string {
  return `${phone.slice(0, 2)} ${phone.slice(2, 5)} ***-**-${phone.slice(-2)}`;
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
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
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
