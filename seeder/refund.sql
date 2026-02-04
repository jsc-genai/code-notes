-- =======================================
-- 09 - OPTIONAL REFUND
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
  SELECT order_id
  FROM orders.orders
  WHERE order_number = 'ORD-2026-000001'
),
intent AS (
  SELECT payment_intent_id, amount
  FROM payments.payment_intents
  WHERE order_id = (SELECT order_id FROM ord)
  ORDER BY created_at DESC
  LIMIT 1
),
refund_tx AS (
  INSERT INTO payments.payment_transactions
    (tenant_id, store_id, payment_intent_id, tx_type, status, amount, currency, provider_tx_id, raw_response)
  SELECT
    ctx.tenant_id, ctx.store_id,
    intent.payment_intent_id,
    'refund', 'succeeded',
    intent.amount,
    'IDR',
    'ext_tx_refund_001',
    '{"reason":"customer_return"}'::jsonb
  FROM ctx, intent
  RETURNING payment_tx_id
),
update_intent AS (
  UPDATE payments.payment_intents
  SET status = 'refunded', updated_at = now()
  WHERE payment_intent_id = (SELECT payment_intent_id FROM intent)
),
update_order AS (
  UPDATE orders.orders
  SET payment_status = 'refunded', status = 'refunded', updated_at = now()
  WHERE order_id = (SELECT order_id FROM ord)
  RETURNING order_id
),
-- If you physically receive returned items, return to stock:
return_stock AS (
  UPDATE inventory.stock_levels sl
  SET on_hand = sl.on_hand + oi.quantity,
      updated_at = now()
  FROM ctx
  JOIN orders.order_items oi ON oi.order_id = (SELECT order_id FROM ord)
  WHERE sl.tenant_id = ctx.tenant_id
    AND sl.store_id = ctx.store_id
    AND sl.warehouse_id = ctx.warehouse_id
    AND sl.variant_id = oi.variant_id
  RETURNING sl.variant_id
),
movement_return AS (
  INSERT INTO inventory.stock_movements
    (tenant_id, store_id, warehouse_id, variant_id, movement_type, quantity, reference_type, reference_id, note)
  SELECT
    ctx.tenant_id, ctx.store_id, ctx.warehouse_id,
    oi.variant_id,
    'adjustment', oi.quantity,
    'order', (SELECT order_id FROM ord),
    'Stock returned after refund'
  FROM ctx
  JOIN orders.order_items oi ON oi.order_id = (SELECT order_id FROM ord)
)
SELECT
  (SELECT payment_tx_id FROM refund_tx) AS refund_payment_tx_id,
  (SELECT order_id FROM update_order) AS refunded_order_id;

COMMIT;
