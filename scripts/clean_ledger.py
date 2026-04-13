import pandas as pd
import numpy as np
from google.cloud import bigquery
from google.oauth2 import service_account
import os

# ─── CONFIG ────────────────────────────────────────────────────────────────────
KEY_PATH = r"C:\Users\vaibh\OneDrive\Documents\sitaram_inventory\gcp_key.json"
PROJECT  = "sitaram-inventory"
DATASET  = "raw"
TABLE    = "ledger"
# ───────────────────────────────────────────────────────────────────────────────

credentials = service_account.Credentials.from_service_account_file(KEY_PATH)
client = bigquery.Client(project=PROJECT, credentials=credentials)

# ── STEP 1: LOAD ──────────────────────────────────────────────────────────────
# header=0 → row 1 has real column names (no junk rows like other QuickBill files)
df = pd.read_csv(
    "raw_data/daybook_ledger.csv",
    header=0,
    dtype=str          # read everything as string first, we cast below
)

print(f"Raw rows loaded: {len(df)}")
print("Columns found:", df.columns.tolist())

# ── STEP 2: CLEAN COLUMN NAMES ───────────────────────────────────────────────
df.columns = (
    df.columns
    .str.strip()
    .str.lower()
    .str.replace(" ", "_")
    .str.replace(r"[^a-z0-9_]", "", regex=True)
)

# ── STEP 3: DROP JUNK ROWS ────────────────────────────────────────────────────
# Remove Sub Total rows (company_name is NaN on these)
df = df[df["company_name"].notna()]
df = df[df["company_name"].str.strip() != ""]
# Also catch any remaining Sub Total rows via particulars
df = df[~df["particulars"].fillna("").str.contains("Sub Total", case=False)]

print(f"After dropping junk rows: {len(df)}")

# ── STEP 4: DROP VOID ROWS ────────────────────────────────────────────────────
# Void = cancelled transactions. Never count them in any analysis.
df = df[~df["voucher_type"].fillna("").str.contains(r"\(Void\)", case=False)]

print(f"After dropping void rows: {len(df)}")

# ── STEP 5: DROP NON-FINANCIAL VOUCHER TYPES ─────────────────────────────────
# These carry no cash/sales value: Delivery Note, Stock Journal, Physical Stock,
# Delivery Note Closure — they are stock movement records, not financial entries
exclude_types = [
    "Delivery Note",
    "Delivery Note Closure",
    "Stock Journal",
    "Physical Stock",
]
df = df[~df["voucher_type"].isin(exclude_types)]

print(f"After dropping non-financial types: {len(df)}")

# ── STEP 6: FIX DATES ─────────────────────────────────────────────────────────
# QuickBill exports as DD-MM-YYYY HH:MM:SS, so dayfirst=True
df["voucher_date"] = pd.to_datetime(
    df["voucher_date"], dayfirst=True, errors="coerce"
).dt.date

# Drop the 25 rows with null dates (safe — they are all Sub Total rows we missed)
df = df[df["voucher_date"].notna()]

# ── STEP 7: CLEAN TEXT COLUMNS ────────────────────────────────────────────────
for col in ["company_name", "city", "voucher_type", "particulars", "narration", "user_name"]:
    if col in df.columns:
        df[col] = df[col].fillna("").str.strip()

# Normalise expense category — QuickBill inconsistently uses
# "Shop Exp" and "SHOP EXP" for the same thing
df["particulars"] = df["particulars"].str.upper().str.strip()

# ── STEP 8: STANDARDISE VOUCHER TYPES ────────────────────────────────────────
# B2B Sale = HO selling to branches internally. Treat same as Sales for revenue.
type_map = {
    "Sales"              : "Sales",
    "B2B Sale"           : "B2B Sale",       # HO → Branch internal transfer (kept separate)
    "Sales Return"       : "Sales Return",
    "Retail Credit Note" : "Sales Return",   # Same economic effect as Sales Return
    "Payment"            : "Payment",
    "Purchase"           : "Purchase",
    "Purchase Return"    : "Purchase Return",
    "Receipt"            : "Receipt",
    "Transfer In"        : "Transfer In",
    "Transfer Out"       : "Transfer Out",
}
df["voucher_type"] = df["voucher_type"].map(type_map).fillna(df["voucher_type"])

# ── STEP 9: CLEAN NUMERIC COLUMNS ────────────────────────────────────────────
for col in ["inwards_qty", "outwards_qty", "debit_amount", "credit_amount"]:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

