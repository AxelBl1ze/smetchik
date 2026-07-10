alter table public.profiles
add column if not exists pdf_show_brand_header boolean not null default true,
add column if not exists pdf_show_signatures boolean not null default true,
add column if not exists pdf_show_service_mark boolean not null default true,
add column if not exists pdf_payment_terms text,
add column if not exists pdf_footer_note text;
