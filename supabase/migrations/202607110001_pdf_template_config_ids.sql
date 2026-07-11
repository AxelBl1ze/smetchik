alter table public.profiles
alter column pdf_template set default 'standard_free';

alter table public.profiles
drop constraint if exists profiles_pdf_template_check;

alter table public.profiles
add constraint profiles_pdf_template_check
check (
  pdf_template in (
    'standard_free',
    'premium_gold_noir',
    'premium_white_space',
    'premium_bright_accent',
    'premium_corporate_classic',
    'premium_invoice_first',
    'premium_craft_paper',
    'premium_tech_grid',
    'premium_cover_deluxe',
    'premium_story_format',
    'premium_bilingual',
    'premium_signed_sealed',
    'accent',
    'classic',
    'compact'
  )
);

alter table public.profiles
drop constraint if exists profiles_pdf_accent_color_check;

alter table public.profiles
add constraint profiles_pdf_accent_color_check
check (pdf_accent_color ~ '^#[0-9A-Fa-f]{6}$');
