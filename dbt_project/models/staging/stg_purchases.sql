with source as (

    select * from {{ source('raw', 'purchase') }}

),

renamed as (

    select
        -- identity columns
        CASE 
            WHEN company_name = 'SITARAM SHANKAR LAL-old'  THEN 'SITARAM SHANKAR LAL'
            WHEN company_name = 'SITARAM SHYAM SUNDER-old' THEN 'SITARAM SHYAM SUNDER'
            WHEN company_name = 'SITARAM\'S-old'            THEN 'SITARAMS'
            ELSE company_name
        END AS company_name,
        stock_no,
        item_description,
        product,
        brand,
        style,
        shade,
        size,

        -- transaction columns
        voucher_no,
        voucher_type,
        cast(voucher_date as date) as voucher_date,
        supplier_name,

        -- financial columns
        cast(purchase_qty as int64)        as purchase_qty,
        cast(retail_price as float64)      as retail_price,
        cast(item_rate as float64)         as item_rate,
        cast(item_net_amount as float64)   as item_net_amount,
        cast(tax_amount as float64)        as tax_amount,
        cast(net_amount as float64)        as net_amount

    from source

    -- remove any rows where stock_no is missing
    where stock_no is not null

)

select * from renamed