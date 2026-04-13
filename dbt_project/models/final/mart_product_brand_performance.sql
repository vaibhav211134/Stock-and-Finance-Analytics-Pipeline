-- models/final/mart_product_brand_performance.sql
-- Purpose : NEW mart table — brand and product performance scorecard.
--           Did not exist before. Powers the Procurement + Suppliers dashboard page.
--           Answers: "Which brands should we buy more of? Which should we stop?"
--
-- Power BI reads this for Page 3 — Procurement + Suppliers.

with perf as (

    select * from {{ ref('int_product_performance') }}

),

-- Summarise to product level (across all branches)
product_summary as (

    select
        product,
        brand,

        sum(units_sold)             as total_units_sold,
        sum(total_revenue)          as total_revenue,
        sum(total_discount_given)   as total_discount_given,
        sum(estimated_profit)       as total_estimated_profit,
        sum(units_purchased)        as total_units_purchased,

        round(avg(margin_pct), 2)           as avg_margin_pct,
        round(avg(avg_discount_pct), 2)     as avg_discount_pct,
        round(avg(sell_through_pct), 2)     as avg_sell_through_pct,
        round(avg(avg_cost_price), 2)       as avg_cost_price,
        round(avg(avg_retail_price), 2)     as avg_retail_price,

        count(distinct company_name)        as num_branches_selling,
        min(first_sale)                     as first_sale_date,
        max(last_sale)                      as last_sale_date,

        -- Revenue rank across all products
        rank() over (order by sum(total_revenue) desc)          as revenue_rank,
        -- Profit rank
        rank() over (order by sum(estimated_profit) desc)       as profit_rank,
        -- Volume rank
        rank() over (order by sum(units_sold) desc)             as volume_rank

    from perf
    group by 1, 2

),

-- Classify each product into a strategic quadrant
final as (

    select
        *,

        -- Strategic quadrant
        case
            when avg_margin_pct >= 30 and avg_sell_through_pct >= 50
                then 'Star — buy more'           -- high margin, sells fast
            when avg_margin_pct >= 30 and avg_sell_through_pct < 50
                then 'Margin trap — slow seller' -- good margin but sitting
            when avg_margin_pct < 30  and avg_sell_through_pct >= 50
                then 'Volume driver — low margin'-- sells fast, thin margin
            when avg_margin_pct < 30  and avg_sell_through_pct < 50
                then 'Dog — review or drop'      -- poor margin, slow sales
            else 'Insufficient data'
        end as strategic_quadrant,

        -- Discount risk flag
        case
            when avg_discount_pct > 20 then 'High discount risk'
            when avg_discount_pct > 10 then 'Moderate discount'
            else 'Healthy pricing'
        end as discount_risk

    from product_summary

)

select * from final
order by total_revenue desc