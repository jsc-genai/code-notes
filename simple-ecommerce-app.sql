CREATE DATABASE ecommerce_app WITH ENCODING = 'UTF8' LC_COLLATE = 'en_US.utf8' LC_CTYPE = 'en_US.utf8' TEMPLATE = template0;
-- for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- case-insensitive email
CREATE EXTENSION IF NOT EXISTS citext;
-- optional: better text search / LIKE performance
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SCHEMA IF NOT EXISTS master;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS sales;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE TABLE master.stores (
    store_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_code text NOT NULL UNIQUE,
    store_name text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    -- active|inactive
    timezone text NOT NULL DEFAULT 'Asia/Jakarta',
    default_currency char(3) NOT NULL DEFAULT 'IDR',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_stores_status ON master.stores(status);
CREATE TABLE master.store_addresses (
    address_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    label text NOT NULL DEFAULT 'main',
    line1 text NOT NULL,
    line2 text,
    city text,
    province text,
    postal_code text,
    country char(2) NOT NULL DEFAULT 'ID',
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_store_addresses_store_id ON master.store_addresses(store_id);
CREATE TABLE auth.users (
    user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NULL REFERENCES master.stores(store_id) ON DELETE
    SET NULL,
        -- optional default store
        email citext NOT NULL UNIQUE,
        phone text,
        password_hash text NOT NULL,
        display_name text,
        is_active boolean NOT NULL DEFAULT true,
        email_verified_at timestamptz,
        last_login_at timestamptz,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
);
-- common API: login by email, active users
CREATE INDEX idx_users_active ON auth.users(is_active) WHERE is_active = true;
CREATE TABLE auth.sessions (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(user_id) ON DELETE CASCADE,
    refresh_token_hash text NOT NULL UNIQUE,
    ip_address inet,
    user_agent text,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz
);
CREATE INDEX idx_sessions_user_id ON auth.sessions(user_id);
CREATE INDEX idx_sessions_valid ON auth.sessions(user_id, expires_at) WHERE revoked_at IS NULL;
CREATE TABLE auth.roles (
    role_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    role_code text NOT NULL UNIQUE,
    -- e.g. admin, cashier, manager
    role_name text NOT NULL,
    description text,
    is_system boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE auth.resources (
    resource_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type text NOT NULL,
    -- 'page' | 'menu' | 'api_route'
    resource_key text NOT NULL,
    -- unique key e.g. 'product.list', 'menu.catalog'
    path text,
    -- for routes: '/api/products'
    meta jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (resource_type, resource_key)
);
CREATE INDEX idx_resources_type_key ON auth.resources(resource_type, resource_key);
CREATE INDEX idx_resources_meta_gin ON auth.resources USING GIN (meta);
-- optional text search for path/key
CREATE INDEX idx_resources_path_trgm ON auth.resources USING GIN (path gin_trgm_ops);
CREATE TABLE auth.permissions (
    permission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_code text NOT NULL UNIQUE,
    -- e.g. 'catalog.product.read'
    resource_id uuid NOT NULL REFERENCES auth.resources(resource_id) ON DELETE CASCADE,
    action text NOT NULL,
    -- 'read' | 'write' | 'delete' | 'view'
    description text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (resource_id, action)
);
CREATE INDEX idx_permissions_resource_action ON auth.permissions(resource_id, action);
CREATE TABLE auth.role_permissions (
    role_id uuid NOT NULL REFERENCES auth.roles(role_id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES auth.permissions(permission_id) ON DELETE CASCADE,
    effect text NOT NULL DEFAULT 'allow',
    -- allow|deny (optional)
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX idx_role_permissions_permission ON auth.role_permissions(permission_id);
CREATE TABLE auth.user_roles (
    user_id uuid NOT NULL REFERENCES auth.users(user_id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES auth.roles(role_id) ON DELETE CASCADE,
    store_id uuid NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    -- NULL = global
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id, store_id)
);
CREATE INDEX idx_user_roles_user ON auth.user_roles(user_id);
CREATE INDEX idx_user_roles_store ON auth.user_roles(store_id);
CREATE TABLE auth.api_routes (
    api_route_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id uuid NOT NULL UNIQUE REFERENCES auth.resources(resource_id) ON DELETE CASCADE,
    http_method text NOT NULL,
    -- GET/POST/PUT/DELETE
    path_pattern text NOT NULL,
    -- /api/products/:id
    is_public boolean NOT NULL DEFAULT false
);
CREATE INDEX idx_api_routes_method_path ON auth.api_routes(http_method, path_pattern);
CREATE TABLE auth.pages (
    page_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id uuid NOT NULL UNIQUE REFERENCES auth.resources(resource_id) ON DELETE CASCADE,
    page_title text NOT NULL,
    route_key text,
    -- optional, FE route name
    sort_order int NOT NULL DEFAULT 0
);
CREATE INDEX idx_pages_sort ON auth.pages(sort_order);
CREATE TABLE auth.menus (
    menu_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id uuid NOT NULL UNIQUE REFERENCES auth.resources(resource_id) ON DELETE CASCADE,
    parent_menu_id uuid NULL REFERENCES auth.menus(menu_id) ON DELETE CASCADE,
    label text NOT NULL,
    icon text,
    sort_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX idx_menus_parent ON auth.menus(parent_menu_id);
CREATE INDEX idx_menus_active ON auth.menus(is_active) WHERE is_active = true;
CREATE TABLE catalog.categories (
    category_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    parent_id uuid NULL REFERENCES catalog.categories(category_id) ON DELETE
    SET NULL,
        name text NOT NULL,
        slug text NOT NULL,
        sort_order int NOT NULL DEFAULT 0,
        is_active boolean NOT NULL DEFAULT true,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now(),
        UNIQUE (store_id, slug)
);
CREATE INDEX idx_categories_store_parent ON catalog.categories(store_id, parent_id);
CREATE INDEX idx_categories_active ON catalog.categories(store_id, is_active) WHERE is_active = true;
CREATE TABLE catalog.products (
    product_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    category_id uuid NULL REFERENCES catalog.categories(category_id) ON DELETE
    SET NULL,
        sku text NOT NULL,
        name text NOT NULL,
        slug text NOT NULL,
        description text,
        status text NOT NULL DEFAULT 'active',
        -- active|draft|archived
        price numeric(12, 2) NOT NULL DEFAULT 0,
        currency char(3) NOT NULL DEFAULT 'IDR',
        attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
        -- flexible attributes
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now(),
        UNIQUE (store_id, sku),
        UNIQUE (store_id, slug)
);
-- Common API filters: store + status + created_at (listing), store + category, slug
CREATE INDEX idx_products_store_status_created ON catalog.products(store_id, status, created_at DESC);
CREATE INDEX idx_products_store_category ON catalog.products(store_id, category_id);
CREATE INDEX idx_products_attr_gin ON catalog.products USING GIN (attributes);
CREATE TABLE catalog.product_variants (
    variant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES catalog.products(product_id) ON DELETE CASCADE,
    variant_sku text NOT NULL,
    name text,
    -- e.g. "Red / XL"
    price numeric(12, 2) NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, variant_sku)
);
CREATE INDEX idx_variants_product ON catalog.product_variants(product_id);
CREATE INDEX idx_variants_active ON catalog.product_variants(is_active) WHERE is_active = true;
CREATE TABLE catalog.product_images (
    image_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES catalog.products(product_id) ON DELETE CASCADE,
    url text NOT NULL,
    alt_text text,
    sort_order int NOT NULL DEFAULT 0
);
CREATE INDEX idx_product_images_product_sort ON catalog.product_images(product_id, sort_order);
CREATE TABLE sales.carts (
    cart_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    user_id uuid NULL REFERENCES auth.users(user_id) ON DELETE
    SET NULL,
        status text NOT NULL DEFAULT 'active',
        -- active|abandoned|converted
        currency char(3) NOT NULL DEFAULT 'IDR',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now(),
        expires_at timestamptz
);
-- Fast "get my active cart"
CREATE INDEX idx_carts_active_by_user ON sales.carts(user_id, updated_at DESC) WHERE status = 'active' AND user_id IS NOT NULL;
CREATE INDEX idx_carts_store_status ON sales.carts(store_id, status, updated_at DESC);
create table sales.cart_items (
    cart_item_id uuid primary key default gen_random_uuid(),
    cart_id uuid not null references sales.carts(cart_id) on
delete
	cascade,
	variant_id uuid not null references catalog.product_variants(variant_id) on
	delete
		restrict,
		quantity int not null check (quantity > 0),
		unit_price numeric(12, 2) not null,
		created_at timestamptz not null default now(),
		unique (cart_id,
		variant_id)
);
CREATE INDEX idx_cart_items_cart ON sales.cart_items(cart_id);
CREATE INDEX idx_cart_items_variant ON sales.cart_items(variant_id);
CREATE TABLE inventory.warehouses (
    warehouse_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    code text NOT NULL,
    name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (store_id, code)
);
CREATE INDEX idx_warehouses_store_active ON inventory.warehouses(store_id, is_active) WHERE is_active = true;
CREATE TABLE inventory.stock_levels (
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    warehouse_id uuid NOT NULL REFERENCES inventory.warehouses(warehouse_id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES catalog.product_variants(variant_id) ON DELETE CASCADE,
    on_hand int NOT NULL DEFAULT 0,
    reserved int NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (store_id, warehouse_id, variant_id),
    CHECK (on_hand >= 0),
    CHECK (reserved >= 0)
);
-- inventory check by variant is common
CREATE INDEX idx_stock_levels_variant ON inventory.stock_levels(variant_id);
CREATE TABLE inventory.stock_movements (
    movement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL REFERENCES master.stores(store_id) ON DELETE CASCADE,
    warehouse_id uuid NOT NULL REFERENCES inventory.warehouses(warehouse_id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES catalog.product_variants(variant_id) ON DELETE CASCADE,
    movement_type text NOT NULL,
    -- receipt|sale|adjustment|transfer_in|transfer_out|reserve|release
    quantity int NOT NULL,
    -- signed (+in, -out)
    reference_type text,
    -- e.g. 'order','purchase','manual'
    reference_id uuid,
    -- points to order_id etc
    note text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_stock_movements_variant_time ON inventory.stock_movements(variant_id, created_at DESC);
CREATE INDEX idx_stock_movements_store_time ON inventory.stock_movements(store_id, created_at DESC);
