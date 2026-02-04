-- =======================================
-- 06 - CHECKOUT (ORDER + RESERVE STOCK)
-- =======================================
BEGIN;

WITH ctx AS (
  SELECT
    t.tenant_id,
    s.store_id,
    w.warehouse_id,
    u.user_id,
    cu.customer_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  JOIN inventory.warehouses w ON w.store_id = s.store_id AND w.code = 'WH-01'
  JOIN auth.users u ON u.email = 'buyer1@acme.co'
  JOIN orders.customers cu ON cu.user_id = u.user_id AND cu.store_id = s.store_id
  WHERE t.tenant_code = 'TENANT-ACME'
    AND s.store_code = 'STORE-JKT-01'
),
active_cart AS (
  SELECT c.cart_id
  FROM sales.carts c
  JOIN ctx ON ctx.user_id = c.user_id AND ctx.store_id = c.store_id
  WHERE c.status = 'active'
  ORDER BY c.updated_at DESC
  LIMIT 1
),
cart_lines AS (
  SELECT
    ci.variant_id,
    ci.quantity,
    ci.unit_price,
    (ci.quantity * ci.unit_price) AS line_total
  FROM sales.cart_items ci
  WHERE ci.cart_id = (SELECT cart_id FROM active_cart)
),
totals AS (
  SELECT
    SUM(line_total) AS subtotal,
    0::numeric AS discount,
    20000::numeric AS shipping,
    0::numeric AS tax
  FROM cart_lines
),
ins_order AS (
  INSERT INTO orders.orders
    (tenant_id, store_id, customer_id, order_number, status, payment_status, fulfillment_status,
     currency, subtotal_amount, discount_amount, shipping_amount, tax_amount, total_amount,
     notes, meta)
  SELECT
    ctx.tenant_id,
    ctx.store_id,
    ctx.customer_id,
    'ORD-2026-000001',
    'pending',
    'unpaid',
    'unfulfilled',
    'IDR',
    totals.subtotal,
    totals.discount,
    totals.shipping,
    totals.tax,
    (totals.subtotal - totals.discount + totals.shipping + totals.tax),
    'Please deliver after 5pm',
    '{"channel":"web"}'::jsonb
  FROM ctx, totals
  RETURNING order_id, tenant_id, store_id
),
ins_items AS (
  INSERT INTO orders.order_items
    (tenant_id, order_id, product_id, variant_id, sku, name, quantity, unit_price, discount, tax, line_total, meta)
  SELECT
    (SELECT tenant_id FROM ins_order),
    (SELECT order_id FROM ins_order),
    p.product_id,
    v.variant_id,
    v.variant_sku,
    p.name || ' - ' || COALESCE(v.name, ''),
    cl.quantity,
    cl.unit_price,
    0, 0,
    cl.line_total,
    '{}'::jsonb
  FROM cart_lines cl
  JOIN catalog.product_variants v ON v.variant_id = cl.variant_id
  JOIN catalog.products p ON p.product_id = v.product_id
  RETURNING order_item_id
),
addr_ship AS (
  INSERT INTO orders.order_addresses
    (tenant_id, order_id, address_type, full_name, phone, line1, line2, city, province, postal_code, country, meta)
  SELECT
    (SELECT tenant_id FROM ins_order),
    (SELECT order_id FROM ins_order),
    'shipping',
    'Buyer One',
    '+62-813-1111-2222',
    'Jl. Example No. 123',
    'Apartment 7A',
    'Tangerang Selatan',
    'Banten',
    '15412',
    'ID',
    '{"note":"leave at lobby"}'::jsonb
  RETURNING order_address_id
),
reserve_stock AS (
  -- reserve stock in stock_levels
  UPDATE inventory.stock_levels sl
  SET reserved = sl.reserved + cl.quantity,
      updated_at = now()
  FROM ctx, cart_lines cl
  WHERE sl.tenant_id = ctx.tenant_id
    AND sl.store_id = ctx.store_id
    AND sl.warehouse_id = ctx.warehouse_id
    AND sl.variant_id = cl.variant_id
    AND sl.on_hand - sl.reserved >= cl.quantity
  RETURNING sl.variant_id
),
reserve_movement AS (
  INSERT INTO inventory.stock_movements
    (tenant_id, store_id, warehouse_id, variant_id, movement_type, quantity, reference_type, reference_id, note)
  SELECT
    ctx.tenant_id, ctx.store_id, ctx.warehouse_id, cl.variant_id,
    'reserve', cl.quantity,
    'order', (SELECT order_id FROM ins_order),
    'Reserve stock for order checkout'
  FROM ctx, cart_lines cl
  RETURNING movement_id
),
close_cart AS (
  UPDATE sales.carts
  SET status = 'converted', updated_at = now()
  WHERE cart_id = (SELECT cart_id FROM active_cart)
  RETURNING cart_id
)
SELECT
  (SELECT order_id FROM ins_order) AS order_id,
  (SELECT cart_id FROM close_cart) AS converted_cart_id;

COMMIT;
