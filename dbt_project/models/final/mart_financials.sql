with daily as (

    select * from {{ ref('int_daily_pnl') }}

),

with_running_totals as (

    select
        -- ── dimension columns ──────────────────────────────────────────────
        company_name,
        branch_type,
        is_active,
        voucher_date,
        year,
        month,
        month_name,
        week,
        quarter,
        day_of_week,

        -- ── daily metrics ──────────────────────────────────────────────────
        gross_sales,
        sales_returns,
        net_sales,
        b2b_sales,
        total_expenses,
        salary_expense,
        shop_expense,
        freight_expense,
        general_expense,
        home_expense,
        other_expense,
        net_pnl,
        round(pnl_margin_pct, 2)    as pnl_margin_pct,
        purchases,
        purchase_returns,
        net_purchases,
        transfer_in,
        transfer_out,
        receipts,
        transaction_count,

        -- ── month-to-date running totals (for MTD KPI cards in Power BI) ──
        sum(net_sales) over (
            partition by company_name, year, month
            order by voucher_date
            rows between unbounded preceding and current row
        )                           as mtd_net_sales,

        sum(total_expenses) over (
            partition by company_name, year, month
            order by voucher_date
            rows between unbounded preceding and current row
        )                           as mtd_expenses,

        sum(net_pnl) over (
            partition by company_name, year, month
            order by voucher_date
            rows between unbounded preceding and current row
        )                           as mtd_net_pnl,

        -- ── week-to-date running totals ────────────────────────────────────
        sum(net_sales) over (
            partition by company_name, year, week
            order by voucher_date
            rows between unbounded preceding and current row
        )                           as wtd_net_sales,

        -- ── same day last week (WoW comparison) ───────────────────────────
        lag(net_sales, 7) over (
            partition by company_name
            order by voucher_date
        )                           as net_sales_last_week,

        -- ── same day last month (MoM comparison) ──────────────────────────
        lag(net_sales, 30) over (
            partition by company_name
            order by voucher_date
        )                           as net_sales_last_month,

        -- ── YTD net sales ─────────────────────────────────────────────────
        sum(net_sales) over (
            partition by company_name, year
            order by voucher_date
            rows between unbounded preceding and current row
        )                           as ytd_net_sales,

        -- ── 7-day rolling average (smoothed trend line) ───────────────────
        avg(net_sales) over (
            partition by company_name
            order by voucher_date
            rows between 6 preceding and current row
        )                           as net_sales_7day_avg,

        -- ── metadata ──────────────────────────────────────────────────────
        current_date()              as report_date

    from daily

)

select * from with_running_totals
order by company_name, voucher_date