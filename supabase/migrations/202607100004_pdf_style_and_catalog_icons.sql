alter table public.profiles
add column if not exists pdf_template text not null default 'accent',
add column if not exists pdf_accent_color text not null default '#F5820D';

alter table public.profiles
drop constraint if exists profiles_pdf_template_check;

alter table public.profiles
add constraint profiles_pdf_template_check
check (pdf_template in ('classic', 'accent', 'compact'));

alter table public.profiles
drop constraint if exists profiles_pdf_accent_color_check;

alter table public.profiles
add constraint profiles_pdf_accent_color_check
check (pdf_accent_color in ('#F5820D', '#1A1A1A', '#3B6D11', '#185FA5'));

alter table public.catalog_categories
add column if not exists icon_key text not null default 'handyman';
