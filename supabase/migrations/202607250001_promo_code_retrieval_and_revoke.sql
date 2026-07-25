-- Promocodes are only available to the service-role backed admin function.
-- App users have no table privileges and only submit a code to redeem-promo.
alter table public.promo_codes
add column if not exists code_value text;

comment on column public.promo_codes.code_value is
  'Original promo code. Restricted to the server-side admin console; legacy codes have no recoverable value.';
