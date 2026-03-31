-- MART ACTION BOARD — The final table for Power BI
-- Every SKU, every branch, with action tags and all key metrics
-- This is what the business owner sees on the dashboard

with velocity as (

    -- brings in all items with velocity and supply metrics
    select * from {{ ref('int_inventory_velocity') }}

),

dead_stock_scored as (

    -- brings in dead stock scores and liquidation info
    select
        company_name,
        stock_no,
        dead_stock_score,
        days_since_last_sold,
        monthly_opportunity_cost,
        liquidation_floor

    from {{ ref('int_dead_stock_scored') }}

),

transfer_opportunities as (

    -- brings in transfer recommendations
    select
        stock_no,
        needing_branch,
        giving_branch,
        transfer_priority_score

    from {{ ref('int_transfer_opportunities') }}

),

-- Step 1: join velocity with dead stock scores
-- left join = keep all velocity rows, attach score if available
enriched as (

    select
        v.company_name,
        v.stock_no,
        v.item_description,
        v.product,
        v.brand,
        v.style,
        v.shade,
        v.size,
        v.retail_price,
        v.closing_bal_qty,
        v.closing_bal_value,
        v.sales_qty,
        v.sales_value,
        v.daily_velocity,
        v.days_of_supply,
        v.capital_locked,
        v.total_days,

        -- from dead stock scored (will be null for stockout items)
        d.dead_stock_score,
        d.days_since_last_sold,
        d.monthly_opportunity_cost,
        d.liquidation_floor,

        -- GROSS MARGIN % = profit margin on each item
        -- (selling price - cost price) / selling price × 100
        round(
            safe_divide(
                (v.retail_price - safe_divide(v.closing_bal_value, nullif(v.closing_bal_qty, 0))),
                v.retail_price
            ) * 100
        , 2) as gross_margin_pct,

        -- LOST REVENUE (for stockout items only)
        -- if out of stock, how much revenue are we losing per day?
        -- lost revenue = daily velocity × retail price × total days out of stock
        case
            when v.closing_bal_qty = 0 and v.daily_velocity > 0
            then round(v.daily_velocity * v.retail_price * v.total_days, 2)
            else 0
        end as lost_revenue_estimate

    from velocity v
    left join dead_stock_scored d
        on v.company_name = d.company_name
        and v.stock_no = d.stock_no

),

-- Step 2: attach transfer opportunity info
with_transfers as (

    select
        e.*,

        -- is this branch a NEEDING branch in any transfer opportunity?
        t_need.giving_branch      as transfer_from_branch,
        t_need.transfer_priority_score,

        -- is this branch a GIVING branch in any transfer opportunity?
        t_give.needing_branch     as transfer_to_branch

    from enriched e

    -- attach where this branch needs stock
    left join transfer_opportunities t_need
        on e.company_name = t_need.needing_branch
        and e.stock_no = t_need.stock_no

    -- attach where this branch has excess stock
    left join transfer_opportunities t_give
        on e.company_name = t_give.giving_branch
        and e.stock_no = t_give.stock_no

),

-- Step 3: assign ACTION TAGS
-- this is the core business logic — what should we do with each item?
final as (

    select
        *,

        -- ACTION TAG logic (order matters — transfer checked before reorder)
        case
            -- TRANSFER: out of stock but another branch has it
            when closing_bal_qty = 0
             and sales_qty > 0
             and transfer_from_branch is not null
            then 'Transfer'

            -- REORDER: out of stock, was selling, no transfer available
            when closing_bal_qty = 0
             and sales_qty > 0
            then 'Reorder'

            -- LIQUIDATE: has stock, zero sales
            when closing_bal_qty > 0
             and sales_qty = 0
            then 'Liquidate'

            -- HEALTHY: has stock and is selling
            when closing_bal_qty > 0
             and sales_qty > 0
            then 'Healthy'

            -- fallback for any edge case
            else 'Review'

        end as action_tag,

        -- ACTION PRIORITY (for sorting in Power BI)
        -- 1 = most urgent, 4 = least urgent
        case
            when closing_bal_qty = 0 and sales_qty > 0 and transfer_from_branch is not null then 1
            when closing_bal_qty = 0 and sales_qty > 0 then 1
            when closing_bal_qty > 0 and sales_qty = 0 then 2
            when closing_bal_qty > 0 and sales_qty > 0 then 4
            else 3
        end as action_priority,


        -- REPORT DATE — when was this data generated
        current_date() as report_date,

        -- BRANCH TYPE — classify each branch
        case
            when company_name = 'SITARAM AND SONS -HO'        
            then 'Head Office'
            when company_name in (
                'SITARAM AND SONS',
                'SITARAMS',
                'SITARAM SHANKAR LAL',
                'SITARAM SHYAM SUNDER'
            )                                                  
            then 'Active Branch'
            else 'Inactive'
        end as branch_type,

        -- IS ACTIVE — simple true/false for easy filtering in Power BI
        case
            when company_name in (
                'SITARAM AND SONS -HO',
                'SITARAM AND SONS',
                'SITARAMS',
                'SITARAM SHANKAR LAL',
                'SITARAM SHYAM SUNDER'
            ) then true
            else false
        end as is_active

    from with_transfers

)

select * from final