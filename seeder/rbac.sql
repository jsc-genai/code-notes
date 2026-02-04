-- =========================
-- AUTH A) ROLES SEED
-- =========================
INSERT INTO auth.roles (role_code, role_name, description, is_system)
VALUES
  ('admin',    'Administrator', 'Full access', true),
  ('staff',    'Store Staff',   'Operational access', false),
  ('customer', 'Customer',      'Buyer / customer role', false)
ON CONFLICT (role_code) DO UPDATE
SET role_name = EXCLUDED.role_name,
    description = EXCLUDED.description;

-- =========================
-- AUTH B) USERS SEED
-- =========================
WITH st AS (
  SELECT s.store_id
  FROM master.stores s
  WHERE s.store_code = 'STORE-JKT-01'
  LIMIT 1
)
INSERT INTO auth.users (store_id, email, phone, password_hash, display_name, is_active, email_verified_at)
SELECT store_id, 'admin@acme.co', '+62-812-0000-0000', '$2b$12$hash_admin', 'ACME Admin', true, now() FROM st
ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name;

WITH st AS (
  SELECT s.store_id
  FROM master.stores s
  WHERE s.store_code = 'STORE-JKT-01'
  LIMIT 1
)
INSERT INTO auth.users (store_id, email, phone, password_hash, display_name, is_active, email_verified_at)
SELECT store_id, 'staff1@acme.co', '+62-812-2222-3333', '$2b$12$hash_staff', 'ACME Staff 1', true, now() FROM st
ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name;

WITH st AS (
  SELECT s.store_id
  FROM master.stores s
  WHERE s.store_code = 'STORE-JKT-01'
  LIMIT 1
)
INSERT INTO auth.users (store_id, email, phone, password_hash, display_name, is_active, email_verified_at)
SELECT store_id, 'buyer1@acme.co', '+62-813-1111-2222', '$2b$12$hash_buyer', 'Buyer One', true, now() FROM st
ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name;



-- =========================
-- 02 - RBAC SEED
-- =========================
WITH ctx AS (
  SELECT
    t.tenant_id,
    s.store_id,
    u.user_id AS admin_user_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  JOIN auth.users u ON u.store_id = s.store_id
  WHERE t.tenant_code = 'TENANT-ACME'
    AND s.store_code = 'STORE-JKT-01'
    AND u.email = 'admin@acme.co'
),
roles AS (
  INSERT INTO auth.roles (role_code, role_name, description, is_system)
  VALUES
    ('admin', 'Administrator', 'Full access', true),
    ('staff', 'Store Staff', 'Operational access', false)
  ON CONFLICT (role_code) DO NOTHING
  RETURNING role_id, role_code
),
res_page_products AS (
  INSERT INTO auth.resources (resource_type, resource_key, path, meta)
  VALUES ('page', 'page.catalog.products', '/app/products', '{"group":"catalog"}')
  ON CONFLICT (resource_type, resource_key) DO UPDATE SET path = EXCLUDED.path
  RETURNING resource_id
),
res_menu_catalog AS (
  INSERT INTO auth.resources (resource_type, resource_key, path, meta)
  VALUES ('menu', 'menu.catalog', NULL, '{"icon":"box"}')
  ON CONFLICT (resource_type, resource_key) DO UPDATE SET meta = EXCLUDED.meta
  RETURNING resource_id
),
res_api_products AS (
  INSERT INTO auth.resources (resource_type, resource_key, path, meta)
  VALUES ('api_route', 'api.products.list', '/api/products', '{"method":"GET"}')
  ON CONFLICT (resource_type, resource_key) DO UPDATE SET path = EXCLUDED.path
  RETURNING resource_id
),
pages AS (
  INSERT INTO auth.pages (resource_id, page_title, route_key, sort_order)
  SELECT resource_id, 'Products', 'ProductsPage', 10
  FROM res_page_products
  ON CONFLICT (resource_id) DO NOTHING
  RETURNING page_id
),
menus AS (
  INSERT INTO auth.menus (resource_id, parent_menu_id, label, icon, sort_order, is_active)
  SELECT resource_id, NULL, 'Catalog', 'box', 10, true
  FROM res_menu_catalog
  ON CONFLICT (resource_id) DO NOTHING
  RETURNING menu_id
),
api_routes AS (
  INSERT INTO auth.api_routes (resource_id, http_method, path_pattern, is_public)
  SELECT resource_id, 'GET', '/api/products', false
  FROM res_api_products
  ON CONFLICT (resource_id) DO NOTHING
  RETURNING api_route_id
),
perms AS (
  INSERT INTO auth.permissions (permission_code, resource_id, action, description)
  VALUES
    ('catalog.product.view', (SELECT resource_id FROM res_page_products), 'view', 'View products page'),
    ('catalog.product.read', (SELECT resource_id FROM res_api_products),  'read', 'Read product list API')
  ON CONFLICT (permission_code) DO NOTHING
  RETURNING permission_id, permission_code
),
admin_role AS (
  SELECT role_id FROM auth.roles WHERE role_code = 'admin'
),
grant_admin AS (
  INSERT INTO auth.role_permissions (role_id, permission_id, effect)
  SELECT (SELECT role_id FROM admin_role), p.permission_id, 'allow'
  FROM auth.permissions p
  WHERE p.permission_code IN ('catalog.product.view', 'catalog.product.read')
  ON CONFLICT DO NOTHING
  RETURNING role_id
),
assign_admin AS (
  INSERT INTO auth.user_roles (user_id, role_id, store_id)
  SELECT c.admin_user_id, (SELECT role_id FROM admin_role), c.store_id
  FROM ctx c
  ON CONFLICT DO NOTHING
  RETURNING user_id
)
SELECT 'RBAC seeded' AS result;
