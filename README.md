# Сметчик

Flutter MVP для создания смет, клиентов, каталога работ и PDF-коммерческих предложений.

## Запуск

Supabase dev-проект уже прописан в `lib/src/core/app_config.dart`, поэтому для обычного запуска достаточно:

```bash
flutter run -d chrome
```

Для запуска с другим Supabase-проектом можно переопределить параметры через `dart-define`:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY
```

Если дефолтные значения убрать из `app_config.dart`, без этих параметров приложение откроет экран настройки.

Подсказки российских адресов работают через Supabase Edge Function `suggest-addresses`.
Ключ DaData хранится только в Supabase secrets, во Flutter-приложение он не попадает.
Если секрет не задан, функция использует запасной поиск Nominatim/OpenStreetMap по России.

```bash
SUPABASE_TELEMETRY_DISABLED=1 supabase secrets set DADATA_API_KEY=YOUR_DADATA_API_KEY --project-ref kvuhtxipcrjsglklaury
SUPABASE_TELEMETRY_DISABLED=1 supabase functions deploy suggest-addresses --project-ref kvuhtxipcrjsglklaury --use-api
```

Email-коды отправляются через Supabase Auth Send Email Hook и Edge Function
`send-auth-email`. API-ключ UniSender, hook secret, list id и sender email
должны храниться только в Supabase secrets:

```bash
SUPABASE_TELEMETRY_DISABLED=1 supabase secrets set \
  UNISENDER_API_KEY=YOUR_UNISENDER_API_KEY \
  UNISENDER_LIST_ID=YOUR_UNISENDER_LIST_ID \
  UNISENDER_SENDER_EMAIL=YOUR_VERIFIED_SENDER_EMAIL \
  UNISENDER_SENDER_NAME=Сметчик \
  SEND_EMAIL_HOOK_SECRET=YOUR_SEND_EMAIL_HOOK_SECRET \
  --project-ref kvuhtxipcrjsglklaury

SUPABASE_TELEMETRY_DISABLED=1 supabase functions deploy send-auth-email \
  --use-api \
  --no-verify-jwt \
  --project-ref kvuhtxipcrjsglklaury
```

В Supabase Dashboard нужно включить `Authentication -> Hooks -> Send Email`
и указать URL функции:

```text
https://kvuhtxipcrjsglklaury.supabase.co/functions/v1/send-auth-email
```

Secret в Dashboard должен совпадать с `SEND_EMAIL_HOOK_SECRET` в Supabase
Edge Function secrets. В репозиторий эти значения не добавляются.

## Supabase

CLI в этом окружении нужно запускать с отключенной telemetry:

```bash
SUPABASE_TELEMETRY_DISABLED=1 supabase login
SUPABASE_TELEMETRY_DISABLED=1 supabase orgs list
SUPABASE_TELEMETRY_DISABLED=1 supabase projects create smetchik --org-id ORG_ID --db-password STRONG_PASSWORD --region eu-central-1
SUPABASE_TELEMETRY_DISABLED=1 supabase link --project-ref PROJECT_REF --password STRONG_PASSWORD
SUPABASE_TELEMETRY_DISABLED=1 supabase db push
```

Схема находится в `supabase/migrations/202606110001_initial_smetchik_schema.sql`.

## Сборки

```bash
flutter analyze
flutter test
flutter build web --release \
  --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY
JAVA_HOME=/Users/ilyasidnev/Library/Java/JavaVirtualMachines/corretto-21.0.5/Contents/Home \
  flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY
```

Для текущего dev-проекта можно собирать короче:

```bash
flutter build web --release
JAVA_HOME=/Users/ilyasidnev/Library/Java/JavaVirtualMachines/corretto-21.0.5/Contents/Home flutter build appbundle --release
```

Для Google Play создайте release keystore, скопируйте `android/key.properties.example` в `android/key.properties` и заполните реальные значения. Без `key.properties` сборка использует debug signing только для технической проверки.
