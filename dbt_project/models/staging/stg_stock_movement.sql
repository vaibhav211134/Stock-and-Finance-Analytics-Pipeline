-- models/staging/stg_stock_movement.sql
-- Source: raw.stock_movement (from stockmovementreport.csv)
-- Purpose: Item-level stock movement — opening, inwards, outwards, closing.
--          This covers the full period the report was exported for.
--          KEY INSIGHT: Opening Bal = 0 for all rows, meaning this report
--          starts from scratch (likely from when QuickBill was first set up).
--          Inwards = all stock that came in. Outwards = all stock that left.

with source as (

    select * from {{ source('raw', 'stock_movement') }}

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
        cast(shade as string)  as shade,
        cast(size as string)   as size,
        hsn_code,
        supplier_name,

        -- Pricing
        cost_price,
        retail_price,
        margin_pct,
        base_uom,

        -- Movement (the core of this table)
        opening_qty,
        opening_val,
        inwards_qty,
        outwards_qty,
        closing_qty,
        closing_val,

        -- Derived
        sell_through_pct,
        capital_locked,
        retail_value_closing,
        movement_status,

        -- Speed tier based on sell-through
        case
            when sell_through_pct >= 80  then 'Fast mover'
            when sell_through_pct >= 40  then 'Medium mover'
            when sell_through_pct >  0   then 'Slow mover'
            when inwards_qty > 0
             and outwards_qty = 0
             and closing_qty > 0         then 'No movement'
            else                              'Other'
        end as velocity_tier,

        -- How much capital is stuck in non-moving items
        case
            when movement_status = 'Stagnant'
            then capital_locked
            else 0
        end as stagnant_capital

    from source

)

select * from cleaned