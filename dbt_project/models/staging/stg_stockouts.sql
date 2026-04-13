-- This model cleans the raw stockout table
-- Stockout = items that have sales but zero closing stock

with source as (

    -- Step 1: pull everything from raw stockout table
    select * from {{ source('raw', 'stockout') }}

),

renamed as (

    select
        -- who and what
        CASE 
            WHEN company_name = 'SITARAM SHANKAR LAL-old'  THEN 'SITARAM SHANKAR LAL'
            WHEN company_name = 'SITARAM SHYAM SUNDER-old' THEN 'SITARAM SHYAM SUNDER'
            WHEN company_name = 'SITARAM\'S-old'            THEN 'SITARAMS'
            ELSE company_name
        END AS company_name,
        stock_no,                                                 -- unique item code
        item_description,                                         -- item name
        product,                                                  -- product category
        brand,                                                    -- brand name
        style,                                                    -- style code
        shade,                                                    -- colour/shade
        size,                                                     -- size

        -- dates
        cast(last_purchase_date as date)  as last_purchase_date,  -- last time purchased
        cast(last_sold_date as date)      as last_sold_date,       -- last time sold (recent)

        -- numbers
        cast(retail_price as float64)     as retail_price,        -- selling price
        cast(closing_bal_qty as int64)    as closing_bal_qty,     -- will be 0 (out of stock)
        cast(sales_qty as int64)          as sales_qty,           -- how many sold
        cast(sales_value as float64)      as sales_value          -- revenue generated

    from source
    where stock_no is not null  -- remove junk rows

)

select * from renamed