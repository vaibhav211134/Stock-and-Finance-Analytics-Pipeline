-- This model calculates how fast each item sells per branch
-- It combines stockout + dead_stock + healthy items for complete picture
-- Key output: daily_velocity, days_of_supply, capital_locked

with purchases as (

    -- get the date range from purchases
    select
        min(voucher_date) as first_date,
        max(voucher_date) as last_date,
        date_diff(max(voucher_date), min(voucher_date), day) as total_days

    from {{ ref('stg_purchases') }}

),

stockouts as (

    -- items that were selling but ran out of stock
    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        retail_price,
        closing_bal_qty,        -- will be 0 (out of stock)
        sales_qty,              -- how many sold
        sales_value,            -- revenue generated
        0.0 as closing_bal_value

    from {{ ref('stg_stockouts') }}

),

dead_stock as (

    -- items that have stock but nobody is buying
    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        retail_price,
        closing_bal_qty,        -- stock sitting unsold
        0 as sales_qty,         -- no sales
        0.0 as sales_value,     -- no revenue
        closing_bal_value       -- capital locked

    from {{ ref('stg_dead_stock') }}

),

healthy as (

    -- items that have stock AND are selling
    -- we estimate their metrics from purchase data
    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        retail_price,

        -- we dont have exact closing qty for healthy items
        -- using total purchased as proxy (they have stock since not in stockout)
        total_purchase_qty      as closing_bal_qty,

        -- estimate sales as portion of purchases (they are selling)
        -- since not in stockout they have remaining stock
        -- we use purchase qty as upper bound
        total_purchase_qty      as sales_qty,

        -- estimated sales value
        total_purchase_value    as sales_value,

        -- estimated capital locked
        total_purchase_value    as closing_bal_value

    from {{ ref('stg_healthy_items') }}

),

-- stack all 3 sources together
combined as (

    select * from stockouts
    union all
    select * from dead_stock
    union all
    select * from healthy

),

with_velocity as (

    select
        c.company_name,
        c.stock_no,
        c.item_description,
        c.product,
        c.brand,
        c.style,
        c.shade,
        c.size,
        c.retail_price,
        c.closing_bal_qty,
        c.closing_bal_value,
        c.sales_qty,
        c.sales_value,
        p.total_days,

        -- DAILY VELOCITY = pieces sold per day
        round(safe_divide(c.sales_qty, p.total_days), 4) as daily_velocity,

        -- DAYS OF SUPPLY = how long current stock will last
        case
            when safe_divide(c.sales_qty, p.total_days) > 0
            then round(safe_divide(c.closing_bal_qty,
                 safe_divide(c.sales_qty, p.total_days)), 1)
            else null
        end as days_of_supply,

        -- CAPITAL LOCKED = money in unsold inventory
        round(c.closing_bal_value, 2) as capital_locked

    from combined c
    cross join purchases p

)

select * from with_velocity