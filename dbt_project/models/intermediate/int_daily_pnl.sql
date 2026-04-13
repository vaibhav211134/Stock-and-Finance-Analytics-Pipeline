with ledger as (

    select * from {{ ref('stg_ledger') }}

),

-- ── Classify each row into a financial bucket ──────────────────────────────
classified as (

    select
        company_name,
        branch_type,
        is_active,
        voucher_date,
        year,
        month,
        month_name,
        week,
        quarter,
        day_of_week,
        voucher_type,
        particulars,
        expense_category,
        narration,
        amount,

        -- RETAIL SALES (what branches sell to customers)
        case when voucher_type = 'Sales'        then amount else 0 end as gross_sales,

        -- SALES RETURNS (customer returns)
        case when voucher_type = 'Sales Return' then amount else 0 end as sales_returns,

        -- B2B SALE (HO dispatching stock to branches — internal, not customer revenue)
        case when voucher_type = 'B2B Sale'     then amount else 0 end as b2b_sales,

        -- EXPENSES — broken down by category
        case when voucher_type = 'Payment' then amount else 0 end as total_expenses,

        case when voucher_type = 'Payment'
              and expense_category = 'Salary'
             then amount else 0 end as salary_expense,

        case when voucher_type = 'Payment'
              and expense_category = 'Shop Expense'
             then amount else 0 end as shop_expense,

        case when voucher_type = 'Payment'
              and expense_category = 'Freight'
             then amount else 0 end as freight_expense,

        case when voucher_type = 'Payment'
              and expense_category = 'General Expense'
             then amount else 0 end as general_expense,

        case when voucher_type = 'Payment'
              and expense_category = 'Home Expense'
             then amount else 0 end as home_expense,

        case when voucher_type = 'Payment'
              and expense_category not in ('Salary','Shop Expense','Freight',
                                           'General Expense','Home Expense')
             then amount else 0 end as other_expense,

        -- PURCHASE (what HO buys from suppliers)
        case when voucher_type = 'Purchase'        then amount else 0 end as purchases,
        case when voucher_type = 'Purchase Return' then amount else 0 end as purchase_returns,

        -- TRANSFERS (stock movement between HO and branches)
        case when voucher_type = 'Transfer In'  then amount else 0 end as transfer_in,
        case when voucher_type = 'Transfer Out' then amount else 0 end as transfer_out,

        -- RECEIPT (cash/cheque received not from sales)
        case when voucher_type = 'Receipt'      then amount else 0 end as receipts,

        -- transaction count
        1 as txn_count

    from ledger

),

-- ── Roll up to branch × day ───────────────────────────────────────────────
daily as (

    select
        company_name,
        branch_type,
        is_active,
        voucher_date,
        year,
        month,
        month_name,
        week,
        quarter,
        day_of_week,

        -- revenue
        sum(gross_sales)                                            as gross_sales,
        sum(sales_returns)                                          as sales_returns,
        sum(gross_sales) - sum(sales_returns)                       as net_sales,
        sum(b2b_sales)                                              as b2b_sales,

        -- expenses
        sum(total_expenses)                                         as total_expenses,
        sum(salary_expense)                                         as salary_expense,
        sum(shop_expense)                                           as shop_expense,
        sum(freight_expense)                                        as freight_expense,
        sum(general_expense)                                        as general_expense,
        sum(home_expense)                                           as home_expense,
        sum(other_expense)                                          as other_expense,

        -- net P&L  (retail net sales minus all operating expenses)
        (sum(gross_sales) - sum(sales_returns)) - sum(total_expenses) as net_pnl,

        -- gross margin proxy  (net sales − expenses)  as % of gross sales
        safe_divide(
            (sum(gross_sales) - sum(sales_returns)) - sum(total_expenses),
            nullif(sum(gross_sales), 0)
        ) * 100                                                     as pnl_margin_pct,

        -- purchase flows
        sum(purchases)                                              as purchases,
        sum(purchase_returns)                                       as purchase_returns,
        sum(purchases) - sum(purchase_returns)                      as net_purchases,

        -- transfer flows
        sum(transfer_in)                                            as transfer_in,
        sum(transfer_out)                                           as transfer_out,

        -- other
        sum(receipts)                                               as receipts,
        sum(txn_count)                                              as transaction_count

    from classified
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

)

select * from daily