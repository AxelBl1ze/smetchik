import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type JsonRecord = Record<string, unknown>;
type AdminRole = 'owner' | 'support' | 'auditor';

type AdminContext = {
  admin: ReturnType<typeof createClient>;
  user: { id: string; email: string | null; role: AdminRole };
};

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

    const context = await authenticatedAdmin(request);
    const body = await readJsonBody(request);
    const action = firstString(body.action);

    switch (action) {
      case 'bootstrap':
      case 'dashboard':
        return json(await dashboard(context));
      case 'users':
        return json(await users(context, body));
      case 'promos':
        return json(await promos(context));
      case 'create_promo':
        return json(await createPromo(context, body));
      case 'set_promo_active':
        return json(await setPromoActive(context, body));
      case 'grant_subscription':
        return json(await grantSubscription(context, body));
      case 'revoke_subscription':
        return json(await revokeSubscription(context, body));
      case 'set_user_block':
        return json(await setUserBlock(context, body));
      case 'set_admin_role':
        return json(await setAdminRole(context, body));
      case 'signed_estimates':
        return json(await signedEstimates(context, body));
      case 'evidence':
        return json(await evidence(context, body));
      case 'audit':
        return json(await audit(context, body));
      default:
        throw new HttpError('Неизвестное действие админ-панели.', 400);
    }
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    console.error(error);
    return json(
      {
        error:
          error instanceof HttpError
            ? error.message
            : 'Админ-панель временно недоступна. Повторите попытку.',
      },
      status,
    );
  }
});

async function dashboard(context: AdminContext): Promise<JsonRecord> {
  const [usersCount, estimatesCount, signedCount, activePromos, recentEvents] =
      await Promise.all([
        countRows(context.admin, 'profiles'),
        countRows(context.admin, 'estimates'),
        countRows(context.admin, 'estimates', (query: any) =>
          query.not('client_signed_at', 'is', null),
        ),
        countRows(context.admin, 'promo_codes', (query: any) =>
          query.eq('is_active', true),
        ),
        context.admin
          .from('admin_audit_events')
          .select('id,action,entity_type,entity_id,metadata,created_at')
          .order('created_at', { ascending: false })
          .limit(8),
      ]);

  if (recentEvents.error) throw recentEvents.error;
  const proResult = await context.admin
    .from('profiles')
    .select('subscription_status,subscription_renews_at')
    .eq('subscription_plan', 'pro')
    .limit(5000);
  if (proResult.error) throw proResult.error;

  const now = Date.now();
  const activePro = (proResult.data ?? []).filter((profile) => {
    const status = profile.subscription_status;
    const renewsAt = profile.subscription_renews_at
      ? Date.parse(profile.subscription_renews_at)
      : Number.POSITIVE_INFINITY;
    return (status === 'active' || status === 'trialing') && renewsAt > now;
  }).length;

  return {
    operator: {
      id: context.user.id,
      email: context.user.email,
      role: context.user.role,
    },
    metrics: {
      users: usersCount,
      estimates: estimatesCount,
      signedEstimates: signedCount,
      activePro,
      activePromos,
    },
    events: recentEvents.data ?? [],
  };
}

