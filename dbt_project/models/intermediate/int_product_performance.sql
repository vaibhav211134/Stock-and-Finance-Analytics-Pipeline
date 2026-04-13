-- models/intermediate/int_product_performance.sql
-- Purpose : NEW model — did not exist before. Answers the key business question:
--           "Which products and brands are actually making us money?"
--
--           Combines sales revenue with purchase cost to get REAL margin per product.
--           This is what elevates the project from "inventory tracker" to
--           "business intelligence tool."

with sales as (

    select * from {{ ref('stg_sales') }}

),

purchases as (

    select * from {{ ref('stg_purchases') }}

),

-- Product-level sales summary
product_sales as (

    select
        product,
        brand,
        company_name,

        sum(sales_qty)      as units_sold,
        sum(line_revenue)   as total_revenue,
        sum(full_mrp_value) as total_mrp_value,
        sum(discount_given) as total_discount_given,

        round(avg(retail_price), 2)         as avg_retail_price,
        round(avg(avg_selling_price), 2)    as avg_actual_selling_price,
        round(avg(discount_pct), 2)         as avg_discount_pct,

        count(distinct voucher_no)          as num_transactions,
        count(distinct sale_date)           as active_selling_days,

        min(sale_date)  as first_sale,
        max(sale_date)  as last_sale

    from (
        -- Need avg_selling_price at line level, so compute inline
        select
            *,
            round(line_revenue / nullif(sales_qty, 0), 2) as avg_selling_price
        from sales
    )
    group by 1, 2, 3

),

-- Product-level purchase cost summary
product_cost as (

    select
        product,
        brand,
        company_name,
        sum(purchase_qty)   as units_purchased,
        round(avg(item_rate), 2) as avg_cost_price,
        sum(item_net_amount)     as total_purchase_cost

    from purchases
    group by 1, 2, 3

),

-- Join sales + cost to get margin
combined as (

    select
        s.product,
        s.brand,
        s.company_name,

        -- Sales metrics
        s.units_sold,
        s.total_revenue,
        s.total_mrp_value,
        s.total_discount_given,
        s.avg_retail_price,
        s.avg_actual_selling_price,
        s.avg_discount_pct,
        s.num_transactions,
        s.active_selling_days,
        s.first_sale,
        s.last_sale,

        -- Cost metrics
        c.units_purchased,
        c.avg_cost_price,
        c.total_purchase_cost,

        -- Margin calculation
        round(s.avg_actual_selling_price - c.avg_cost_price, 2)
            as avg_unit_margin,

        round(
            (s.avg_actual_selling_price - c.avg_cost_price) /
            nullif(s.avg_actual_selling_price, 0) * 100
        , 2) as margin_pct,

        -- Estimated total profit (units sold × unit margin)
        round(s.units_sold * (s.avg_actual_selling_price - c.avg_cost_price), 2)
            as estimated_profit,

        -- Sell-through rate (units sold / units purchased)
        round(s.units_sold / nullif(c.units_purchased, 0) * 100, 2)
            as sell_through_pct,

        -- Revenue rank within branch
        rank() over (
            partition by s.company_name
            order by s.total_revenue desc
        ) as revenue_rank_in_branch,

        -- Revenue rank across all branches (overall)
        rank() over (
            order by s.total_revenue desc
        ) as revenue_rank_overall

    from product_sales s
    left join product_cost c
        on  s.product      = c.product
        and s.brand        = c.brand
        and s.company_name = c.company_name

)

select * from combined
order by total_revenue desc