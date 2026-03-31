-- This model takes dead stock items and scores them by priority
-- Higher score = more urgent to liquidate
-- Score is based on: capital locked + how long it has been sitting

with dead_stock as (

    select * from {{ ref('stg_dead_stock') }}

),

scored as (

    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        retail_price,
        closing_bal_qty,
        closing_bal_value,
        last_purchase_date,
        last_sold_date,

        -- CAPITAL LOCKED = value of stock sitting unsold
        round(closing_bal_value, 2) as capital_locked,

        -- OPPORTUNITY COST = what this money could have earned elsewhere
        -- assuming 12% annual cost of capital
        -- monthly cost = capital × 0.12 / 12
        round(closing_bal_value * 0.12 / 12, 2) as monthly_opportunity_cost,

        -- LIQUIDATION FLOOR = minimum price to recover cost
        -- sell at 60% of item cost price — below this we lose money
        round(retail_price * 0.60, 2) as liquidation_floor,

        -- DAYS SINCE LAST SOLD = how long this item has been sitting
        -- if never sold, last_sold_date will be null — we use 999 as a flag
        case
            when last_sold_date is null then 999
            else date_diff(current_date(), last_sold_date, day)
        end as days_since_last_sold,

        -- DEAD STOCK SCORE = urgency score (higher = more urgent to act)
        -- Logic: big capital locked + sitting for long time = high score
        -- We normalize both components to make them comparable
        round(
            (closing_bal_value / 1000)   -- capital component (per 1000 rupees)
            +
            case                          -- time component
                when last_sold_date is null then 50        -- never sold = very urgent
                when date_diff(current_date(), last_sold_date, day) > 365 then 30  -- over 1 year
                when date_diff(current_date(), last_sold_date, day) > 180 then 20  -- over 6 months
                when date_diff(current_date(), last_sold_date, day) > 90  then 10  -- over 3 months
                else 5                                                              -- under 3 months
            end
        , 2) as dead_stock_score

    from dead_stock
    where closing_bal_qty > 0      -- must have stock
    and closing_bal_value > 0      -- must have value

)

-- order by score descending so highest priority items come first
select * from scored
order by dead_stock_score desc