-- =====================================================================
-- المرحلة 5: باقات الإعلانات
-- آمن للتنفيذ أكثر من مرة. الصقوه كاملاً في Supabase SQL Editor ثم Run
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) إعدادات المنصة (تعليمات الدفع التي يراها التجار)
--    القراءة عامة، والتعديل للأدمن فقط. لا تضعوا فيها أسراراً.
-- ---------------------------------------------------------------------
create table if not exists public.platform_settings (
  key        text primary key,
  value      text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.platform_settings enable row level security;

drop policy if exists "settings_public_select" on public.platform_settings;
create policy "settings_public_select"
  on public.platform_settings for select
  using (true);

drop policy if exists "settings_admin_manage" on public.platform_settings;
create policy "settings_admin_manage"
  on public.platform_settings for all
  using (public.is_admin())
  with check (public.is_admin());

insert into public.platform_settings (key, value)
values ('payment_instructions', '')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2) طلبات الإعلانات: تفاصيل الطلب ومبلغه
-- ---------------------------------------------------------------------
alter table public.ad_orders add column if not exists brief jsonb;
alter table public.ad_orders add column if not exists amount_dzd integer;

create or replace function public.ad_orders_before_insert()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_price  integer;
  v_active boolean;
begin
  select price_dzd, is_active into v_price, v_active
  from public.ad_packages where id = new.package_id;

  if v_price is null or v_active is not true then
    raise exception 'USER: هذه الباقة غير متاحة';
  end if;

  if auth.uid() is not null and not public.is_admin() then
    new.merchant_id       := auth.uid();
    new.status            := 'pending_payment';
    new.generated_ad_copy := null;
    new.delivery_urls     := null;

    if new.brief is null
       or jsonb_typeof(new.brief) <> 'object'
       or length(new.brief::text) > 4000 then
      raise exception 'USER: تفاصيل الطلب غير صالحة';
    end if;

    if (select count(*) from public.ad_orders
        where merchant_id = auth.uid() and status = 'pending_payment') >= 5 then
      raise exception 'USER: لديكم عدة طلبات بانتظار الدفع، أكملوها أولاً';
    end if;
  end if;

  new.amount_dzd := v_price;
  return new;
end;
$$;

drop trigger if exists trg_ad_orders_before_insert on public.ad_orders;
create trigger trg_ad_orders_before_insert
  before insert on public.ad_orders
  for each row execute function public.ad_orders_before_insert();

-- ---------------------------------------------------------------------
-- 3) فحص: يجب أن يظهر جدول الإعدادات بصف واحد على الأقل
-- ---------------------------------------------------------------------
select key, length(value) as chars from public.platform_settings;
