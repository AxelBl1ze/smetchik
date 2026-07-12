import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const approvalStatementVersion = 'client-approval-link-v1';
const approvalStatement =
  'Нажимая «Принять смету», я подтверждаю, что ознакомился(ась) с указанной версией сметы, согласен(на) с её условиями и принимаю документ. Я согласен(на) на фиксацию подписи, даты, времени, технических сведений о подписании и версии документа в сервисе «Сметчик».';

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

    const body = await readJsonBody(request);
    const action = firstString(body.action);
    if (action === 'create') {
      return await createApprovalLink(await authenticatedUserId(request), body);
    }
    if (action === 'get') return await getApprovalLink(body);
    if (action === 'sign') return await signApprovalLink(request, body);
    return json({ error: 'Unknown action' }, 400);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    console.error(error);
    return json(
      { error: error instanceof HttpError ? error.message : 'Не удалось обработать запрос.' },
      status,
    );
  }
});

async function createApprovalLink(userId: string, body: JsonRecord) {
  const estimateId = firstString(body.estimateId, body.estimate_id);
  if (!estimateId) throw new HttpError('Не указана смета.', 400);

  const admin = adminClient();
  const estimate = await loadOwnedPendingEstimate(admin, userId, estimateId);
  const client = asRecord(estimate.clients);
  if (!firstString(client.name) || !firstString(client.phone)) {
    throw new HttpError('Для подписи укажите ФИО и телефон клиента.', 400);
  }

  await admin
    .from('estimate_signature_links')
    .update({ revoked_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('estimate_id', estimateId)
    .is('signed_at', null)
    .is('revoked_at', null);

  const token = createToken();
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const inserted = await admin.from('estimate_signature_links').insert({
    id: crypto.randomUUID(),
    user_id: userId,
    estimate_id: estimateId,
    token_hash: await sha256(token),
    expires_at: expiresAt,
  });
  if (inserted.error) throw inserted.error;

  return json({ token, expiresAt });
}

async function getApprovalLink(body: JsonRecord) {
  const context = await loadPublicApproval(firstString(body.token));
  if (context.link.signed_at) {
    return json({ state: 'signed', signedAt: context.link.signed_at });
  }

  await context.admin
    .from('estimate_signature_links')
    .update({ viewed_at: context.link.viewed_at ?? new Date().toISOString() })
    .eq('id', context.link.id)
    .is('signed_at', null);

  return json({
    state: 'ready',
    expiresAt: context.link.expires_at,
    statement: approvalStatement,
    statementVersion: approvalStatementVersion,
    document: publicDocument(context),
  });
}

async function signApprovalLink(request: Request, body: JsonRecord) {
  const context = await loadPublicApproval(firstString(body.token));
  if (context.link.signed_at) {
    throw new HttpError('Эта смета уже принята.', 409);
  }

  const clientName = normalizeName(firstString(body.clientName, body.client_name));
  const clientPhone = normalizeRussianPhone(firstString(body.clientPhone, body.client_phone));
  const signature = decodePng(firstString(body.signature));
  const signedAt = new Date().toISOString();
  const document = documentSnapshot(context);
  const documentHash = await sha256(JSON.stringify(document));
  const snapshot = {
    schema_version: 'signed-estimate-v2',
    statement_version: approvalStatementVersion,
    statement: approvalStatement,
    signed_at: signedAt,
    signature: {
      method: 'approval_link',
      link_id: context.link.id,
      link_created_at: context.link.created_at,
      link_viewed_at: context.link.viewed_at,
      signer_ip: signerIp(request),
      signer_user_agent: truncate(request.headers.get('user-agent'), 512),
      document_hash: documentHash,
    },
    document,
    master: masterSnapshot(context.profile),
  };
  const signaturePath =
    `${context.link.user_id}/${context.estimate.id}/` +
    `v${context.estimate.document_version}-${Date.now()}-link-signature.png`;
  const upload = await context.admin.storage
    .from('client-signatures')
    .upload(signaturePath, signature, {
      contentType: 'image/png',
      upsert: false,
    });
  if (upload.error) throw upload.error;

  const finalized = await context.admin.rpc('finalize_estimate_link_signature', {
    p_link_id: context.link.id,
    p_signature_path: signaturePath,
    p_client_name: clientName,
    p_client_phone: clientPhone,
    p_signed_at: signedAt,
    p_statement_version: approvalStatementVersion,
    p_statement: approvalStatement,
    p_snapshot: snapshot,
    p_document_hash: documentHash,
    p_signer_ip: signerIp(request),
    p_signer_user_agent: truncate(request.headers.get('user-agent'), 512),
  });
  if (finalized.error) throw new HttpError('Не удалось зафиксировать подпись. Обновите страницу.', 409);

  return json({ state: 'signed', signedAt, documentHash });
}

async function loadPublicApproval(token: string | null) {
  if (!token || token.length < 32) {
    throw new HttpError('Ссылка недействительна.', 404);
  }
  const admin = adminClient();
  const tokenHash = await sha256(token);
  const linkResult = await admin
    .from('estimate_signature_links')
    .select('*')
    .eq('token_hash', tokenHash)
    .maybeSingle();
  if (linkResult.error) throw linkResult.error;
  const link = asRecord(linkResult.data);
  if (!Object.keys(link).length || link.revoked_at) {
    throw new HttpError('Ссылка недействительна.', 404);
  }
  if (!link.signed_at && Date.parse(firstString(link.expires_at) ?? '') <= Date.now()) {
    throw new HttpError('Срок действия ссылки закончился. Попросите мастера создать новую.', 410);
  }

  const estimateResult = await admin
    .from('estimates')
    .select('id,user_id,client_id,object_title,estimate_date,duration_days,status,total_amount,document_version,client_signed_at,clients(name,phone,object_address)')
    .eq('id', firstString(link.estimate_id))
    .eq('user_id', firstString(link.user_id))
    .single();
  if (estimateResult.error) throw estimateResult.error;
  const estimate = asRecord(estimateResult.data);
  if (!estimate.client_signed_at && firstString(estimate.status) !== 'sent') {
    throw new HttpError('Эта смета больше недоступна для подписания.', 409);
  }

  const linesResult = await admin
    .from('estimate_lines')
    .select('title,unit,quantity,unit_price,line_total,sort_order')
    .eq('estimate_id', firstString(estimate.id))
    .eq('user_id', firstString(link.user_id))
    .order('sort_order');
  if (linesResult.error) throw linesResult.error;

  const profileResult = await admin
    .from('profiles')
    .select('full_name,phone,specialization,logo_path')
    .eq('id', firstString(link.user_id))
    .maybeSingle();
  if (profileResult.error) throw profileResult.error;

  return {
    admin,
    link,
    estimate,
    lines: Array.isArray(linesResult.data) ? linesResult.data.map(asRecord) : [],
    profile: asRecord(profileResult.data),
  };
}

async function loadOwnedPendingEstimate(
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
  if (
    firstString(estimate.status) !== 'sent' ||
    estimate.client_signed_at !== null
  ) {
    throw new HttpError('Смета уже принята или недоступна для подписи.', 409);
  }
  return estimate;
}

function publicDocument(context: Awaited<ReturnType<typeof loadPublicApproval>>) {
  const document = documentSnapshot(context);
  const client = asRecord(document.client);
  return {
    ...document,
    client: {
      ...client,
      phone_masked: maskPhone(firstString(client.phone)),
    },
    master: {
      full_name: firstString(context.profile.full_name) ?? 'Мастер',
      phone: firstString(context.profile.phone),
      specialization: firstString(context.profile.specialization),
      logo_url: publicStorageUrl(context.admin, 'logos', firstString(context.profile.logo_path)),
    },
  };
}

function documentSnapshot(context: Awaited<ReturnType<typeof loadPublicApproval>>) {
  const client = asRecord(context.estimate.clients);
  return {
    id: context.estimate.id,
    version: Number(context.estimate.document_version ?? 1),
    object_title: firstString(context.estimate.object_title) ?? '',
    estimate_date: firstString(context.estimate.estimate_date),
    duration_days: context.estimate.duration_days ?? null,
    total_amount: Number(context.estimate.total_amount ?? 0),
    client: {
      name: firstString(client.name),
      phone: firstString(client.phone),
      object_address: firstString(client.object_address),
    },
    lines: context.lines.map((line) => ({
      title: firstString(line.title) ?? '',
      unit: firstString(line.unit) ?? 'шт',
      quantity: Number(line.quantity ?? 0),
      unit_price: Number(line.unit_price ?? 0),
      line_total: Number(line.line_total ?? 0),
      sort_order: Number(line.sort_order ?? 0),
    })),
  };
}

function masterSnapshot(profile: JsonRecord) {
  return {
    name: firstString(profile.full_name),
    phone: firstString(profile.phone),
    specialization: firstString(profile.specialization),
    signature_path: null,
  };
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

function adminClient() {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

function publicStorageUrl(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  path: string | null,
) {
  if (!path) return null;
  return admin.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}

function createToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function decodePng(value: string | null) {
  if (!value) throw new HttpError('Добавьте подпись.', 400);
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw new HttpError('Подпись передана в неверном формате.', 400);
  }
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  const pngMagic = [137, 80, 78, 71, 13, 10, 26, 10];
  if (
    bytes.length < 128 ||
    bytes.length > 1024 * 1024 ||
    !pngMagic.every((value, index) => bytes[index] === value)
  ) {
    throw new HttpError('Подпись должна быть PNG-изображением до 1 МБ.', 400);
  }
  return bytes;
}

function normalizeName(value: string | null) {
  const normalized = (value ?? '').trim().replaceAll(/\s+/g, ' ');
  if (normalized.length < 2 || normalized.length > 160) {
    throw new HttpError('Укажите ФИО клиента.', 400);
  }
  return normalized;
}

function normalizeRussianPhone(value: string | null) {
  let digits = (value ?? '').replaceAll(/\D/g, '');
  if (digits.length === 10) digits = `7${digits}`;
  if (digits.startsWith('8')) digits = `7${digits.slice(1)}`;
  if (digits.length !== 11 || !digits.startsWith('7')) {
    throw new HttpError('Укажите российский номер клиента.', 400);
  }
  return `+${digits}`;
}

function maskPhone(value: string | null) {
  const digits = (value ?? '').replaceAll(/\D/g, '');
  if (digits.length !== 11) return 'номер клиента';
  return `+${digits[0]} ${digits.slice(1, 4)} ***-**-${digits.slice(-2)}`;
}

function signerIp(request: Request) {
  const cloudflareIp = request.headers.get('cf-connecting-ip');
  if (cloudflareIp) return truncate(cloudflareIp, 64);
  return truncate(request.headers.get('x-forwarded-for')?.split(',')[0] ?? null, 64);
}

function truncate(value: string | null, length: number) {
  if (!value) return null;
  return value.slice(0, length);
}

function requireEnv(name: string) {
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
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

async function readJsonBody(request: Request): Promise<JsonRecord> {
  try {
    return asRecord(await request.json());
  } catch {
    return {};
  }
}

function json(payload: JsonRecord, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
