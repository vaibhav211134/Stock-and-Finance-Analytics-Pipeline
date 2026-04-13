-- models/intermediate/int_transfer_opportunities.sql
-- Purpose: Find items that are slow/stagnant at one branch
--          but sell well at another branch — transfer candidates.
--          Uses stg_stock_movement (closing_qty, not closing_bal_qty)
--          and int_inventory_velocity for sales velocity.

with movement as (

    select * from {{ ref('stg_stock_movement') }}

),

velocity as (

    select * from {{ ref('int_inventory_velocity') }}

),

-- Items that are stagnant at a branch (no outward movement)
stagnant as (

    select
        company_name,
        stock_no,
        item_description,
        product,
        brand,
        closing_qty         as qty_available,
        capital_locked,
        movement_status
    from movement
    where movement_status = 'Stagnant'
      and closing_qty > 0

),

-- Items that sell fast at some branch
fast_movers as (

    select
        stock_no,
        company_name        as sells_fast_at,
        velocity_tier,
        units_per_day,
        total_units_sold
    from velocity
    where velocity_tier = 'Fast mover'

),

-- Match: stagnant at branch A, fast mover at branch B
opportunities as (

    select
        s.company_name          as from_branch,
        f.sells_fast_at         as to_branch,
        s.stock_no,
        s.item_description,
        s.product,
        s.brand,
        s.qty_available,
        s.capital_locked,
        f.units_per_day         as velocity_at_destination,
        f.total_units_sold      as total_sold_at_destination,

        -- Estimated days to sell if transferred
        round(
            s.qty_available / nullif(f.units_per_day, 0)
        , 0)                    as est_days_to_sell_if_transferred

    from stagnant s
    join fast_movers f
        on  s.stock_no     = f.stock_no
        and s.company_name != f.sells_fast_at   -- different branch

)

select * from opportunities
order by capital_locked desc