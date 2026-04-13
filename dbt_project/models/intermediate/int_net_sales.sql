-- models/intermediate/int_net_sales.sql
-- Purpose : Combines stg_sales and stg_sales_returns to produce
--           NET figures per SKU per branch per month.
--
--           This is the CORRECT way to measure revenue and units —
--           gross sales minus returns. Every downstream mart that
--           shows revenue should use this, not raw stg_sales.
--
-- FIXES APPLIED:
--   1. GREATEST(0, ...) on net_units_sold and net_revenue
--      Guards against 3 known data entry errors where return_qty > sold_qty.
--      Without this, those 3 rows would make net figures go negative.
--
-- Outputs one row per stock_no × company_name × sale_month.

with sales as (

    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        sale_year                   as txn_year,
        sale_month                  as txn_month,
        sale_month_name             as txn_month_name,
        sale_quarter                as txn_quarter,
        sum(sales_qty)              as gross_units_sold,
        sum(line_revenue)           as gross_revenue,
        sum(discount_given)         as total_discount,
        sum(full_mrp_value)         as total_mrp_value,
        count(distinct voucher_no)  as num_bills,
        sum(case when is_b2b then sales_qty    else 0 end) as b2b_units,
        sum(case when is_b2b then line_revenue else 0 end) as b2b_revenue
    from {{ ref('stg_sales') }}
    group by 1,2,3,4,5,6,7,8,9

),

returns as (

    select
        company_name,
        stock_no,
        return_year                 as txn_year,
        return_month                as txn_month,
        sum(return_qty)             as returned_units,
        sum(return_value)           as returned_value
    from {{ ref('stg_sales_returns') }}
    group by 1,2,3,4

),

combined as (

    select
        s.company_name,
        s.stock_no,
        s.item_description,
        s.product,
        s.brand,
        s.txn_year,
        s.txn_month,
        s.txn_month_name,
        s.txn_quarter,

        -- Gross figures
        s.gross_units_sold,
        s.gross_revenue,
        s.total_discount,
        s.total_mrp_value,
        s.num_bills,
        s.b2b_units,
        s.b2b_revenue,

        -- Return figures (0 if no returns this month)
        coalesce(r.returned_units, 0)   as returned_units,
        coalesce(r.returned_value, 0)   as returned_value,

        -- NET figures — GREATEST(0,...) prevents negatives from the
        -- 3 known data entry errors where return_qty > sold_qty
        greatest(0,
            s.gross_units_sold - coalesce(r.returned_units, 0)
        )                               as net_units_sold,

        greatest(0,
            s.gross_revenue - coalesce(r.returned_value, 0)
        )                               as net_revenue,

        -- Return rate for this SKU/branch/month
        round(
            coalesce(r.returned_units, 0) /
            nullif(s.gross_units_sold, 0) * 100
        , 2)                            as return_rate_pct,

        -- Return value rate
        round(
            coalesce(r.returned_value, 0) /
            nullif(s.gross_revenue, 0) * 100
        , 2)                            as return_value_rate_pct,

        -- Flag: high-return item this month (>10% return rate)
        case
            when coalesce(r.returned_units, 0) /
                 nullif(s.gross_units_sold, 0) > 0.10
            then true else false
        end                             as is_high_return_item

    from sales s
    left join returns r
        on  s.company_name = r.company_name
        and s.stock_no     = r.stock_no
        and s.txn_year     = r.txn_year
        and s.txn_month    = r.txn_month

)

select * from combined
order by txn_year, txn_month, net_revenue desc