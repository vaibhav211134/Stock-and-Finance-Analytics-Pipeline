-- MART BRANCH PERFORMANCE
-- Answers: How is each branch performing?
-- Which branch has most dead stock? Which has most stockouts?
-- Which branch is most efficient?
-- Power BI page: Branch Performance + Executive Summary

with action_board as (

    -- use our already built mart as the base
    -- it has all items with tags for all branches
    select * from {{ ref('mart_action_board') }}

),

-- STEP 1: summarize by branch and action tag
branch_tag_summary as (

    select
        company_name,
        branch_type,
        is_active,
        action_tag,

        -- count of items per tag per branch
        count(*)                                as item_count,

        -- capital locked (only relevant for Liquidate tag)
        round(sum(capital_locked), 2)           as total_capital_locked,

        -- lost revenue (only relevant for Reorder tag)
        round(sum(lost_revenue_estimate), 2)    as total_lost_revenue,

        -- total retail value at risk
        round(sum(retail_price * closing_bal_qty), 2) as total_retail_value

    from action_board
    group by
        company_name,
        branch_type,
        is_active,
        action_tag

),

-- STEP 2: pivot to get one row per branch
-- each action tag becomes its own column
branch_pivoted as (

    select
        company_name,
        branch_type,
        is_active,

        -- TOTAL ITEMS per branch
        sum(item_count)                         as total_items,

        -- LIQUIDATE metrics
        sum(case when action_tag = 'Liquidate'
            then item_count else 0 end)         as liquidate_count,

        sum(case when action_tag = 'Liquidate'
            then total_capital_locked else 0 end) as total_capital_locked,

        -- REORDER metrics
        sum(case when action_tag = 'Reorder'
            then item_count else 0 end)         as reorder_count,

        sum(case when action_tag = 'Reorder'
            then total_lost_revenue else 0 end) as total_lost_revenue,

        -- TRANSFER metrics
        sum(case when action_tag = 'Transfer'
            then item_count else 0 end)         as transfer_count,

        -- HEALTHY metrics
        sum(case when action_tag = 'Healthy'
            then item_count else 0 end)         as healthy_count,

        -- REVIEW metrics
        sum(case when action_tag = 'Review'
            then item_count else 0 end)         as review_count

    from branch_tag_summary
    group by
        company_name,
        branch_type,
        is_active

),

-- STEP 3: calculate efficiency scores per branch
scored as (

    select
        *,

        -- DEAD STOCK RATE = what % of items are dead stock
        -- lower is better
        round(
            safe_divide(liquidate_count, total_items) * 100
        , 2)                                    as dead_stock_rate_pct,

        -- STOCKOUT RATE = what % of items are out of stock
        -- lower is better
        round(
            safe_divide(reorder_count, total_items) * 100
        , 2)                                    as stockout_rate_pct,

        -- OPPORTUNITY COST = monthly cost of capital locked in dead stock
        -- 12% annual = 1% monthly
        round(total_capital_locked * 0.01, 2)   as monthly_opportunity_cost,

        -- BRANCH HEALTH SCORE = overall efficiency score (0-100)
        -- penalize for dead stock and stockouts
        -- higher score = healthier branch
        round(
            100
            - safe_divide(liquidate_count, total_items) * 50  -- dead stock penalty
            - safe_divide(reorder_count, total_items) * 50    -- stockout penalty
        , 2)                                    as branch_health_score,

        -- RANK branches by health score
        rank() over (
            partition by branch_type
            order by (
                100
                - safe_divide(liquidate_count, total_items) * 50
                - safe_divide(reorder_count, total_items) * 50
            ) desc
        )                                       as branch_rank,

        current_date()                          as report_date

    from branch_pivoted

)

select * from scored
order by branch_health_score desc