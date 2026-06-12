const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type JsonValue = Record<string, unknown> | unknown[];

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return json({ suggestions: [] }, 405);
  }

  const body = await readJsonBody(request);
  const query = typeof body.query === 'string' ? body.query.trim() : '';
  const requestedCount = typeof body.count === 'number' ? body.count : 6;
  const count = Math.max(1, Math.min(8, Math.round(requestedCount)));

  if (query.length < 3) {
    return json({ suggestions: [] });
  }

  const dadataKey = Deno.env.get('DADATA_API_KEY')?.trim();
  const dadata = dadataKey ? await suggestWithDadata(query, count, dadataKey) : [];
  const suggestions = dadata.length > 0
    ? dadata
    : await suggestWithNominatim(query, count);

  return json({ suggestions });
});

async function readJsonBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const payload = await request.json();
    return isRecord(payload) ? payload : {};
  } catch {
    return {};
  }
}

async function suggestWithDadata(
  query: string,
  count: number,
  apiKey: string,
): Promise<string[]> {
  try {
    const response = await fetch(
      'https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/address',
      {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Token ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ query, count }),
      },
    );

    if (!response.ok) {
      return [];
    }

    const payload = await response.json();
    if (!isRecord(payload) || !Array.isArray(payload.suggestions)) {
      return [];
    }

    return unique(
      payload.suggestions
        .filter(isRecord)
        .filter((item) => {
          const data = item.data;
          return isRecord(data) && data.country_iso_code === 'RU';
        })
        .map(compactDadataAddress)
        .filter((value): value is string => typeof value === 'string'),
    ).slice(0, count);
  } catch {
    return [];
  }
}

async function suggestWithNominatim(query: string, count: number): Promise<string[]> {
  try {
    const url = new URL('https://nominatim.openstreetmap.org/search');
    url.searchParams.set('q', query);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('countrycodes', 'ru');
    url.searchParams.set('accept-language', 'ru');
    url.searchParams.set('limit', String(count));

    const response = await fetch(url, {
      headers: {
        Accept: 'application/json',
        Referer: 'https://smetchik.app',
        'User-Agent': 'Smetchik/1.0 address suggestions',
      },
    });

    if (!response.ok) {
      return [];
    }

    const payload = await response.json();
    if (!Array.isArray(payload)) {
      return [];
    }

    return unique(
      payload
        .filter(isRecord)
        .filter((item) => {
          const address = item.address;
          return isRecord(address) && address.country_code === 'ru';
        })
        .map(compactNominatimAddress)
        .filter((value): value is string => typeof value === 'string'),
    ).slice(0, count);
  } catch {
    return [];
  }
}

function compactDadataAddress(item: Record<string, unknown>): string | null {
  const data = item.data;
  if (!isRecord(data)) {
    return typeof item.value === 'string' ? item.value : null;
  }

  const city = firstString(
    data.city_with_type,
    data.settlement_with_type,
    data.area_with_type,
    data.region_with_type,
  );
  const street = firstString(
    data.street_with_type,
    data.settlement_with_type,
    data.city_district_with_type,
  );
  const house = compactHouse(
    firstString(data.house_type_full, data.house_type),
    firstString(data.house),
  );

  return joinAddressParts(['Россия', city, street, house]);
}

function compactNominatimAddress(item: Record<string, unknown>): string | null {
  const address = item.address;
  if (!isRecord(address)) {
    return typeof item.display_name === 'string' ? item.display_name : null;
  }

  const city = firstString(
    address.city,
    address.town,
    address.village,
    address.hamlet,
    address.municipality,
    address.county,
    address.state,
  );
  const street = firstString(
    address.road,
    address.pedestrian,
    address.footway,
    address.residential,
    address.neighbourhood,
  );
  const house = firstString(address.house_number);

  return joinAddressParts(['Россия', city, street, house]);
}

function firstString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function compactHouse(type: string | null, number: string | null): string | null {
  if (!number) return null;
  if (!type) return number;
  const normalizedType = type.toLowerCase();
  if (normalizedType === 'дом' || normalizedType === 'д') return number;
  return `${type} ${number}`;
}

function joinAddressParts(parts: Array<string | null>): string | null {
  const compact = parts
    .map((part) => part?.trim())
    .filter((part): part is string => Boolean(part));
  return compact.length > 1 ? compact.join(', ') : null;
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

function unique(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
