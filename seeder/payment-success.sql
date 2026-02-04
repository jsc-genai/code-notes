-- =======================================
-- 07B - WEBHOOK: SUCCEEDED -> CAPTURED
-- =======================================
BEGIN;

WITH ctx AS (
  SELECT t.tenant_id, s.store_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  WHERE t.tenant_code = 'TENANT-ACME' AND s.store_code = 'STORE-JKT-01'
),
provider AS (
  SELECT provider_id
  FROM payments.payment_providers p
  JOIN ctx ON ctx.tenant_id = p.tenant_id AND ctx.store_id = p.store_id
  WHERE p.provider_code = 'generic_gateway'
),
intent AS (
  SELECT pi.payment_intent_id, pi.order_id, pi.amount
  FROM payments.payment_intents pi
  JOIN ctx ON ctx.store_id = pi.store_id
  WHERE pi.provider_payment_intent_id = 'ext_pi_123456'
  LIMIT 1
),
webhook AS (
  INSERT INTO payments.payment_webhook_events
    (tenant_id, store_id, provider_id, event_id, event_type, signature, payload, process_status)
  SELECT
    ctx.tenant_id, ctx.store_id, provider.provider_id,
    'evt_98765',
    'payment.succeeded',
    'sig_xxx',
    jsonb_build_object('provider_payment_intent_id','ext_pi_123456','status','succeeded','amount', intent.amount),
    'received'
  FROM ctx, provider, intent
  ON CONFLICT (provider_id, event_id) DO NOTHING
  RETURNING webhook_event_id
),
update_intent AS (
  UPDATE payments.payment_intents
  SET status = 'succeeded', updated_at = now()
  WHERE payment_intent_id = (SELECT payment_intent_id FROM intent)
  RETURNING payment_intent_id
),
capture_tx AS (
  INSERT INTO payments.payment_transactions
    (tenant_id, store_id, payment_intent_id, tx_type, status, amount, currency, provider_tx_id, raw_response)
  SELECT
    ctx.tenant_id, ctx.store_id,
    (SELECT payment_intent_id FROM intent),
    'capture',
    'succeeded',
    (SELECT amount FROM intent),
    'IDR',
    'ext_tx_capture_001',
    '{"captured":true}'::jsonb
  FROM ctx
  RETURNING payment_tx_id
),
mark_order_paid AS (
  UPDATE orders.orders
  SET payment_status = 'paid', status = 'confirmed', updated_at = now()
  WHERE order_id = (SELECT order_id FROM intent)
  RETURNING order_id
),
mark_webhook_processed AS (
  UPDATE payments.payment_webhook_events
  SET process_status = 'processed', processed_at = now()
  WHERE webhook_event_id = (SELECT webhook_event_id FROM webhook)
)
SELECT
  (SELECT order_id FROM mark_order_paid) AS paid_order_id,
  (SELECT payment_tx_id FROM capture_tx) AS capture_tx_id;

COMMIT;
