-- models/final/mart_branch_performance.sql
-- Purpose: Branch-level comparison — which branch is performing best?
--          Used in Power BI Stock Dashboard — Branch Performance page.
--
-- FIX: Removed reference to branch_type and is_active columns
--      which no longer exist in mart_financials after the rename.
--      Branch classification is now derived from company_name directly.

with financials as (

    select * from {{ ref('mart_financials') }}

),

-- Aggregate financials to branch level (all time)
branch_financials as (

    select
        company_name,

        -- Revenue
        sum(gross_sales)            as total_gross_sales,
        sum(sales_returns)          as total_sales_returns,
        sum(net_sales)              as total_net_sales,

        -- Expenses
        sum(total_expenses)         as total_expenses,
        sum(salary_expense)         as total_salary,
        sum(shop_expense)           as total_shop_expense,
        sum(freight_expense)        as total_freight,

        -- P&L
        sum(net_pnl)                as total_net_pnl,
        round(avg(pnl_margin_pct), 2) as avg_pnl_margin_pct,

        -- Activity
        count(distinct voucher_date)    as active_days,
        min(voucher_date)               as first_sale_date,
        max(voucher_date)               as last_sale_date,
        sum(transaction_count)          as total_transactions

    from financials
    group by 1

),

-- Add derived branch classification (replaces the old branch_type column)
final as (

    select
        company_name,

        -- Classify branch type from name
        case
            when company_name = 'SITARAM AND SONS -HO' then 'Head Office'
            else 'Retail Branch'
        end                         as branch_type,

        -- Active flag
        case
            when company_name in (
                'SITARAM AND SONS',
                'SITARAMS',
                'SITARAM SHYAM SUNDER',
                'SITARAM SHANKAR LAL',
                'SITARAM AND SONS -HO'
            ) then true
            else false
        end                         as is_active,

        total_gross_sales,
        total_sales_returns,
        total_net_sales,
        total_expenses,
        total_salary,
        total_shop_expense,
        total_freight,
        total_net_pnl,
        avg_pnl_margin_pct,
        active_days,
        first_sale_date,
        last_sale_date,
        total_transactions,

        -- Revenue rank across branches
        rank() over (
            order by total_net_sales desc
        )                           as revenue_rank,

        -- Expense ratio (expenses as % of sales)
        round(
            total_expenses / nullif(total_net_sales, 0) * 100
        , 2)                        as expense_ratio_pct,

        -- Avg daily sales
        round(
            total_net_sales / nullif(active_days, 0)
        , 2)                        as avg_daily_sales

    from branch_financials

)

select * from final
order by total_net_sales desc