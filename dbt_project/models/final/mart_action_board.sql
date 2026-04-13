-- models/final/mart_action_board_v2.sql
-- Purpose : UPGRADED action board using real sales velocity.
--           Power BI reads this for the "Dead Stock + Branch Performance" page.
--
-- FIXES APPLIED:
--   1. Removed dependency on stg_dead_stock entirely.
--      Reason: dead_stock export is outdated — 9,322 items in it also
--      have real sales, making it unreliable. stg_stock_movement already
--      provides movement_status = 'Stagnant' which is more accurate and current.
--
--   2. Action tag 'Liquidate' now based purely on movement data:
--      stock sitting + zero outward movement = confirmed stagnant.
--      No need for the old dead_stock report.
--
-- Action tags:
--   Reorder              → fast mover, less than 7 days stock remaining
--   Watch — high discount→ selling but giving away too much margin
--   Transfer             → slow here, fast at another branch
--   Liquidate            → zero outward movement, stock confirmed sitting
--   Healthy              → selling well, good margin, good stock level
--   Monitor              → has some sales but slow velocity
--   Review               → everything else

with velocity as (

    select * from {{ ref('int_inventory_velocity') }}

),

balance as (

    select * from {{ ref('stg_stock_balance') }}

),

movement as (

    select * from {{ ref('stg_stock_movement') }}

),

-- Cross-branch sales: find which branch sells each item fastest
-- Used to identify transfer opportunities
cross_branch_velocity as (

    select
        stock_no,
        max(case when velocity_tier = 'Fast mover' then company_name end)
                                        as fast_at_branch,
        count(distinct company_name)    as branches_selling,
        sum(total_units_sold)           as total_units_all_branches,
        sum(total_revenue)              as total_revenue_all_branches
    from velocity
    group by stock_no

),

action as (

    select
        -- Identity
        b.company_name,
        b.stock_no,
        b.item_description,
        b.product,
        b.brand,
        b.supplier_name,

        -- Pricing
        b.cost_price,
        b.retail_price,
        b.margin_pct,

        -- Current stock (from balance report — most accurate snapshot)
        b.closing_qty                   as stock_on_hand,
        b.capital_locked,
        b.retail_value                  as stock_retail_value,
        b.stock_value_bucket,

        -- Sales velocity (from real transactions)
        v.total_units_sold,
        v.total_revenue,
        v.units_per_day,
        v.velocity_tier,
        v.avg_discount_pct,
        v.first_sale_date,
        v.last_sale_date,
        v.days_with_sales,
        v.num_bills                     as bills_containing_item,

        -- Days of stock remaining at current sell rate
        -- e.g. 30 units in stock, selling 2/day = 15 days left
        round(
            b.closing_qty / nullif(v.units_per_day, 0)
        , 0)                            as days_of_stock_remaining,

        -- Cross-branch context
        cb.branches_selling,
        cb.fast_at_branch,
        cb.total_units_all_branches,
        cb.total_revenue_all_branches,

        -- Movement data (replaces dead_stock report)
        m.movement_status,              -- Stagnant / Fully sold / Partially sold
        m.sell_through_pct,
        m.inwards_qty,
        m.outwards_qty,

        -- ── ACTION TAG — based on movement + sales + stock ───────────────
        case
            -- REORDER: real sales, fast mover, stock running low
            when v.velocity_tier = 'Fast mover'
             and b.closing_qty <= coalesce(v.units_per_day * 7, 5)
            then 'Reorder'

            -- WATCH: selling but giving heavy discounts — margin leakage
            when v.total_units_sold > 0
             and coalesce(v.avg_discount_pct, 0) > 15
            then 'Watch — high discount'

            -- TRANSFER: slow/no sales here, but another branch sells it fast
            when coalesce(v.velocity_tier, 'No sales') in ('Slow mover', 'No sales')
             and b.closing_qty > 0
             and cb.fast_at_branch is not null
             and cb.fast_at_branch != b.company_name
            then 'Transfer'

            -- LIQUIDATE: zero outward movement confirmed by movement report
            -- Does NOT rely on old dead_stock export
            when (v.total_units_sold is null or v.total_units_sold = 0)
             and b.closing_qty > 0
             and m.movement_status = 'Stagnant'
            then 'Liquidate'

            -- HEALTHY: selling well, good margin, enough stock (>7 days)
            when v.velocity_tier in ('Fast mover', 'Medium mover')
             and b.margin_pct >= 20
             and b.closing_qty > coalesce(v.units_per_day * 7, 0)
            then 'Healthy'

            -- MONITOR: has sales but slow velocity
            when v.total_units_sold > 0
            then 'Monitor'

            -- REVIEW: in stock but no movement data at all
            else 'Review'

        end                             as action_tag

    from balance b
    left join velocity v
        on  b.stock_no     = v.stock_no
        and b.company_name = v.company_name
    left join movement m
        on  b.stock_no     = m.stock_no
        and b.company_name = m.company_name
    left join cross_branch_velocity cb
        on  b.stock_no     = cb.stock_no

)

select * from action
order by capital_locked desc