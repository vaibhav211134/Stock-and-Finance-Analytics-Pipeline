with source as (

    select * from `sitaram-inventory`.raw.ledger

),

staged as (

    select
        -- identifiers
        CASE 
            WHEN company_name = 'SITARAM SHANKAR LAL-old'  THEN 'SITARAM SHANKAR LAL'
            WHEN company_name = 'SITARAM SHYAM SUNDER-old' THEN 'SITARAM SHYAM SUNDER'
            WHEN company_name = 'SITARAM\'S-old'            THEN 'SITARAMS'
            ELSE company_name
        END AS company_name,
        city,
        cast(voucher_date as date)       as voucher_date,
        cast(voucher_no   as string)     as voucher_no,
        voucher_type,

        -- description fields
        particulars,
        narration,
        user_name,

        -- quantities
        cast(inwards_qty  as int64)      as inwards_qty,
        cast(outwards_qty as int64)      as outwards_qty,

        -- raw money columns (kept for auditing)
        cast(debit_amount  as float64)   as debit_amount,
        cast(credit_amount as float64)   as credit_amount,

        -- derived columns (computed in Python)
        cast(amount as float64)          as amount,
        expense_category,

        -- branch fields
        branch_type,
        cast(is_active as bool)          as is_active,

        -- calendar helpers
        cast(year     as int64)          as year,
        cast(month    as int64)          as month,
        month_name,
        cast(week     as int64)          as week,
        cast(quarter  as int64)          as quarter,
        day_of_week

    from source

    where
        -- only rows with a valid date
        voucher_date is not null
        -- exclude any Sub Total rows that slipped through
        and not (particulars like '%Sub Total%')

)

select * from staged