# ── STEP 10: DERIVE AMOUNT COLUMN ────────────────────────────────────────────
# One clean positive number per row based on confirmed column mapping:
#   Sales              → debit_amount   (confirmed: 47561 debit, 0 credit)
#   Sales Return       → credit_amount  (confirmed: 0 debit, 2768 credit)
#   Retail Credit Note → credit_amount  (confirmed: 0 debit, 26 credit)
#   B2B Sale           → debit_amount   (HO → branch, 163 debit, 0 credit)
#   Payment            → debit_amount   (confirmed: 5719 debit, 0 credit)
#   Purchase           → credit_amount  (confirmed: 0 debit, 1943 credit)
#   Purchase Return    → debit_amount   (confirmed: 67 debit, 0 credit)
#   Transfer In        → credit_amount  (confirmed: 0 debit, 3702 credit)
#   Transfer Out       → debit_amount   (confirmed: 2849 debit, 0 credit)
#   Receipt            → credit_amount  (confirmed: 0 debit, 57 credit)

conditions = [
    df["voucher_type"].isin(["Sales", "B2B Sale"]),
    df["voucher_type"] == "Sales Return",
    df["voucher_type"] == "Payment",
    df["voucher_type"] == "Purchase",
    df["voucher_type"] == "Purchase Return",
    df["voucher_type"] == "Transfer In",
    df["voucher_type"] == "Transfer Out",
    df["voucher_type"] == "Receipt",
]
amount_values = [
    df["debit_amount"],    # Sales, B2B Sale
    df["credit_amount"],   # Sales Return
    df["debit_amount"],    # Payment
    df["credit_amount"],   # Purchase
    df["debit_amount"],    # Purchase Return
    df["credit_amount"],   # Transfer In
    df["debit_amount"],    # Transfer Out
    df["credit_amount"],   # Receipt
]
df["amount"] = np.select(conditions, amount_values, default=0)

# ── STEP 11: EXPENSE CATEGORY ─────────────────────────────────────────────────
# For Payment rows, Particulars already tells us the category.
# Map to standard clean names for Power BI visuals.
expense_map = {
    "SALARY EXP"                    : "Salary",
    "SHOP EXP"                      : "Shop Expense",
    "FREIGHT EXP"                   : "Freight",
    "FREIGHT"                       : "Freight",
    "GENERAL EXP"                   : "General Expense",
    "HOME EXP"                      : "Home Expense",
    "CREDIT NOTE"                   : "Credit Note",
    "GIFT VOUCHER"                  : "Gift Voucher",
    "ADDITONAL INCOME -GIFT VOUCHER": "Gift Voucher",
    "< MULTIPLE PARTY >"            : "Multiple Party",
}
# Map known expense categories; for Payment rows not in the map → "Other Expense"
df["expense_category"] = df["particulars"].map(expense_map)
df["expense_category"] = df["expense_category"].fillna(
    df["voucher_type"].map(lambda v: "Other Expense" if v == "Payment" else "")
)

# ── STEP 12: BRANCH CLASSIFICATION ───────────────────────────────────────────
active_branches = [
    "SITARAM AND SONS",
    "SITARAMS",
    "SITARAM SHANKAR LAL",
    "SITARAM SHYAM SUNDER",
]
head_office = ["SITARAM AND SONS -HO"]

def classify_branch(name):
    if name in head_office:      return "Head Office"
    if name in active_branches:  return "Active Branch"
    return "Inactive"

df["branch_type"] = df["company_name"].apply(classify_branch)
df["is_active"]   = df["company_name"].isin(active_branches)

# ── STEP 13: CALENDAR HELPERS ─────────────────────────────────────────────────
df["voucher_date"] = pd.to_datetime(df["voucher_date"])
df["year"]         = df["voucher_date"].dt.year
df["month"]        = df["voucher_date"].dt.month
df["month_name"]   = df["voucher_date"].dt.strftime("%b %Y")
df["week"]         = df["voucher_date"].dt.isocalendar().week.astype(int)
df["quarter"]      = df["voucher_date"].dt.quarter
df["day_of_week"]  = df["voucher_date"].dt.day_name()
df["voucher_date"] = df["voucher_date"].dt.date   # back to date only

# ── STEP 14: SAVE CLEAN CSV ───────────────────────────────────────────────────
os.makedirs("clean_data", exist_ok=True)
df.to_csv("clean_data/ledger_clean.csv", index=False)
print(f"\nClean CSV saved → clean_data/ledger_clean.csv  ({len(df)} rows)")

# ── STEP 15: UPLOAD TO BIGQUERY ───────────────────────────────────────────────
table_ref  = f"{PROJECT}.{DATASET}.{TABLE}"
job_config = bigquery.LoadJobConfig(
    write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    autodetect=True,
)
job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
job.result()

table = client.get_table(table_ref)
print(f"Uploaded to BigQuery → {table_ref}  ({table.num_rows} rows)")
print("\nDone!")