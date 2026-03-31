-- MART PROCUREMENT ANALYSIS
-- Answers: What are monthly buying trends? Which brands/categories dominate?
-- What is our gross margin per brand/category?
-- Power BI page: Procurement Insights + Executive Summary

with purchases as (

    select * from {{ ref('stg_purchases') }}

),

-- PART 1: MONTHLY TRENDS
-- how much did we buy each month
monthly_trends as (

    select
        -- extract year and month from voucher date
        extract(year from voucher_date)         as purchase_year,
        extract(month from voucher_date)        as purchase_month,

        -- combine year+month into one readable label e.g. "2025-01"
        format_date('%Y-%m', voucher_date)      as year_month,

        product,
        brand,

        -- volume
        sum(purchase_qty)                       as total_units,

        -- spend
        round(sum(item_net_amount), 2)          as total_spend,

        -- margin
        round(
            safe_divide(
                sum(retail_price - item_rate),
                sum(retail_price)
            ) * 100
        , 2)                                    as gross_margin_pct,

        -- unique items bought this month
        count(distinct stock_no)                as unique_items,

        -- unique suppliers used this month
        count(distinct supplier_name)           as unique_suppliers

    from purchases
    group by
        purchase_year,
        purchase_month,
        year_month,
        product,
        brand

),

-- PART 2: BRAND PERFORMANCE
-- which brands are we investing most in
brand_summary as (

    select
        brand,
        product,

        -- total investment in this brand
        round(sum(item_net_amount), 2)          as total_brand_spend,

        -- total units
        sum(purchase_qty)                       as total_brand_units,

        -- margin
        round(
            safe_divide(
                sum(retail_price - item_rate),
                sum(retail_price)
            ) * 100
        , 2)                                    as brand_gross_margin_pct,

        -- unique styles bought
        count(distinct style)                   as unique_styles,

        -- unique suppliers for this brand
        count(distinct supplier_name)           as unique_suppliers,

        -- brand rank by spend
        rank() over (
            order by sum(item_net_amount) desc
        )                                       as brand_rank

    from purchases
    group by
        brand,
        product

),

-- PART 3: CATEGORY PERFORMANCE
-- which product categories dominate
category_summary as (

    select
        product,

        -- total investment in this category
        round(sum(item_net_amount), 2)          as total_category_spend,

        -- total units
        sum(purchase_qty)                       as total_category_units,

        -- margin
        round(
            safe_divide(
                sum(retail_price - item_rate),
                sum(retail_price)
            ) * 100
        , 2)                                    as category_gross_margin_pct,

        -- unique brands in this category
        count(distinct brand)                   as unique_brands,

        -- category rank
        rank() over (
            order by sum(item_net_amount) desc
        )                                       as category_rank

    from purchases
    group by product

),

-- JOIN all 3 parts together
-- monthly_trends is the base — brand and category info attached
final as (

    select
        m.year_month,
        m.purchase_year,
        m.purchase_month,
        m.product,
        m.brand,
        m.total_units,
        m.total_spend,
        m.gross_margin_pct,
        m.unique_items,
        m.unique_suppliers,

        -- attach brand level metrics
        b.total_brand_spend,
        b.brand_gross_margin_pct,
        b.brand_rank,
        b.unique_styles,

        -- attach category level metrics
        c.total_category_spend,
        c.category_gross_margin_pct,
        c.category_rank,
        c.unique_brands,

        current_date()                          as report_date

    from monthly_trends m
    left join brand_summary b
        on m.brand = b.brand
        and m.product = b.product
    left join category_summary c
        on m.product = c.product

)

select * from final
order by year_month, total_spend desc