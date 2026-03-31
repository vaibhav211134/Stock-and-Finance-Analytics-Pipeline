-- MART SUPPLIER ANALYSIS
-- Answers: Who are our top suppliers? How much do we spend per supplier?
-- Which suppliers give us the best margins?
-- Power BI page: Procurement Insights

with purchases as (

    select * from {{ ref('stg_purchases') }}

),

supplier_summary as (

    select
        -- supplier identity
        supplier_name,
        brand,
        product,

        -- VOLUME METRICS
        -- how many times did we buy from this supplier
        count(distinct voucher_no)              as total_purchase_orders,

        -- total pieces bought
        sum(purchase_qty)                       as total_units_purchased,

        -- FINANCIAL METRICS
        -- total money spent with this supplier
        round(sum(item_net_amount), 2)          as total_purchase_value,

        -- average order value
        round(avg(item_net_amount), 2)          as avg_order_value,

        -- average cost price per unit
        round(avg(item_rate), 2)                as avg_item_cost,

        -- average retail price per unit
        round(avg(retail_price), 2)             as avg_retail_price,

        -- MARGIN METRICS
        -- gross margin % = (retail - cost) / retail × 100
        -- tells us which supplier gives us best profit margin
        round(
            safe_divide(
                sum(retail_price - item_rate),
                sum(retail_price)
            ) * 100
        , 2)                                    as avg_gross_margin_pct,

        -- DATE METRICS
        -- when did we first and last buy from this supplier
        min(voucher_date)                       as first_purchase_date,
        max(voucher_date)                       as last_purchase_date,

        -- how many months have we been buying from them
        date_diff(
            max(voucher_date),
            min(voucher_date),
            month
        )                                       as relationship_months,

        -- how many unique items do they supply
        count(distinct stock_no)                as unique_items_supplied

    from purchases
    where supplier_name is not null     -- remove rows with no supplier name
    group by
        supplier_name,
        brand,
        product

),

-- rank suppliers by total purchase value
-- rank 1 = biggest supplier
ranked as (

    select
        *,

        -- RANK by total spend — who do we spend most with
        rank() over (
            order by total_purchase_value desc
        )                                       as supplier_rank,

        -- RANK within each product category
        rank() over (
            partition by product
            order by total_purchase_value desc
        )                                       as rank_within_category,

        -- REPORT DATE
        current_date()                          as report_date

    from supplier_summary

)

select * from ranked
order by total_purchase_value desc