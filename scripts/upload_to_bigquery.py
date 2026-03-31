from google.cloud import bigquery
import pandas as pd
import os

# ============================================================
# STEP 1 — CONNECT TO BIGQUERY USING YOUR KEY FILE
# ============================================================

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = 'gcp_key.json'

client = bigquery.Client(project='sitaram-inventory')

print("✅ Connected to BigQuery!")

# ============================================================
# STEP 2 — CREATE A DATASET CALLED "raw"
# Dataset = like a folder inside BigQuery
# ============================================================

dataset_id = 'sitaram-inventory.raw'
dataset = bigquery.Dataset(dataset_id)
dataset.location = 'US'

try:
    client.create_dataset(dataset)
    print("✅ Dataset 'raw' created!")
except Exception as e:
    print(f"Dataset already exists or error: {e}")

# ============================================================
# STEP 3 — LOAD ALL 3 CSV FILES INTO BIGQUERY
# Each CSV becomes one table
# ============================================================

files = {
    'purchase'  : 'clean_data/purchase_clean.csv',
    'dead_stock': 'clean_data/dead_stock_clean.csv',
    'stockout'  : 'clean_data/stockout_clean.csv',
}

for table_name, file_path in files.items():

    print(f"\nUploading {file_path}...")

    # Read the CSV
    df = pd.read_csv(file_path)

    # Full table address in BigQuery
    table_id = f'sitaram-inventory.raw.{table_name}'

    # Upload — if table exists, replace it
    job_config = bigquery.LoadJobConfig(
        write_disposition='WRITE_TRUNCATE',  # replace if exists
        autodetect=True                       # auto detect column types
    )

    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()  # wait for upload to finish

    # Confirm
    table = client.get_table(table_id)
    print(f"✅ {table_name} uploaded — {table.num_rows} rows in BigQuery")

print("\n🎉 ALL 3 TABLES LIVE IN BIGQUERY!")