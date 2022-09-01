# Reference DB-UC-Demo

This is a reference terraform script on creating a brand new UC Metastore and assigning it to Workspace. Mainly useful in understanding how the general UC workspace enablement flow is. Not mean't for production in any capacity.

## Prerequisite/Assumptions
* Have Brand new Databricks Workspace
* Databricks Account Admin 
* Create AWS IAM Roles and Policies
* No existing UC Metastore, UC Metastore that script creates is defaulted to primary
* Have a group of users whom wish to try out UC and also ingest data from outside S3 bucket

## Walkthrough
In this script we do the following(summary, see comments in main.tf for more detail) ->

* Create UC Metastore and associated AWS IAM Role / S3 bucket
* Create and Add the emails in databricks_user var to a group called `analyst` in databricks
* Create UC Catalog called `analyst_sandbox` and give `analyst` group has `USAGE` Grants on it
* For each user we add we create a SCHEMA named after there email alias and give them `USAGE/CREATE` perms for there schema only
    * e.g. user email is `viren.patel+analyst1@databricks.com`, schema created called `viren_patel_analyst1`
* Also Create Storage Credential for the `s3_existing_data` bucket with `READ_FILES` Perms to `analyst` group
* Then create external location using the Storage Credential and we make the whole bucket accessible via external location to the analyst group
* Small SQL Endpoint is also created
* Cluster policy to enforce UC CLuster spin only is also provisioned to `analyst` group

### Notebook
`sql_endpoint_queries.sql` show how to query data outside of UC with `STORAGE CREDENTIAL` and `EXTERNAL LOCATION`, you will need to update it to your own code path and storage credential name