async function users(context: AdminContext, body: JsonRecord): Promise<JsonRecord> {
  requireSupport(context);
  const query = (firstString(body.query) ?? '').toLowerCase();
  const response = await context.admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (response.error) throw response.error;

  const authUsers = response.data.users;
  const ids = authUsers.map((user) => user.id);
  const profiles = ids.length
    ? await context.admin
      .from('profiles')
      .select(
        'id,full_name,phone,specialization,subscription_plan,subscription_status,subscription_source,subscription_renews_at,created_at',
      )
      .in('id', ids)
    : { data: [], error: null };
  if (profiles.error) throw profiles.error;
  const byId = new Map((profiles.data ?? []).map((profile) => [profile.id, profile]));
  const adminRoles = ids.length
    ? await context.admin
      .from('app_admins')
      .select('user_id,role,enabled')
      .in('user_id', ids)
      .eq('enabled', true)
    : { data: [], error: null };
  if (adminRoles.error) throw adminRoles.error;
  const roleById = new Map((adminRoles.data ?? []).map((admin) => [admin.user_id, admin.role]));

  const rows = authUsers
    .map((user) => {
      const profile = byId.get(user.id) ?? {};
      return {
        id: user.id,
        email: user.email ?? null,
        createdAt: user.created_at,
        fullName: profile.full_name ?? '',
        phone: profile.phone ?? null,
        specialization: profile.specialization ?? null,
        subscriptionPlan: profile.subscription_plan ?? 'basic',
        subscriptionStatus: profile.subscription_status ?? 'active',
        subscriptionSource: profile.subscription_source ?? 'manual',
        subscriptionRenewsAt: profile.subscription_renews_at ?? null,
        bannedUntil: user.banned_until ?? null,
        adminRole: roleById.get(user.id) ?? null,
      };
    })
    .filter((row) => {
      if (!query) return true;
      return [row.email, row.fullName, row.phone, row.specialization]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(query);
    })
    .slice(0, 80);

  return { users: rows, limited: authUsers.length >= 1000 };
}

async function promos(context: AdminContext): Promise<JsonRecord> {
  requireSupport(context);
  const response = await context.admin
    .from('promo_codes')
    .select(
      'id,code_hint,code_value,title,plan,grant_days,max_redemptions,redemption_count,starts_at,expires_at,is_active,disabled_at,created_at',
    )
    .order('created_at', { ascending: false })
    .limit(100);
  if (response.error) throw response.error;
  return { promos: response.data ?? [] };
}

async function createPromo(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  requireSupport(context);
  const title = firstString(body.title) ?? 'Промокод Профи';
  const grantDays = boundedInt(body.grantDays, 30, 1, 1095);
  const maxRedemptions = boundedInt(body.maxRedemptions, 1, 1, 100000);
  const startsAt = optionalDate(body.startsAt);
  const expiresAt = optionalDate(body.expiresAt);
  if (startsAt && expiresAt && Date.parse(expiresAt) <= Date.parse(startsAt)) {
    throw new HttpError('Дата завершения должна быть позже даты начала.', 400);
  }

  const rawCode = normalizeCode(firstString(body.code) ?? generatePromoCode());
  if (rawCode.length < 4) throw new HttpError('Промокод слишком короткий.', 400);
  const codeHash = await sha256(rawCode);
  const response = await context.admin.from('promo_codes').insert({
    code_hash: codeHash,
    code_hint: maskPromo(rawCode),
    code_value: rawCode,
    title: title.slice(0, 120),
    plan: 'pro',
    grant_days: grantDays,
    max_redemptions: maxRedemptions,
    starts_at: startsAt,
    expires_at: expiresAt,
    created_by: context.user.id,
  }).select('id,code_hint,code_value,title,grant_days,max_redemptions,starts_at,expires_at,is_active').single();
  if (response.error) {
    if (response.error.code === '23505') {
      throw new HttpError('Такой промокод уже существует. Выберите другой.', 409);
    }
    throw response.error;
  }

  await logEvent(context, 'promo_created', 'promo_code', response.data.id, {
    title: response.data.title,
    grantDays,
    maxRedemptions,
  });
  return { promo: response.data, code: rawCode };
}

async function setPromoActive(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  requireSupport(context);
  const id = requiredUuid(body.id, 'промокод');
  const active = body.active === true;
  const response = await context.admin
    .from('promo_codes')
    .update({
      is_active: active,
      disabled_at: active ? null : new Date().toISOString(),
    })
    .eq('id', id)
    .select('id,is_active,disabled_at')
    .single();
  if (response.error) throw response.error;
  await logEvent(
    context,
    active ? 'promo_enabled' : 'promo_disabled',
    'promo_code',
    id,
  );
  return { promo: response.data };
}

