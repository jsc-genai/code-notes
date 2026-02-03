-- =========================
-- 01 - TENANT + STORE SETUP
-- =========================
WITH ins_tenant AS (
  INSERT INTO master.tenants (tenant_code, tenant_name, plan, status)
  VALUES ('TENANT-ACME', 'ACME Commerce', 'pro', 'active')
  RETURNING tenant_id
),
ins_store AS (
  INSERT INTO master.stores (tenant_id, store_code, store_name, status, timezone, default_currency)
  SELECT tenant_id, 'STORE-JKT-01', 'ACME Jakarta Store', 'active', 'Asia/Jakarta', 'IDR'
  FROM ins_tenant
  RETURNING store_id, tenant_id
),
ins_wh AS (
  INSERT INTO inventory.warehouses (store_id, tenant_id, code, name, is_active)
  SELECT store_id, tenant_id, 'WH-01', 'Main Warehouse', true
  FROM ins_store
  RETURNING warehouse_id, store_id, tenant_id
),
ins_admin AS (
  INSERT INTO auth.users (store_id, email, phone, password_hash, display_name, is_active, email_verified_at)
  SELECT store_id, 'admin@acme.co', '+62-812-0000-0000', '$2b$12$hash_here', 'ACME Admin', true, now()
  FROM ins_store
  RETURNING user_id
)
SELECT
  (SELECT tenant_id FROM ins_store)  AS tenant_id,
  (SELECT store_id  FROM ins_store)  AS store_id,
  (SELECT warehouse_id FROM ins_wh)  AS warehouse_id,
  (SELECT user_id FROM ins_admin)    AS admin_user_id;
