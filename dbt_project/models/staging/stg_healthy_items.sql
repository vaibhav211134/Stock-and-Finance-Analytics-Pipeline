-- This model finds HEALTHY items from the purchase report
-- Healthy = items that exist in purchases but NOT in dead_stock or stockout
-- These items have stock available AND are selling well
-- QuickBill does not export these separately — we derive them from purchases

with purchases as (

    select * from {{ ref('stg_purchases') }}

),

dead_stock as (

    -- get all stock_no + company combinations that are dead stock
    select distinct
        company_name,
        stock_no
    from {{ ref('stg_dead_stock') }}

),

stockouts as (

    -- get all stock_no + company combinations that are stockouts
    select distinct
        company_name,
        stock_no
    from {{ ref('stg_stockouts') }}

),

-- get latest purchase info per item per branch
-- we use this to get retail price, item rate etc.
purchase_summary as (

    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,

        -- latest retail price for this item
        max(retail_price)     as retail_price,

        -- total quantity purchased
        sum(purchase_qty)     as total_purchase_qty,

        -- total amount spent purchasing this item
        sum(item_net_amount)  as total_purchase_value,

        -- average cost price
        avg(item_rate)        as avg_item_rate,

        -- date range
        min(voucher_date)     as first_purchase_date,
        max(voucher_date)     as last_purchase_date

    from purchases
    group by
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size

),

-- now find items that are NOT in dead_stock AND NOT in stockout
-- these are the healthy items
healthy as (

    select
        p.company_name,
        p.stock_no,
        p.item_description,
        p.product,
        p.brand,
        p.style,
        p.shade,
        p.size,
        p.retail_price,
        p.total_purchase_qty,
        p.total_purchase_value,
        p.avg_item_rate,
        p.first_purchase_date,
        p.last_purchase_date

    from purchase_summary p

    -- exclude items that appear in dead_stock for same branch
    left join dead_stock d
        on p.company_name = d.company_name
        and p.stock_no = d.stock_no

    -- exclude items that appear in stockout for same branch
    left join stockouts s
        on p.company_name = s.company_name
        and p.stock_no = s.stock_no

    -- keep only items not found in either
    where d.stock_no is null
    and s.stock_no is null
    -- exclude Head Office and inactive branches
    -- HO distributes stock, it doesn't sell to customers
    and p.company_name not in (
        'SITARAM AND SONS -HO',
        'SITARAM SHANKAR LAL-old',
        'SITARAM SHYAM SUNDER-old',
        'SITARAM\'S-old'
    )
)

select * from healthy