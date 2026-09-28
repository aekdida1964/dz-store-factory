-- =====================================================================
-- المرحلة 6: ربط Gemini (سيناريوهات الفيديو ومصدر التوليد)
-- آمن للتنفيذ أكثر من مرة. الصقوه كاملاً في Supabase SQL Editor ثم Run
-- =====================================================================

alter table public.ad_orders add column if not exists video_scripts text[];
alter table public.ad_orders add column if not exists gen_source text;

-- نفس دالة المرحلة 5 مع منع التاجر من ملء الحقلين الجديدين
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
    new.video_scripts     := null;
    new.gen_source        := null;

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

-- فحص: يجب أن يظهر عمودان (gen_source و video_scripts)
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'ad_orders'
  and column_name in ('video_scripts', 'gen_source');
