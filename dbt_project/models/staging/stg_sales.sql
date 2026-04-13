-- models/staging/stg_sales.sql
-- Source : raw.sales  (inventory_transaction_sales_report.csv)
-- Purpose: Item-level sales transactions — every line on every bill.
--
-- FIXES APPLIED:
--   1. Deduplication — 152 voucher_no+stock_no+date combos appear >1 time.
--      Root cause: QuickBill split lines or double entry.
--      Fix: keep only the first occurrence per voucher_no+stock_no+sale_date.
--      This removes ~1870 duplicate rows cleanly without losing real data.
--
--   2. sale_date cast — uploaded as STRING, cast to DATE here for all
--      downstream date operations.

with source as (

    select * from {{ source('raw', 'sales') }}

),

-- Step 1: cast types and rename
cast_types as (

    select
        CASE 
            WHEN company_name = 'SITARAM SHANKAR LAL-old'  THEN 'SITARAM SHANKAR LAL'
            WHEN company_name = 'SITARAM SHYAM SUNDER-old' THEN 'SITARAM SHYAM SUNDER'
            WHEN company_name = 'SITARAM\'S-old'            THEN 'SITARAMS'
            ELSE company_name
        END AS company_name,
        voucher_type,
        cast(sale_date as date)     as sale_date,
        voucher_no,
        customer_ref,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        base_uom,
        retail_price,
        sales_qty,
        line_revenue,
        full_mrp_value,
        discount_given,
        discount_pct,
        is_b2b,
        sale_year,
        sale_month,
        sale_month_name,
        sale_quarter,
        sale_week,
        sale_dow

    from source

),

-- Step 2: deduplicate — assign row number per voucher+stock+date
-- Keep row_num = 1 only (first occurrence)
deduped as (

    select
        *,
        row_number() over (
            partition by company_name, voucher_no, stock_no, sale_date
            order by line_revenue desc   -- keep the higher-value line if they differ
        ) as row_num

    from cast_types

),

-- Step 3: final clean output — only unique rows
cleaned as (

    select
        company_name,
        voucher_type,
        sale_date,
        voucher_no,
        customer_ref,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        base_uom,
        retail_price,
        sales_qty,
        line_revenue,
        full_mrp_value,
        discount_given,
        discount_pct,
        is_b2b,
        sale_year,
        sale_month,
        sale_month_name,
        sale_quarter,
        sale_week,
        sale_dow

    from deduped
    where row_num = 1

)

select * from cleaned