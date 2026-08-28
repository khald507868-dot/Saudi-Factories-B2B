-- ============================================================
-- فحص: هل منتجات السلة تحمل اسمًا وسعرًا؟
-- يقرأ فقط - لا يعدّل شيئًا.
-- ============================================================
select
  p.id as "رقم المنتج",
  coalesce(nullif(p.name,''), '(فارغ)') as "اسم المنتج",
  coalesce(p.price::text, '(فارغ)') as "السعر",
  coalesce(f.name, '(بلا مصنع)') as "المصنع",
  ci.quantity as "الكمية"
from cart_items ci
join products p on p.id = ci.product_id
left join factories f on f.id = p.factory_id
order by ci.created_at desc
limit 20;
