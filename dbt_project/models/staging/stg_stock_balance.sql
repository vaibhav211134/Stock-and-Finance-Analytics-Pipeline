-- models/staging/stg_stock_balance.sql
-- Source: raw.stock_balance (from stockbalancereport.csv)
-- Purpose: Current stock on hand per item per branch
--          This is the SNAPSHOT of what is physically sitting in each shop right now.

with source as (

    select * from {{ source('raw', 'stock_balance') }}

),

cleaned as (

    select
        -- Identity
        CASE 
            WHEN company_name = 'SITARAM SHANKAR LAL-old'  THEN 'SITARAM SHANKAR LAL'
            WHEN company_name = 'SITARAM SHYAM SUNDER-old' THEN 'SITARAM SHYAM SUNDER'
            WHEN company_name = 'SITARAM\'S-old'            THEN 'SITARAMS'
            ELSE company_name
        END AS company_name,
        stock_no,
        item_description,

        -- Classification
        product,
        brand,
        style,
        cast(shade as string)    as shade,
        cast(size as string)     as size,
        hsn_code,
        item_type,

        -- Supplier
        supplier_name,

        -- Pricing
        cost_price,
        retail_price,
        base_uom,

        -- Stock levels (the core of this table)
        closing_qty,
        closing_rate,
        closing_value      as capital_locked,   -- what was paid for this stock

        -- Derived columns
        margin_pct,
        retail_value,                           -- what stock is worth at MRP

        -- Bucket the stock by value for prioritisation
        case
            when closing_value >= 100000 then 'High value'    -- 1L+
            when closing_value >= 10000  then 'Medium value'  -- 10K–1L
            else                              'Low value'     -- below 10K
        end as stock_value_bucket,

        -- Flag items where cost > retail (data issue or genuine loss)
        case
            when cost_price > retail_price then true
            else false
        end as is_negative_margin

    from source

)

select * from cleaned