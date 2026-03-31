import pandas as pd
import os

# ============================================================
# STEP 1 — READ ALL 3 FILES
# header=4 means "5th row is the real header"
# ============================================================

purchase = pd.read_excel('raw_data/purchase_report.xlsx', header=4)
dead_stock = pd.read_excel('raw_data/dead_stock.xlsx', header=4)
stockout = pd.read_excel('raw_data/stockout.xlsx', header=4)

print("Files loaded successfully!")
print(f"Purchase rows: {purchase.shape[0]}")
print(f"Dead Stock rows: {dead_stock.shape[0]}")
print(f"Stockout rows: {stockout.shape[0]}")

# ============================================================
# STEP 2 — CLEAN COLUMN NAMES
# Lowercase everything, replace spaces with underscores
# So "Company Name" becomes "company_name"
# ============================================================

def clean_columns(df):
    df.columns = (
        df.columns
        .str.strip()           # remove extra spaces
        .str.lower()           # COMPANY NAME → company name
        .str.replace(' ', '_') # company name → company_name
        .str.replace('[^a-z0-9_]', '', regex=True)  # remove special characters
    )
    return df

purchase   = clean_columns(purchase)
dead_stock = clean_columns(dead_stock)
stockout   = clean_columns(stockout)

print("\nColumn names cleaned!")
print("\nPurchase columns:", purchase.columns.tolist())
print("\nDead Stock columns:", dead_stock.columns.tolist())
print("\nStockout columns:", stockout.columns.tolist())

# ============================================================
# STEP 3 — DROP EMPTY ROWS
# QuickBill sometimes adds blank rows at bottom — remove them
# We use the company_name column as anchor
# ============================================================

purchase   = purchase.dropna(subset=['company_name'])
dead_stock = dead_stock.dropna(subset=['company_name'])
stockout   = stockout.dropna(subset=['company_name'])

print("\nEmpty rows dropped!")
print(f"Purchase rows after clean: {purchase.shape[0]}")
print(f"Dead Stock rows after clean: {dead_stock.shape[0]}")
print(f"Stockout rows after clean: {stockout.shape[0]}")

# ============================================================
# STEP 4 — FIX DATE COLUMNS
# Convert date text into proper date format
# ============================================================

purchase['voucher_date']      = pd.to_datetime(purchase['voucher_date'], errors='coerce')
dead_stock['last_purchase_date'] = pd.to_datetime(dead_stock['last_purchase_date'], errors='coerce')
dead_stock['last_sold_date']     = pd.to_datetime(dead_stock['last_sold_date'], errors='coerce')
stockout['last_purchase_date']   = pd.to_datetime(stockout['last_purchase_date'], errors='coerce')
stockout['last_sold_date']       = pd.to_datetime(stockout['last_sold_date'], errors='coerce')

print("\nDates fixed!")

# ============================================================
# STEP 5 — SAVE CLEAN CSVs to clean_data/ folder
# ============================================================

os.makedirs('clean_data', exist_ok=True)

purchase.to_csv('clean_data/purchase_clean.csv', index=False)
dead_stock.to_csv('clean_data/dead_stock_clean.csv', index=False)
stockout.to_csv('clean_data/stockout_clean.csv', index=False)

print("\n✅ ALL DONE! 3 clean CSV files saved in clean_data/ folder")
print("   → clean_data/purchase_clean.csv")
print("   → clean_data/dead_stock_clean.csv")
print("   → clean_data/stockout_clean.csv")