async function grantSubscription(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  requireSupport(context);
  const userId = requiredUuid(body.userId, 'пользователя');
  const days = boundedInt(body.days, 30, 1, 1095);
  const profile = await context.admin
    .from('profiles')
    .select('id,subscription_renews_at')
    .eq('id', userId)
    .maybeSingle();
  if (profile.error) throw profile.error;
  if (!profile.data) throw new HttpError('Профиль пользователя не найден.', 404);

  const current = profile.data.subscription_renews_at
    ? Date.parse(profile.data.subscription_renews_at)
    : 0;
  const base = Math.max(current, Date.now());
  const renewsAt = new Date(base + days * 24 * 60 * 60 * 1000).toISOString();
  const update = await context.admin
    .from('profiles')
    .update({
      subscription_plan: 'pro',
      subscription_status: 'active',
      subscription_source: 'admin',
      subscription_renews_at: renewsAt,
    })
    .eq('id', userId);
  if (update.error) throw update.error;
  await logEvent(context, 'subscription_granted', 'profile', userId, {
    days,
    renewsAt,
  });
  return { userId, plan: 'pro', renewsAt };
}

async function revokeSubscription(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  requireSupport(context);
  const userId = requiredUuid(body.userId, 'пользователя');
  const update = await context.admin
    .from('profiles')
    .update({
      subscription_plan: 'basic',
      subscription_status: 'active',
      subscription_source: 'admin',
      subscription_renews_at: null,
    })
    .eq('id', userId)
    .select('id')
    .maybeSingle();
  if (update.error) throw update.error;
  if (!update.data) throw new HttpError('Профиль пользователя не найден.', 404);

  await logEvent(context, 'subscription_revoked', 'profile', userId, {
    plan: 'basic',
  });
  return { userId, plan: 'basic', renewsAt: null };
}

async function setUserBlock(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  requireSupport(context);
  const userId = requiredUuid(body.userId, 'пользователя');
  const blocked = body.blocked === true;
  if (userId === context.user.id) {
    throw new HttpError('Нельзя заблокировать собственный аккаунт.', 400);
  }

  const targetAdmin = await context.admin
    .from('app_admins')
    .select('role')
    .eq('user_id', userId)
    .eq('enabled', true)
    .maybeSingle();
  if (targetAdmin.error) throw targetAdmin.error;
  if (targetAdmin.data && context.user.role !== 'owner') {
    throw new HttpError('Блокировать администратора может только владелец.', 403);
  }

  const update = await context.admin.auth.admin.updateUserById(userId, {
    ban_duration: blocked ? '876000h' : 'none',
  });
  if (update.error) throw update.error;
  await logEvent(context, blocked ? 'user_blocked' : 'user_unblocked', 'profile', userId);
  return { userId, blocked };
}

async function setAdminRole(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  requireOwner(context);
  const userId = requiredUuid(body.userId, 'пользователя');
  const requested = firstString(body.role);
  const role = isAdminRole(requested) ? requested : null;
  if (requested && !role) throw new HttpError('Неизвестная роль администратора.', 400);
  if (userId === context.user.id && role !== 'owner') {
    throw new HttpError('Владелец не может понизить или отозвать собственный доступ.', 400);
  }

  const authUser = await context.admin.auth.admin.getUserById(userId);
  if (authUser.error || !authUser.data.user) {
    throw new HttpError('Пользователь не найден.', 404);
  }
  const email = authUser.data.user.email?.toLowerCase();
  if (!email) throw new HttpError('У пользователя нет email для админ-доступа.', 400);

  if (role == null) {
    const result = await context.admin
      .from('app_admins')
      .delete()
      .eq('user_id', userId);
    if (result.error) throw result.error;
  } else {
    const result = await context.admin.from('app_admins').upsert(
      {
        user_id: userId,
        email,
        role,
        enabled: true,
      },
      { onConflict: 'user_id' },
    );
    if (result.error) throw result.error;
  }
  await logEvent(context, 'admin_role_changed', 'profile', userId, { role });
  return { userId, role };
}

