-- do with other data
-- delivered update + tracking event
WITH ctx AS (
  SELECT t.tenant_id
  FROM master.tenants t
  WHERE t.tenant_code = 'TENANT-ACME'
),
sh AS (
  SELECT shipment_id
  FROM shipping.shipments
  WHERE tracking_number = 'TRK-ACME-0001'
)
UPDATE shipping.shipments
SET status = 'delivered', delivered_at = now(), updated_at = now()
WHERE shipment_id = (SELECT shipment_id FROM sh);

INSERT INTO shipping.tracking_events
  (tenant_id, shipment_id, status_code, description, location, event_time, raw_payload)
SELECT
  (SELECT tenant_id FROM ctx),
  (SELECT shipment_id FROM sh),
  'DELIVERED', 'Delivered to customer', 'Tangerang Selatan', now(),
  '{}'::jsonb;
