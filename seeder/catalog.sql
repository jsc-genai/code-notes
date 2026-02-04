-- =========================
-- 03 - CATALOG SEED
-- =========================
WITH ctx AS (
  SELECT t.tenant_id, s.store_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  WHERE t.tenant_code = 'TENANT-ACME' AND s.store_code = 'STORE-JKT-01'
),
cat AS (
  INSERT INTO catalog.categories (tenant_id, store_id, parent_id, name, slug, sort_order, is_active)
  SELECT tenant_id, store_id, NULL, 'Electronics', 'electronics', 1, true FROM ctx
  ON CONFLICT (store_id, slug) DO UPDATE SET name = EXCLUDED.name
  RETURNING category_id
),
prod AS (
  INSERT INTO catalog.products (tenant_id, store_id, category_id, sku, name, slug, description, status, price, currency, attributes)
  SELECT
    c.tenant_id,
    c.store_id,
    (SELECT category_id FROM cat),
    'SKU-HEADPHONE-001',
    'Wireless Headphone X',
    'wireless-headphone-x',
    'Noise canceling wireless headphone',
    'active',
    599000,
    'IDR',
    '{"brand":"ACME","warranty_months":12}'::jsonb
  FROM ctx c
  ON CONFLICT (store_id, sku) DO UPDATE SET name = EXCLUDED.name
  RETURNING product_id
),
var AS (
  INSERT INTO catalog.product_variants (product_id, variant_sku, name, price, is_active)
  SELECT
    (SELECT product_id FROM prod),
    'SKU-HEADPHONE-001-BLK',
    'Black',
    599000,
    true
  ON CONFLICT (product_id, variant_sku) DO UPDATE SET price = EXCLUDED.price
  RETURNING variant_id
),
img AS (
  INSERT INTO catalog.product_images (product_id, url, alt_text, sort_order)
  SELECT (SELECT product_id FROM prod),
         'https://cdn.example.com/products/headphone-x-black.jpg',
         'Wireless Headphone X Black',
         1
  ON CONFLICT DO NOTHING
  RETURNING image_id
)
SELECT
  (SELECT category_id FROM cat) AS category_id,
  (SELECT product_id  FROM prod) AS product_id,
  (SELECT variant_id  FROM var)  AS variant_id;
