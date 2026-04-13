import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account
import os

# ── CONFIG ────────────────────────────────────────────────────────────────────
RAW_FILE   = "raw_data/inventory_transaction_sales_report.csv"
CLEAN_FILE = "clean_data/sales_clean.csv"
GCP_KEY    = "gcp_key.json"
PROJECT_ID = "sitaram-inventory"
DATASET    = "raw"
TABLE      = "sales"

ACTIVE_BRANCHES = [
    "SITARAM AND SONS",
    "SITARAMS",
    "SITARAM SHYAM SUNDER",
    "SITARAM SHANKAR LAL",
    "SITARAM AND SONS -HO",
]

# ── LOAD ──────────────────────────────────────────────────────────────────────
print("Loading raw file...")
df = pd.read_csv(RAW_FILE, low_memory=False)
print(f"  Raw rows : {len(df)}")

# ── CLEAN ─────────────────────────────────────────────────────────────────────
str_cols = df.select_dtypes("object").columns
df[str_cols] = df[str_cols].apply(lambda c: c.str.strip())

df.columns = [
    "company_name", "voucher_type", "voucher_date", "voucher_no",
    "particulars", "stock_no", "item_description", "product",
    "brand", "style", "shade", "size", "retail_price",
    "sales_qty", "base_uom", "alt_sales_qty", "net_amount", "remarks"
]

df["voucher_date"] = pd.to_datetime(df["voucher_date"], dayfirst=True)
df = df.dropna(subset=["company_name", "stock_no", "voucher_date"])
df = df[df["company_name"].isin(ACTIVE_BRANCHES)]
print(f"  After active branch filter : {len(df)}")

df = df.drop(columns=["remarks", "alt_sales_qty"])

for col in ["company_name", "product", "brand", "voucher_type"]:
    df[col] = df[col].str.upper().str.strip()

# Rename particulars to customer_ref
df = df.rename(columns={"particulars": "customer_ref"})

df["sale_date"]      = df["voucher_date"].dt.date
df["sale_year"]      = df["voucher_date"].dt.year
df["sale_month"]     = df["voucher_date"].dt.month
df["sale_month_name"]= df["voucher_date"].dt.strftime("%b")
df["sale_quarter"]   = df["voucher_date"].dt.quarter
df["sale_week"]      = df["voucher_date"].dt.isocalendar().week.astype(int)
df["sale_dow"]       = df["voucher_date"].dt.day_name()

df["line_revenue"]   = df["net_amount"].round(2)
df["full_mrp_value"] = (df["sales_qty"] * df["retail_price"]).round(2)
df["discount_given"] = (df["full_mrp_value"] - df["net_amount"]).round(2)
df["discount_pct"]   = (
    df["discount_given"] / df["full_mrp_value"].replace(0, float("nan")) * 100
).round(2)
df["is_b2b"] = df["voucher_type"] == "B2B SALE"

# Drop the original voucher_date (sale_date replaces it as DATE type)
df = df.drop(columns=["voucher_date"])

print(f"\nFinal clean rows : {len(df)}")
print(f"\nColumn order in CSV:")
for i, col in enumerate(df.columns):
    print(f"  {i:2d}  {col}  ({df[col].dtype})")

# ── SAVE ──────────────────────────────────────────────────────────────────────
os.makedirs("clean_data", exist_ok=True)
df.to_csv(CLEAN_FILE, index=False)
print(f"\nSaved → {CLEAN_FILE}")

# ── UPLOAD TO BIGQUERY ────────────────────────────────────────────────────────
print("\nUploading to BigQuery...")
credentials = service_account.Credentials.from_service_account_file(GCP_KEY)
client = bigquery.Client(project=PROJECT_ID, credentials=credentials)

table_ref = f"{PROJECT_ID}.{DATASET}.{TABLE}"

FORCE_STRING = {
    "company_name", "voucher_type", "voucher_no", "customer_ref",
    "stock_no", "item_description", "product", "brand",
    "style", "shade", "size", "base_uom",
    "sale_month_name", "sale_dow",
}
FORCE_DATE   = {"sale_date"}
FORCE_BOOL   = {"is_b2b"}
FORCE_INT    = {"sale_year", "sale_month", "sale_quarter", "sale_week"}

schema = []
for col in df.columns:
    if col in FORCE_STRING or str(df[col].dtype) in ("object", "string"):
        bq_type = "STRING"
    elif col in FORCE_DATE:
        bq_type = "DATE"
    elif col in FORCE_BOOL or str(df[col].dtype) == "bool":
        bq_type = "BOOL"
    elif col in FORCE_INT or str(df[col].dtype) in ("int64", "int32"):
        bq_type = "INT64"
    else:
        bq_type = "FLOAT64"
    schema.append(bigquery.SchemaField(col, bq_type))

print("\nBigQuery schema (matches CSV column order):")
for f in schema:
    print(f"  {f.name:30s} {f.field_type}")

job_config = bigquery.LoadJobConfig(
    write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    source_format=bigquery.SourceFormat.CSV,
    skip_leading_rows=1,
    schema=schema,
)

with open(CLEAN_FILE, "rb") as f:
    job = client.load_table_from_file(f, table_ref, job_config=job_config)
job.result()

table = client.get_table(table_ref)
print(f"\nUploaded {table.num_rows} rows to {table_ref}")
print("\nDone!")