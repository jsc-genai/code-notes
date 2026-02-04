-- =========================
-- 04 - INVENTORY SEED (RECEIPT)
-- =========================
WITH ctx AS (
  SELECT
    t.tenant_id,
    s.store_id,
    w.warehouse_id,
    v.variant_id
  FROM master.tenants t
  JOIN master.stores s ON s.tenant_id = t.tenant_id
  JOIN inventory.warehouses w ON w.store_id = s.store_id
  JOIN catalog.products p ON p.store_id = s.store_id AND p.sku = 'SKU-HEADPHONE-001'
  JOIN catalog.product_variants v ON v.product_id = p.product_id AND v.variant_sku = 'SKU-HEADPHONE-001-BLK'
  WHERE t.tenant_code = 'TENANT-ACME' AND s.store_code = 'STORE-JKT-01' AND w.code = 'WH-01'
),
upsert_level AS (
  INSERT INTO inventory.stock_levels (tenant_id, store_id, warehouse_id, variant_id, on_hand, reserved, updated_at)
  SELECT tenant_id, store_id, warehouse_id, variant_id, 50, 0, now()
  FROM ctx
  ON CONFLICT (store_id, warehouse_id, variant_id)
  DO UPDATE SET on_hand = EXCLUDED.on_hand, reserved = EXCLUDED.reserved, updated_at = now()
  RETURNING store_id
),
movement AS (
  INSERT INTO inventory.stock_movements
    (tenant_id, store_id, warehouse_id, variant_id, movement_type, quantity, reference_type, reference_id, note)
  SELECT tenant_id, store_id, warehouse_id, variant_id,
         'receipt', 50, 'seed', NULL, 'Initial stock receipt'
  FROM ctx
  RETURNING movement_id
)
SELECT (SELECT movement_id FROM movement) AS receipt_movement_id;
