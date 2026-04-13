import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account
import os

# ── CONFIG ────────────────────────────────────────────────────────────────────
RAW_FILE   = "raw_data/stockbalancereport.csv"
CLEAN_FILE = "clean_data/stock_balance_clean.csv"
GCP_KEY    = "gcp_key.json"
PROJECT_ID = "sitaram-inventory"
DATASET    = "raw"
TABLE      = "stock_balance"

ACTIVE_BRANCHES = [
    "SITARAM AND SONS",
    "SITARAMS",
    "SITARAM SHYAM SUNDER",
    "SITARAM SHANKAR LAL",
    "SITARAM AND SONS -HO",
]

# ── LOAD ──────────────────────────────────────────────────────────────────────
print("Loading raw file...")
df = pd.read_csv(RAW_FILE, dtype={"HSN Code": str}, low_memory=False)
print(f"  Raw rows: {len(df)}")

# ── CLEAN ─────────────────────────────────────────────────────────────────────
str_cols = df.select_dtypes("object").columns
df[str_cols] = df[str_cols].apply(lambda c: c.str.strip())

df.columns = [
    "company_name", "stock_no", "item_description", "product",
    "brand", "style", "shade", "size", "hsn_code", "supplier_name",
    "item_type", "agent", "party", "cost_price", "retail_price",
    "base_uom", "closing_qty", "closing_rate", "closing_value"
]

df = df.dropna(subset=["company_name", "stock_no"])
df = df[df["company_name"].isin(ACTIVE_BRANCHES)]
print(f"  After filtering active branches: {len(df)}")

df = df[df["closing_qty"] > 0]
print(f"  After dropping zero/negative qty: {len(df)}")

df = df.drop(columns=["agent", "party"])

df["hsn_code"] = df["hsn_code"].str.replace(r"\.0$", "", regex=True)

for col in ["company_name", "product", "brand", "item_type"]:
    df[col] = df[col].str.upper().str.strip()

df["margin_pct"]    = ((df["retail_price"] - df["cost_price"]) / df["retail_price"] * 100).round(2)
df["retail_value"]  = (df["closing_qty"] * df["retail_price"]).round(2)
df["capital_locked"]= df["closing_value"].round(2)

print(f"\nFinal clean rows: {len(df)}")
print(f"\nColumn order in CSV:")
for i, col in enumerate(df.columns):
    print(f"  {i:2d}  {col}  ({df[col].dtype})")

# ── SAVE ──────────────────────────────────────────────────────────────────────
os.makedirs("clean_data", exist_ok=True)
df.to_csv(CLEAN_FILE, index=False)
print(f"\nSaved to {CLEAN_FILE}")

# ── UPLOAD TO BIGQUERY ────────────────────────────────────────────────────────
print("\nUploading to BigQuery...")
credentials = service_account.Credentials.from_service_account_file(GCP_KEY)
client = bigquery.Client(project=PROJECT_ID, credentials=credentials)

table_ref = f"{PROJECT_ID}.{DATASET}.{TABLE}"

FORCE_STRING = {
    "company_name", "stock_no", "item_description", "product",
    "brand", "style", "shade", "size", "hsn_code", "supplier_name",
    "item_type", "base_uom",
}

schema = []
for col in df.columns:
    if col in FORCE_STRING or str(df[col].dtype) in ("object", "string"):
        bq_type = "STRING"
    elif str(df[col].dtype) == "bool":
        bq_type = "BOOL"
    elif str(df[col].dtype) in ("int64", "int32"):
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