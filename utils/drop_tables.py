import tfvars
import argparse
from databricks_cli.configure.provider import DatabricksConfig
from databricks_cli.unity_catalog.uc_service import UnityCatalogService
from databricks_cli.configure.config import _get_api_client

parser = argparse.ArgumentParser(description='UC Catalog/Schema info')
parser.add_argument('--catalog', type=str, required=True)
parser.add_argument('--schema', type=str, required=True)

args = parser.parse_args()
tfv = tfvars.LoadSecrets()

config = DatabricksConfig.from_password(
    tfv['databricks_workspace_url'], 
    tfv['databricks_account_username'],
    tfv['databricks_account_password']
    )

api_client = _get_api_client(config, command_name="blog-dms-cdc-demo")
uc_client = UnityCatalogService(api_client)

schema_tables = uc_client.list_tables(args.catalog, args.schema).get('tables', '')

if schema_tables == '':
    print("No Tables in Schema")
    exit()

for table in schema_tables:
    uc_client.delete_table(f"{args.catalog}.{args.schema}.{table['name']}")
    print(f"Deleted table {args.catalog}.{args.schema}.{table['name']}")
