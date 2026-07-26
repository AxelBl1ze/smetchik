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
      return json({ error: 'Поддержка принимает только POST-запросы.' }, 405);
    }

    const body = await readJsonBody(request);
    const action = firstString(body.action);
    switch (action) {
      case 'create':
        return json(await createTicket(request, body));
      case 'thread':
        return json(await loadThread(body));
      case 'reply':
        return json(await replyToTicket(body));
      default:
        throw new HttpError('Неизвестное действие поддержки.', 400);
    }
  } catch (error) {
    console.error(error);
    const status = error instanceof HttpError ? error.status : 500;
    return json(
      {
        error:
          error instanceof HttpError
            ? error.message
            : 'Поддержка временно недоступна. Повторите попытку позже.',
      },
      status,
    );
  }
});

async function createTicket(request: Request, body: JsonRecord): Promise<JsonRecord> {
  const email = requiredEmail(body.email);
  const subject = requiredText(body.subject, 'Укажите тему обращения.', 3, 120);
  const message = requiredText(body.message, 'Опишите вопрос.', 1, 4000);
  const admin = adminClient();
  const after = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const recent = await admin
    .from('support_tickets')
    .select('id', { count: 'exact', head: true })
    .eq('contact_email', email)
    .gte('created_at', after);
  if (recent.error) throw recent.error;
  if ((recent.count ?? 0) >= 3) {
    throw new HttpError('Слишком много обращений. Подождите 10 минут и попробуйте снова.', 429);
  }

  const publicToken = crypto.randomUUID();
  const ticket = await admin
    .from('support_tickets')
    .insert({
      contact_email: email,
      public_token: publicToken,
      subject,
      context: { source: 'public_help' },
    })
    .select('id')
    .single();
  if (ticket.error) throw ticket.error;

  const inserted = await admin.from('support_messages').insert({
    ticket_id: ticket.data.id,
    author_role: 'user',
    body: message,
  });
  if (inserted.error) throw inserted.error;

  const publicUrl = publicThreadUrl(request, publicToken);
  const emailSent = await sendThreadLink({ email, subject, publicUrl });
  return { token: publicToken, emailSent };
}

async function loadThread(body: JsonRecord): Promise<JsonRecord> {
  const context = await ticketByToken(firstString(body.token));
  const messages = await context.admin
    .from('support_messages')
    .select('id,author_role,body,created_at')
    .eq('ticket_id', context.ticket.id)
    .order('created_at', { ascending: true })
    .order('id', { ascending: true });
  if (messages.error) throw messages.error;
  return {
    ticket: publicTicket(context.ticket),
    messages: messages.data ?? [],
  };
}

async function replyToTicket(body: JsonRecord): Promise<JsonRecord> {
  const context = await ticketByToken(firstString(body.token));
  if (context.ticket.status === 'resolved') {
    throw new HttpError('Обращение закрыто. Создайте новое, если вопрос появился снова.', 409);
  }
  const message = requiredText(body.message, 'Введите сообщение.', 1, 4000);
  const inserted = await context.admin
    .from('support_messages')
    .insert({ ticket_id: context.ticket.id, author_role: 'user', body: message })
    .select('id')
    .single();
  if (inserted.error) throw inserted.error;
  return { messageId: inserted.data.id };
}

async function ticketByToken(token: string | null) {
  if (!token || !/^[0-9a-f-]{36}$/i.test(token)) {
    throw new HttpError('Ссылка на обращение недействительна.', 404);
  }
  const admin = adminClient();
  const response = await admin
    .from('support_tickets')
    .select('id,subject,status,public_token,created_at,updated_at')
    .eq('public_token', token)
    .maybeSingle();
  if (response.error) throw response.error;
  if (!response.data) throw new HttpError('Обращение не найдено.', 404);
  return { admin, ticket: response.data };
}

function publicTicket(ticket: JsonRecord) {
  return {
    id: ticket.id,
    subject: ticket.subject,
    status: ticket.status,
    createdAt: ticket.created_at,
    updatedAt: ticket.updated_at,
  };
}

function adminClient() {
  const url = Deno.env.get('SUPABASE_URL')?.trim();
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim();
  if (!url || !serviceRole) {
    throw new Error('Supabase service credentials are not configured.');
  }
  return createClient(url, serviceRole, { auth: { persistSession: false } });
}

function publicThreadUrl(request: Request, token: string) {
  const configured = Deno.env.get('PUBLIC_APP_URL')?.trim();
  const origin = configured || request.headers.get('origin')?.trim() || 'https://smetchik.pages.dev';
  return `${origin.replace(/\/$/, '')}/#/help/${token}`;
}

async function sendThreadLink(input: {
  email: string;
  subject: string;
  publicUrl: string;
}): Promise<boolean> {
  const apiKey = Deno.env.get('UNISENDER_API_KEY')?.trim();
  const senderEmail = Deno.env.get('UNISENDER_SENDER_EMAIL')?.trim();
  const senderName = Deno.env.get('UNISENDER_SENDER_NAME')?.trim() || 'Сметчик';
  if (!apiKey || !senderEmail) return false;

  try {
    const form = new URLSearchParams({
      api_key: apiKey,
      email: input.email,
      sender_name: senderName,
      sender_email: senderEmail,
      subject: `Сметчик: ваше обращение «${input.subject}»`,
      body: `
        <div style="font-family:Arial,sans-serif;color:#1A1A1A;line-height:1.5">
          <h2 style="margin:0 0 12px">Ваше обращение принято</h2>
          <p>Мы ответим в личной переписке. Сохраните эту ссылку:</p>
          <p><a href="${input.publicUrl}" style="color:#C96500;font-weight:700">Открыть обращение в Сметчике</a></p>
          <p style="color:#5F5E5A;font-size:13px">Ссылка не требует входа в аккаунт. Не пересылайте её другим людям.</p>
        </div>
      `.trim(),
      lang: 'ru',
    });
    const response = await fetch('https://api.unisender.com/ru/api/sendEmail?format=json', {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form,
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || (isRecord(result) && typeof result.error === 'string')) {
      console.error('Unable to send public support link', result);
      return false;
    }
    return true;
  } catch (error) {
    console.error('Unable to send public support link', error);
    return false;
  }
}

async function readJsonBody(request: Request): Promise<JsonRecord> {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError('Некорректный запрос.', 400);
  }
  return body as JsonRecord;
}

function firstString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requiredEmail(value: unknown) {
  const email = firstString(value)?.toLowerCase();
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpError('Введите корректный email для ответа.', 400);
  }
  return email;
}

function requiredText(
  value: unknown,
  errorMessage: string,
  min: number,
  max: number,
) {
  const text = firstString(value);
  if (!text || text.length < min || text.length > max) {
    throw new HttpError(errorMessage, 400);
  }
  return text;
}

function json(payload: JsonRecord, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
