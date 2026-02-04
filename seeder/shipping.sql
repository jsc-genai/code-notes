-- =======================================
-- 08 - SHIPPING + FULFILLMENT
-- =======================================
BEGIN;

WITH ctx AS (
  SELECT t.tenant_id, s.store_id, w.warehouse_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  JOIN inventory.warehouses w ON w.store_id = s.store_id AND w.code = 'WH-01'
  WHERE t.tenant_code = 'TENANT-ACME' AND s.store_code = 'STORE-JKT-01'
),
ord AS (
  SELECT o.order_id
  FROM orders.orders o
  JOIN ctx ON ctx.store_id = o.store_id
  WHERE o.order_number = 'ORD-2026-000001'
),
ship_provider AS (
  INSERT INTO shipping.shipping_providers
    (tenant_id, store_id, provider_code, display_name, is_active, config)
  SELECT
    ctx.tenant_id, ctx.store_id,
    'manual', 'Manual Courier', true,
    '{"note":"use internal courier"}'::jsonb
  FROM ctx
  ON CONFLICT (tenant_id, store_id, provider_code) DO UPDATE SET is_active = true
  RETURNING shipping_provider_id
),
shipment AS (
  INSERT INTO shipping.shipments
    (tenant_id, store_id, order_id, shipping_provider_id, status, service_code, tracking_number, shipping_cost, currency, meta)
  SELECT
    ctx.tenant_id, ctx.store_id,
    ord.order_id,
    ship_provider.shipping_provider_id,
    'packed',
    'SAME_DAY',
    'TRK-ACME-0001',
    20000, 'IDR',
    '{"pickup_window":"17:00-19:00"}'::jsonb
  FROM ctx, ord, ship_provider
  RETURNING shipment_id
),
ship_items AS (
  INSERT INTO shipping.shipment_items (tenant_id, shipment_id, order_item_id, quantity)
  SELECT
    ctx.tenant_id,
    shipment.shipment_id,
    oi.order_item_id,
    oi.quantity
  FROM ctx, shipment
  JOIN orders.order_items oi ON oi.order_id = (SELECT order_id FROM ord)
  RETURNING shipment_item_id
),
-- When shipping is created and ready to ship, deduct stock:
deduct_stock AS (
  UPDATE inventory.stock_levels sl
  SET
    on_hand  = sl.on_hand - oi.quantity,
    reserved = sl.reserved - oi.quantity,
    updated_at = now()
  FROM ctx
  JOIN orders.order_items oi ON oi.order_id = (SELECT order_id FROM ord)
  WHERE sl.tenant_id = ctx.tenant_id
    AND sl.store_id = ctx.store_id
    AND sl.warehouse_id = ctx.warehouse_id
    AND sl.variant_id = oi.variant_id
  RETURNING sl.variant_id
),
movement_sale AS (
  INSERT INTO inventory.stock_movements
    (tenant_id, store_id, warehouse_id, variant_id, movement_type, quantity, reference_type, reference_id, note)
  SELECT
    ctx.tenant_id, ctx.store_id, ctx.warehouse_id,
    oi.variant_id,
    'sale',
    -oi.quantity,
    'order', (SELECT order_id FROM ord),
    'Stock deducted when shipment created'
  FROM ctx
  JOIN orders.order_items oi ON oi.order_id = (SELECT order_id FROM ord)
  RETURNING movement_id
),
update_order_fulfillment AS (
  UPDATE orders.orders
  SET fulfillment_status = 'fulfilled', updated_at = now()
  WHERE order_id = (SELECT order_id FROM ord)
  RETURNING order_id
),
tracking1 AS (
  INSERT INTO shipping.tracking_events
    (tenant_id, shipment_id, status_code, description, location, event_time, raw_payload)
  SELECT
    ctx.tenant_id,
    (SELECT shipment_id FROM shipment),
    'PICKED_UP', 'Picked up by courier', 'Jakarta', now(),
    '{"carrier":"manual"}'::jsonb
  FROM ctx
)
SELECT
  (SELECT shipment_id FROM shipment) AS shipment_id,
  (SELECT order_id FROM update_order_fulfillment) AS fulfilled_order_id;

COMMIT;
