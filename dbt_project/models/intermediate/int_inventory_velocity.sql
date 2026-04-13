-- models/intermediate/int_inventory_velocity_v3.sql
-- Purpose : THE definitive velocity model. Uses actual sales transactions
--           (not purchases, not movement summaries) to calculate how fast
--           each item sells at each branch.
--
--           v1 = purchase-based (old, inaccurate)
--           v2 = movement summary outwards_qty (better)
--           v3 = actual sales lines (most accurate — retire v1 and v2 after confirming)
--
-- Key metric: units_sold_per_day — the heartbeat of inventory intelligence.

with sales as (

    select * from {{ ref('stg_sales') }}

),

-- Aggregate to SKU × branch level
sku_branch as (

    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,

        -- Volume
        sum(sales_qty)                              as total_units_sold,
        sum(line_revenue)                           as total_revenue,
        sum(full_mrp_value)                         as total_mrp_value,
        sum(discount_given)                         as total_discount,

        -- Time span
        min(sale_date)                              as first_sale_date,
        max(sale_date)                              as last_sale_date,
        count(distinct sale_date)                   as days_with_sales,
        count(distinct voucher_no)                  as num_bills,

        -- B2B split
        sum(case when is_b2b then sales_qty else 0 end)     as b2b_units,
        sum(case when is_b2b then line_revenue else 0 end)  as b2b_revenue,
        sum(case when not is_b2b then sales_qty else 0 end) as retail_units,
        sum(case when not is_b2b then line_revenue else 0 end) as retail_revenue,

        -- Avg selling price (net_amount / qty — reflects actual discounts)
        round(
            sum(line_revenue) / nullif(sum(sales_qty), 0)
        , 2)                                        as avg_selling_price,

        -- Avg discount %
        round(
            sum(discount_given) / nullif(sum(full_mrp_value), 0) * 100
        , 2)                                        as avg_discount_pct

    from sales
    group by 1, 2, 3, 4, 5

),

-- Calculate velocity (units per day over the active selling period)
velocity as (

    select
        *,

        -- Days the item has been in the system (first sale to today)
        date_diff(current_date(), first_sale_date, day) as days_since_first_sale,

        -- Days between first and last sale
        date_diff(last_sale_date, first_sale_date, day) + 1 as selling_period_days,

        -- Units sold per day (over full selling period)
        round(
            total_units_sold /
            nullif(date_diff(last_sale_date, first_sale_date, day) + 1, 0)
        , 4)                                        as units_per_day,

        -- Revenue per day
        round(
            total_revenue /
            nullif(date_diff(last_sale_date, first_sale_date, day) + 1, 0)
        , 2)                                        as revenue_per_day

    from sku_branch

),

-- Assign velocity tier and reorder signals
final as (

    select
        *,

        -- Velocity tier
        case
            when units_per_day >= 1.0  then 'Fast mover'    -- sells 1+ unit/day
            when units_per_day >= 0.1  then 'Medium mover'  -- sells 1 unit per ~10 days
            when units_per_day >  0    then 'Slow mover'    -- sells occasionally
            else                            'No sales'
        end as velocity_tier,

        -- Days of stock remaining at current sell rate
        -- (requires stock_balance — joined in mart layer)
        null as days_of_stock_remaining   -- placeholder, joined in mart_action_board_v2

    from velocity

)

select * from final