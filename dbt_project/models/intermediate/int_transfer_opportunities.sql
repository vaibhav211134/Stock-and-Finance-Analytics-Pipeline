-- This model finds items where one branch is out of stock
-- but another branch has excess stock of the same item
-- Instead of reordering from supplier, just transfer between branches!

with velocity as (

    select * from {{ ref('int_inventory_velocity') }}

),

-- Step 1: find branches that are OUT OF STOCK for each item
-- these are the branches that NEED stock
needing_stock as (

    select
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,
        retail_price,
        company_name          as needing_branch,   -- this branch needs stock
        sales_qty,                                  -- proof that it was selling
        daily_velocity                              -- how fast it sells

    from velocity
    where closing_bal_qty = 0    -- out of stock
    and sales_qty > 0            -- but was actually selling (real demand exists)

),

-- Step 2: find branches that have EXCESS STOCK of the same item
-- these are the branches that CAN GIVE stock
having_stock as (

    select
        stock_no,
        company_name          as giving_branch,    -- this branch can give stock
        closing_bal_qty       as available_qty,    -- how much they have
        capital_locked                             -- value of that stock

    from velocity
    where closing_bal_qty > 2    -- has meaningful stock (more than 2 pieces)
    and sales_qty = 0            -- and it is NOT selling there (dead stock there)

),

-- Step 3: join them together
-- same stock_no, different branches
opportunities as (

    select
        n.stock_no,
        n.item_description,
        n.product,
        n.brand,
        n.style,
        n.shade,
        n.size,
        n.retail_price,
        n.needing_branch,         -- branch that needs stock
        h.giving_branch,          -- branch that has excess
        h.available_qty,          -- how many pieces can be transferred
        n.daily_velocity,         -- how fast it sells at needing branch
        h.capital_locked,         -- value being unlocked by transfer

        -- TRANSFER PRIORITY SCORE
        -- high velocity at needing branch + high capital locked at giving branch
        -- = very high priority transfer
        round(
            (n.daily_velocity * 100)   -- velocity component
            +
            (h.capital_locked / 1000)  -- capital component
        , 2) as transfer_priority_score

    from needing_stock n
    inner join having_stock h
        on n.stock_no = h.stock_no          -- same item
        and n.needing_branch != h.giving_branch  -- different branches

)

select * from opportunities
order by transfer_priority_score desc   -- highest priority transfers first