async function signedEstimates(
  context: AdminContext,
  body: JsonRecord,
): Promise<JsonRecord> {
  const search = firstString(body.query)?.toLowerCase() ?? '';
  const response = await context.admin
    .from('estimates')
    .select(
      'id,user_id,object_title,estimate_date,total_amount,status,document_version,client_signed_at,client_signed_name,client_signed_phone,client_signature_method,signed_document_hash,signed_pdf_storage_path,clients(name,phone)',
    )
    .not('client_signed_at', 'is', null)
    .order('client_signed_at', { ascending: false })
    .limit(100);
  if (response.error) throw response.error;
  const rows = response.data ?? [];
  const masterIds = [...new Set(rows.map((row) => row.user_id))];
  const profiles = masterIds.length
    ? await context.admin.from('profiles').select('id,full_name').in('id', masterIds)
    : { data: [], error: null };
  if (profiles.error) throw profiles.error;
  const names = new Map((profiles.data ?? []).map((profile) => [profile.id, profile.full_name]));

  const estimates = rows
    .map((row) => ({
      ...row,
      masterName: names.get(row.user_id) ?? 'Мастер',
    }))
    .filter((row) => {
      if (!search) return true;
      const client = asRecord(row.clients);
      return [
        row.object_title,
        row.client_signed_name,
        row.client_signed_phone,
        row.masterName,
        firstString(client.name),
      ].filter(Boolean).join(' ').toLowerCase().includes(search);
    });

  return { estimates };
}

async function evidence(context: AdminContext, body: JsonRecord): Promise<JsonRecord> {
  const estimateId = requiredUuid(body.estimateId, 'смету');
  const estimate = await context.admin
    .from('estimates')
    .select('*')
    .eq('id', estimateId)
    .not('client_signed_at', 'is', null)
    .maybeSingle();
  if (estimate.error) throw estimate.error;
  if (!estimate.data) throw new HttpError('Подписанная смета не найдена.', 404);

  const [profile, client, lines, links] = await Promise.all([
    context.admin
      .from('profiles')
      .select('id,full_name,phone,specialization')
      .eq('id', estimate.data.user_id)
      .maybeSingle(),
    estimate.data.client_id
      ? context.admin.from('clients').select('id,name,phone,object_address').eq('id', estimate.data.client_id).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    context.admin
      .from('estimate_lines')
      .select('title,unit,quantity,unit_price,line_total,sort_order')
      .eq('estimate_id', estimateId)
      .order('sort_order'),
    context.admin
      .from('estimate_signature_links')
      .select('id,created_at,viewed_at,signed_at,expires_at,revoked_at,signer_ip,signer_user_agent,document_hash')
      .eq('estimate_id', estimateId)
      .order('created_at', { ascending: false }),
  ]);
  if (profile.error) throw profile.error;
  if (client.error) throw client.error;
  if (lines.error) throw lines.error;
  if (links.error) throw links.error;

  const files = await signedEvidenceFiles(context.admin, estimate.data);
  await logEvent(context, 'signed_estimate_evidence_exported', 'estimate', estimateId, {
    documentVersion: estimate.data.document_version,
  });

  return {
    generatedAt: new Date().toISOString(),
    estimate: estimate.data,
    master: profile.data,
    client: client.data,
    lines: lines.data ?? [],
    signatureLinks: links.data ?? [],
    files,
  };
}

async function audit(context: AdminContext, body: JsonRecord): Promise<JsonRecord> {
  const query = (firstString(body.query) ?? '').toLowerCase();
  const category = firstString(body.category) ?? 'all';
  const response = await context.admin
    .from('admin_audit_events')
    .select('id,actor_user_id,action,entity_type,entity_id,metadata,created_at')
    .order('created_at', { ascending: false })
    .limit(250);
  if (response.error) throw response.error;
  const events = (response.data ?? []).filter((event) => {
    const action = String(event.action ?? '');
    if (category !== 'all' && auditCategory(action) !== category) return false;
    if (!query) return true;
    return [action, event.entity_type, event.entity_id, JSON.stringify(event.metadata ?? {})]
      .filter(Boolean)
      .join(' ')
      .toLowerCase()
      .includes(query);
  });
  return { events };
}

