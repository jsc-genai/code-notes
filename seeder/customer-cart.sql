-- =========================
-- 05 - CUSTOMER + CART FLOW
-- =========================
WITH ctx AS (
  SELECT t.tenant_id, s.store_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  WHERE t.tenant_code = 'TENANT-ACME' AND s.store_code = 'STORE-JKT-01'
),
ins_user AS (
  INSERT INTO auth.users (store_id, email, phone, password_hash, display_name, is_active, email_verified_at)
  SELECT store_id, 'buyer1@acme.co', '+62-813-1111-2222', '$2b$12$hash_buyer', 'Buyer One', true, now()
  FROM ctx
  ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name
  RETURNING user_id
),
ins_customer AS (
  INSERT INTO orders.customers (tenant_id, store_id, user_id, email, phone, full_name)
  SELECT c.tenant_id, c.store_id, u.user_id, 'buyer1@acme.co', '+62-813-1111-2222', 'Buyer One'
  FROM ctx c, ins_user u
  RETURNING customer_id, user_id
),
ins_cart AS (
  INSERT INTO sales.carts (tenant_id, store_id, user_id, status, currency, created_at, updated_at, expires_at)
  SELECT c.tenant_id, c.store_id, cu.user_id, 'active', 'IDR', now(), now(), now() + interval '2 days'
  FROM ctx c, ins_customer cu
  RETURNING cart_id
),
variant AS (
  SELECT v.variant_id, p.price
  FROM catalog.products p
  JOIN catalog.product_variants v ON v.product_id = p.product_id
  JOIN master.stores s ON s.store_id = p.store_id
  WHERE s.store_code = 'STORE-JKT-01'
    AND p.sku = 'SKU-HEADPHONE-001'
    AND v.variant_sku = 'SKU-HEADPHONE-001-BLK'
),
add_item AS (
  INSERT INTO sales.cart_items (cart_id, variant_id, quantity, unit_price)
  SELECT (SELECT cart_id FROM ins_cart), variant_id, 2, price
  FROM variant
  ON CONFLICT (cart_id, variant_id) DO UPDATE SET quantity = EXCLUDED.quantity
  RETURNING cart_item_id
)
SELECT
  (SELECT customer_id FROM ins_customer) AS customer_id,
  (SELECT cart_id FROM ins_cart) AS cart_id,
  (SELECT cart_item_id FROM add_item) AS cart_item_id;
