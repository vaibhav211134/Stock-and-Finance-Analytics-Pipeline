-- models/staging/stg_sales_returns.sql
-- Source : raw.sales_returns  (inventory_transaction_report_sales_return.csv)
-- Purpose: Every item returned by a customer after sale.
--          2,882 active branch rows.
--          Rs 38.75 Lakh returned (3.47% of sales revenue).
--          Unit return rate: 2.09% — within normal retail range.
--
-- NOTE: Column names match exactly what clean_sales_returns.py uploads.
--       return_date, return_value, customer_ref are already renamed in BigQuery.
--       return_qty capped at sold qty via GREATEST(0,...) in int_net_sales.

with source as (

    select * from {{ source('raw', 'sales_returns') }}

),

cleaned as (

    select
        -- Bill identity
        CASE 
            WHEN company_name = 'SITARAM SHANKAR LAL-old'  THEN 'SITARAM SHANKAR LAL'
            WHEN company_name = 'SITARAM SHYAM SUNDER-old' THEN 'SITARAM SHYAM SUNDER'
            WHEN company_name = 'SITARAM\'S-old'            THEN 'SITARAMS'
            ELSE company_name
        END AS company_name,
        voucher_type,
        cast(return_date as date)   as return_date,
        voucher_no,
        customer_ref,

        -- Item identity
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        base_uom,

        -- Financials
        retail_price,
        return_qty,
        return_value,
        return_value_per_unit,

        -- Flags
        has_customer_name,

        -- Date parts
        return_year,
        return_month,
        return_month_name,
        return_quarter

    from source

)

select * from cleaned