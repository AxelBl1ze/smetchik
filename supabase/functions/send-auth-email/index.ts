import { Webhook } from 'https://esm.sh/standardwebhooks@1.0.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, webhook-id, webhook-signature, webhook-timestamp',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type JsonValue = Record<string, unknown> | unknown[];

Deno.serve(async (request) => {
  try {
    if (request.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const body = await request.text();
    const signatureError = await verifyHookSignature(request, body);
    if (signatureError) {
      return json({ error: signatureError }, 401);
    }

    const payload = parseJson(body);
    if (!payload) {
      return json({ error: 'Invalid JSON payload' }, 400);
    }

    const emailData = getEmailData(payload);
    const email = extractEmail(payload);
    if (!email) {
      return json({ error: 'Email is missing' }, 400);
    }

    const actionType =
      firstString(emailData.email_action_type, payload.email_action_type) ??
        'magiclink';
    const token = firstString(emailData.token, payload.token);
    if (!token || !/^\d{6}$/.test(token)) {
      return json({ error: 'Email OTP token is missing' }, 400);
    }

    await sendWithUnisender({
      email,
      subject: subjectFor(actionType),
      body: buildEmailHtml({ actionType, token }),
    });

    return json({});
  } catch (error) {
    console.error(error);
    return json({ error: 'Failed to send auth email' }, 500);
  }
});

async function verifyHookSignature(
  request: Request,
  body: string,
): Promise<string | null> {
  const secret = Deno.env.get('SEND_EMAIL_HOOK_SECRET')?.trim();
  if (!secret) return 'SEND_EMAIL_HOOK_SECRET is not configured';

  try {
    const headers = Object.fromEntries(request.headers.entries());
    const hookSecret = secret.replace(/^v1,whsec_/, '');
    new Webhook(hookSecret).verify(body, headers);
    return null;
  } catch {
    return 'Invalid webhook signature';
  }
}

async function sendWithUnisender(message: {
  email: string;
  subject: string;
  body: string;
}) {
  const apiKey = Deno.env.get('UNISENDER_API_KEY')?.trim();
  const senderEmail = Deno.env.get('UNISENDER_SENDER_EMAIL')?.trim();
  const senderName =
    Deno.env.get('UNISENDER_SENDER_NAME')?.trim() || 'Сметчик';
  const listId = Deno.env.get('UNISENDER_LIST_ID')?.trim();

  if (!apiKey) {
    throw new Error('UNISENDER_API_KEY is not configured');
  }
  if (!senderEmail) {
    throw new Error('UNISENDER_SENDER_EMAIL is not configured');
  }

  const form = new URLSearchParams({
    api_key: apiKey,
    email: message.email,
    sender_name: senderName,
    sender_email: senderEmail,
    subject: message.subject,
    body: message.body,
    lang: 'ru',
  });

  if (listId) {
    form.set('list_id', listId);
  }

  const response = await fetch(
    'https://api.unisender.com/ru/api/sendEmail?format=json',
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form,
    },
  );

  const result = await response.json().catch(() => ({}));
  const apiError = unisenderError(result);
  if (!response.ok || apiError) {
    const message =
      apiError ??
      (isRecord(result) && typeof result.error === 'string'
        ? result.error
        : `UniSender request failed with ${response.status}`);
    throw new Error(message);
  }
}

function buildEmailHtml(input: {
  actionType: string;
  token: string | null;
}): string {
  const title = titleFor(input.actionType);
  const lead = leadFor(input.actionType);
  const code = `<div style="letter-spacing:8px;font-size:34px;font-weight:900;color:#1A1A1A;background:#FEF0E0;border:1px solid #F5820D;border-radius:16px;padding:18px 20px;text-align:center;">${escapeHtml(input.token ?? '')}</div>`;

  return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)}</title>
  </head>
  <body style="margin:0;background:#F7F6F3;font-family:Arial,Helvetica,sans-serif;color:#1A1A1A;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F7F6F3;padding:24px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:#FFFFFF;border:1px solid rgba(0,0,0,.08);border-radius:22px;overflow:hidden;">
            <tr>
              <td style="padding:24px 24px 10px;">
                <div style="display:inline-flex;align-items:center;justify-content:center;width:54px;height:54px;border-radius:18px;background:#FEF0E0;color:#F5820D;font-size:28px;font-weight:900;">С</div>
                <h1 style="margin:18px 0 8px;font-size:26px;line-height:1.15;">${escapeHtml(title)}</h1>
                <p style="margin:0;color:#5F5E5A;font-size:16px;line-height:1.45;">${escapeHtml(lead)}</p>
              </td>
            </tr>
            <tr>
              <td style="padding:14px 24px 6px;">${code}</td>
            </tr>
            <tr>
              <td style="padding:8px 24px 24px;color:#7A766E;font-size:13px;line-height:1.45;">
                Код действует ограниченное время и подходит только для этого действия.
              </td>
            </tr>
            <tr>
              <td style="padding:18px 24px;background:#1A1A1A;color:#D7D4CC;font-size:13px;line-height:1.45;">
                Если вы не запрашивали это письмо, просто проигнорируйте его.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

function subjectFor(actionType: string): string {
  if (actionType === 'recovery') return 'Сброс пароля в Сметчике';
  if (actionType === 'signup') return 'Подтвердите email в Сметчике';
  return 'Код входа в Сметчик';
}

function titleFor(actionType: string): string {
  if (actionType === 'recovery') return 'Сброс пароля';
  if (actionType === 'signup') return 'Подтвердите email';
  return 'Код входа';
}

function leadFor(actionType: string): string {
  if (actionType === 'recovery') {
    return 'Введите этот код в Сметчике, затем задайте новый пароль.';
  }
  if (actionType === 'signup') {
    return 'Введите этот код в Сметчике, чтобы завершить создание аккаунта.';
  }
  return 'Введите этот код в Сметчике, чтобы войти в аккаунт.';
}

function extractEmail(payload: Record<string, unknown>): string | null {
  const user = isRecord(payload.user) ? payload.user : {};
  const emailData = getEmailData(payload);
  return firstString(user.email, emailData.email, payload.email);
}

function getEmailData(payload: Record<string, unknown>): Record<string, unknown> {
  if (isRecord(payload.email_data)) return payload.email_data;
  if (isRecord(payload.email)) return payload.email;
  return {};
}

function firstString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function parseJson(value: string): Record<string, unknown> | null {
  try {
    const payload = JSON.parse(value);
    return isRecord(payload) ? payload : null;
  } catch {
    return null;
  }
}

function json(payload: JsonValue, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function unisenderError(result: unknown): string | null {
  if (!isRecord(result)) return null;
  if (typeof result.error === 'string') return result.error;

  const data = result.result;
  if (!Array.isArray(data)) return null;
  for (const item of data) {
    if (!isRecord(item)) continue;
    const errors = item.errors;
    if (!Array.isArray(errors) || errors.length === 0) continue;
    const first = errors[0];
    if (typeof first === 'string') return first;
    if (isRecord(first) && typeof first.message === 'string') {
      return first.message;
    }
  }
  return null;
}
