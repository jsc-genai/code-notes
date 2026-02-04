-- =======================================
-- 07 - PAYMENT FLOW (GENERIC PROVIDER)
-- =======================================
WITH ctx AS (
  SELECT t.tenant_id, s.store_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  WHERE t.tenant_code = 'TENANT-ACME' AND s.store_code = 'STORE-JKT-01'
),
target_order AS (
  SELECT o.order_id, o.total_amount
  FROM orders.orders o
  JOIN ctx ON ctx.store_id = o.store_id
  WHERE o.order_number = 'ORD-2026-000001'
),
provider AS (
  INSERT INTO payments.payment_providers
    (tenant_id, store_id, provider_code, display_name, environment, is_active, config)
  SELECT
    ctx.tenant_id, ctx.store_id,
    'generic_gateway', 'Generic Gateway', 'sandbox', true,
    '{"webhook_url":"https://api.example.com/payments/webhook","supported":["card","va","ewallet"]}'::jsonb
  FROM ctx
  ON CONFLICT (tenant_id, store_id, provider_code) DO UPDATE SET is_active = true
  RETURNING provider_id
),
intent AS (
  INSERT INTO payments.payment_intents
    (tenant_id, store_id, order_id, provider_id, amount, currency, status, capture_method,
     idempotency_key, provider_payment_intent_id, redirect_url, meta)
  SELECT
    ctx.tenant_id, ctx.store_id,
    target_order.order_id,
    provider.provider_id,
    target_order.total_amount,
    'IDR',
    'requires_payment',
    'automatic',
    'idem-ORD-2026-000001-001',
    'ext_pi_123456',
    'https://pay.example.com/redirect/ext_pi_123456',
    '{"method":"ewallet"}'::jsonb
  FROM ctx, target_order, provider
  ON CONFLICT (tenant_id, store_id, provider_id, idempotency_key) DO UPDATE
    SET updated_at = now()
  RETURNING payment_intent_id, provider_id
),
tx_pending AS (
  INSERT INTO payments.payment_transactions
    (tenant_id, store_id, payment_intent_id, tx_type, status, amount, currency, provider_tx_id, raw_response)
  SELECT
    ctx.tenant_id, ctx.store_id,
    intent.payment_intent_id,
    'charge',
    'pending',
    target_order.total_amount,
    'IDR',
    'ext_tx_pending_001',
    '{"message":"waiting payment"}'::jsonb
  FROM ctx, target_order, intent
  RETURNING payment_tx_id
)
SELECT
  (SELECT payment_intent_id FROM intent) AS payment_intent_id,
  (SELECT payment_tx_id FROM tx_pending) AS pending_tx_id;