async function signedEvidenceFiles(admin: ReturnType<typeof createClient>, estimate: JsonRecord) {
  const files: JsonRecord = {};
  const signedPdf = firstString(estimate.signed_pdf_storage_path);
  const signature = firstString(estimate.client_signature_path);
  if (signedPdf) {
    const response = await admin.storage
      .from('signed-estimate-pdfs')
      .createSignedUrl(signedPdf, 15 * 60);
    if (!response.error) files.signedPdfUrl = response.data.signedUrl;
  }
  if (signature) {
    const response = await admin.storage
      .from('client-signatures')
      .createSignedUrl(signature, 15 * 60);
    if (!response.error) files.clientSignatureUrl = response.data.signedUrl;
  }
  return files;
}

async function authenticatedAdmin(request: Request): Promise<AdminContext> {
  const token = (request.headers.get('Authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
    .trim();
  if (!token) throw new HttpError('Требуется вход администратора.', 401);

  const admin = adminClient();
  const userResult = await admin.auth.getUser(token);
  const user = userResult.data.user;
  if (userResult.error || !user) {
    throw new HttpError('Сессия не подтверждена. Войдите снова.', 401);
  }
  const role = await admin
    .from('app_admins')
    .select('user_id,role')
    .eq('user_id', user.id)
    .eq('enabled', true)
    .maybeSingle();
  if (role.error) throw role.error;
  if (!role.data) throw new HttpError('У этого аккаунта нет доступа к админ-панели.', 403);
  return {
    admin,
    user: {
      id: user.id,
      email: user.email ?? null,
      role: isAdminRole(role.data.role) ? role.data.role : 'owner',
    },
  };
}

function isAdminRole(value: unknown): value is AdminRole {
  return value === 'owner' || value === 'support' || value === 'auditor';
}

function requireOwner(context: AdminContext) {
  if (context.user.role !== 'owner') {
    throw new HttpError('Это действие доступно только владельцу.', 403);
  }
}

function requireSupport(context: AdminContext) {
  if (context.user.role === 'auditor') {
    throw new HttpError('У аудитора доступ только к документам и журналу.', 403);
  }
}

function auditCategory(action: string) {
  if (action.includes('promo')) return 'promos';
  if (action.includes('evidence') || action.includes('signed')) return 'documents';
  if (action.includes('admin_role')) return 'admins';
  if (action.includes('block') || action.includes('subscription')) return 'access';
  return 'other';
}

async function countRows(
  admin: ReturnType<typeof createClient>,
  table: string,
  decorate?: (query: any) => any,
): Promise<number> {
  let query = admin.from(table).select('*', { count: 'exact', head: true });
  if (decorate) query = decorate(query);
  const response = await query;
  if (response.error) throw response.error;
  return response.count ?? 0;
}

async function logEvent(
  context: AdminContext,
  action: string,
  entityType?: string,
  entityId?: string,
  metadata: JsonRecord = {},
) {
  const response = await context.admin.from('admin_audit_events').insert({
    actor_user_id: context.user.id,
    action,
    entity_type: entityType ?? null,
    entity_id: entityId ?? null,
    metadata,
  });
  if (response.error) throw response.error;
}

function requiredUuid(value: unknown, label: string): string {
  const id = firstString(value);
  if (!id || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    throw new HttpError(`Не удалось определить ${label}.`, 400);
  }
  return id;
}

function boundedInt(value: unknown, fallback: number, min: number, max: number) {
  const parsed = typeof value === 'number' ? value : Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(parsed)));
}

function optionalDate(value: unknown) {
  const raw = firstString(value);
  if (!raw) return null;
  const parsed = Date.parse(raw);
  if (!Number.isFinite(parsed)) throw new HttpError('Проверьте дату промокода.', 400);
  return new Date(parsed).toISOString();
}

function normalizeCode(value: string) {
  return value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 48);
}

function maskPromo(code: string) {
  if (code.length <= 4) return code;
  return `${code.slice(0, 3)}…${code.slice(-4)}`;
}

function generatePromoCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join('');
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

async function readJsonBody(request: Request): Promise<JsonRecord> {
  try {
    return asRecord(await request.json());
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

function json(payload: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function adminClient() {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}
