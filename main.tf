
// Variables
// These are Account Level Admin variables
variable "databricks_account_username" {
  description = "Databricks Account Admin Username"
}
variable "databricks_account_password" {
  description = "Databricks Account Admin Password"
}
variable "databricks_account_id" {
  description = "ID available in bottom left of account admin page"
}

variable "databricks_workspace_url" {
  description = "Need the Workspace URL we are going to enable UC with"
}

variable "databricks_workspace_id" {
  description = "ID of the databricks workspace"
}

variable "databricks_users" {
  description = "List of users to add to workspace"
} 

variable "s3_existing_data" {
  description = "bucket with existing data"
}

variable "region" {}

variable "tags" {
  default = {}
}

// Setting Required Providers
terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "3.49.0"
    }
  }
}

provider "aws" {
  region = var.region
}
// -------------------

// This will tell if the resources is doing a Account level or Workspace level action
// initialize provider in "MWS" mode for account-level resources
// note in resources that have provider = databricks.mws vs provider = databricks.workspace
provider "databricks" {
  alias      = "mws"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  username   = var.databricks_account_username
  password   = var.databricks_account_password
}

// This needs to be created
// initialize provider at workspace level, to create UC resources
provider "databricks" {
  alias    = "workspace"
  host     = var.databricks_workspace_url
  username = var.databricks_account_username
  password = var.databricks_account_password
}

//generate a random string as the prefix for AWS resources, to ensure uniqueness, can skip in ur code
resource "random_string" "naming" {
  special = false
  upper   = false
  length  = 6
}

locals {
  prefix = "demo${random_string.naming.result}"
  tags = {}
}

// ------------------------


// This is just creating neccessary AWs metastora infra
// bucket -> managed data location
// iam role -> that has trusted policy so that databricks account can access and policy for s3 bucket access
// 2 policies are added to it and 1 assume role policy
resource "aws_s3_bucket" "unity_metastore" {
  bucket = "${local.prefix}-metastore"
  acl    = "private"
  versioning {
    enabled = false
  }
  force_destroy = true
  tags = merge(local.tags, {
    Name = "${local.prefix}-metastore"
  })
}

resource "aws_s3_bucket_public_access_block" "metastore" {
  bucket                  = aws_s3_bucket.unity_metastore.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.unity_metastore]
}

data "aws_iam_policy_document" "passrole_for_uc" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"]
      type        = "AWS"
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}

resource "aws_iam_policy" "unity_metastore" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.prefix}-databricks-unity-metastore"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          aws_s3_bucket.unity_metastore.arn,
          "${aws_s3_bucket.unity_metastore.arn}/*"
        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(local.tags, {
    Name = "${local.prefix}-unity-catalog IAM policy"
  })
}

// Addtitional Policy to access Databricks-Datasets
// Required, in case https://docs.databricks.com/data/databricks-datasets.html are needed
resource "aws_iam_policy" "sample_data" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.prefix}-databricks-sample-data"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          "arn:aws:s3:::databricks-datasets-oregon/*",
          "arn:aws:s3:::databricks-datasets-oregon"

        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(local.tags, {
    Name = "${local.prefix}-unity-catalog IAM policy"
  })
}


resource "aws_iam_role" "metastore_data_access" {
  name                = "${local.prefix}-uc-access"
  assume_role_policy  = data.aws_iam_policy_document.passrole_for_uc.json
  managed_policy_arns = [aws_iam_policy.unity_metastore.arn, aws_iam_policy.sample_data.arn]
  tags = merge(local.tags, {
    Name = "${local.prefix}-unity-catalog IAM role"
  })
}
resource "time_sleep" "metastore_iam_role_create" {
  create_duration = "20s"

  depends_on = [aws_iam_role.metastore_data_access]
}

//--------------------------------

// Adding Users
resource "databricks_user" "unity_analyst_users" {
  provider  = databricks.mws
  for_each  = toset(var.databricks_users)
  user_name = each.value
  force     = true
}

// Creating Analyst Group
resource "databricks_group" "analyst" {
  provider     = databricks.mws
  display_name = "analyst"
  databricks_sql_access = true 
  workspace_access = true
}

resource "databricks_group_member" "analyst" {
  provider  = databricks.mws
  for_each  = toset(var.databricks_users)
  group_id  = databricks_group.analyst.id
  member_id = databricks_user.unity_analyst_users[each.value].id
}

// Creating UC Metastore
resource "databricks_metastore" "this" {
  provider      = databricks.workspace
  name          = "primary"
  storage_root  = "s3://${aws_s3_bucket.unity_metastore.id}/metastore"
  force_destroy = true
  delta_sharing_scope = "INTERNAL"
  delta_sharing_recipient_token_lifetime_in_seconds = "0"
}

resource "databricks_metastore_data_access" "this" {
  provider     = databricks.workspace
  metastore_id = databricks_metastore.this.id
  name         = aws_iam_role.metastore_data_access.name
  aws_iam_role {
    role_arn = aws_iam_role.metastore_data_access.arn
  }
  is_default = true
  depends_on = [
    databricks_metastore.this,
    time_sleep.metastore_iam_role_create
  ]
}
//-------------------

// Registering UC Metastore to Workspace ID
resource "databricks_metastore_assignment" "default_metastore" {
  provider             = databricks.workspace
  workspace_id         = var.databricks_workspace_id
  metastore_id         = databricks_metastore.this.id
}

// Creating a Catalog for Analyst Group
resource "databricks_catalog" "analyst_sandbox" {
  provider     = databricks.workspace
  metastore_id = databricks_metastore.this.id
  name         = "analyst_sandbox"
  comment      = "this catalog is managed by terraform"
  properties = {
    purpose = "analyst_testing"
  }
  depends_on = [databricks_metastore_assignment.default_metastore]
}

resource "databricks_grants" "sandbox" {
  provider = databricks.workspace
  catalog  = databricks_catalog.analyst_sandbox.name
  grant {
    // Analyst group can only gets USAGE rights to Catalog, still can't really do anything
    principal  = "analyst"
    privileges = ["USAGE"]
  }
}

// for each analyst create there own schema, with email (with it cleaned up)
resource "databricks_schema" "playground" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.analyst_sandbox.id
  for_each     = toset(var.databricks_users)
  name         = replace(replace(split("@", each.key)[0], ".", "_"), "+", "_")
  owner        = each.key 
  comment      = "this database is managed by terraform"
  properties = {
    kind = "playground schema for indvidual Analyst"
  }

  depends_on = [
    databricks_catalog.analyst_sandbox,
    databricks_group_member.analyst
  ]
  provisioner "local-exec" {
    when    = destroy
    // Need this to drop all tables in the schema before deleting it
    // hardcoded catalog for now 
    command = "python utils/drop_tables.py --catalog analyst_sandbox --schema ${replace(replace(split("@", each.key)[0], ".", "_"), "+", "_")}"
  }
}

// Grant analyst USAGE to there respective schema/database
resource "databricks_grants" "playground" {
  provider = databricks.workspace
  for_each = toset(var.databricks_users)
  schema   = databricks_schema.playground[each.key].id
  grant {
    principal  = each.key
    privileges = ["USAGE"]
  }
}

// Add Analyst Group to workspace
resource "databricks_mws_permission_assignment" "add_analyst_group" {
  provider = databricks.mws
  workspace_id = var.databricks_workspace_id
  principal_id = databricks_group.analyst.id
  permissions = ["USER"]
}

// Create SQL Endpoints for Analyst Group
resource "databricks_sql_endpoint" "small" {
  provider = databricks.workspace
  name             = "Small Endpoint for ${databricks_group.analyst.display_name}"
  cluster_size     = "Small"
  max_num_clusters = 1
  auto_stop_mins = 15

  // Needed for Unity Catalog
  channel {
    name = "CHANNEL_NAME_PREVIEW"
  }

  tags {
    custom_tags {
      key   = "Size"
      value = "Small"
    }
  }
  depends_on = [
    databricks_metastore_assignment.default_metastore
  ]
}

// Give access to Analyst Group to Stop/Restart endpoint
resource "databricks_permissions" "small_endpoint_usage" {
  provider = databricks.workspace
  sql_endpoint_id = databricks_sql_endpoint.small.id

  access_control {
    group_name       = databricks_group.analyst.display_name
    permission_level = "CAN_MANAGE"
  }
}

// Also create single user cluster policy that by default uses Unity Catalog
resource "databricks_cluster_policy" "uc_analyst_policy" {
  provider   = databricks.workspace
  name       = "${databricks_group.analyst.display_name} cluster policy"
  definition = jsonencode({
      "spark_version": {
      "type": "regex",
      "pattern": "1[0-1]\\.[0-9]*\\.x-scala.*",
      "defaultValue": "10.4.x-scala2.12"
    },
    "data_security_mode": {
      "type": "fixed",
      "value": "USER_ISOLATION",
      "hidden": true
    },
    "spark_conf.spark.databricks.unityCatalog.userIsolation.python.preview": {
      "type": "fixed",
      "value": "true"
    },
    "spark_conf.spark.databricks.dataLineage.enabled": {
      "type": "fixed",
      "value": "true"  
    }
  })
}

resource "databricks_permissions" "can_use_cluster_policy" {
  provider   = databricks.workspace
  cluster_policy_id = databricks_cluster_policy.uc_analyst_policy.id
  access_control {
    group_name       = databricks_group.analyst.display_name
    permission_level = "CAN_USE"
  }
  depends_on = [
    databricks_group.analyst
  ]
}

// Lets Create External Storage Credential to provide
// blanket read access to the data in the s3 bucket for easy ingestion
data "aws_s3_bucket" "s3_existing_data" {
  bucket = var.s3_existing_data
}

resource "aws_iam_policy" "external_data_access" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${data.aws_s3_bucket.s3_existing_data.id}-access"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          data.aws_s3_bucket.s3_existing_data.arn,
          "${data.aws_s3_bucket.s3_existing_data.arn}/*"
        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(local.tags, {
    Name = "${local.prefix}-unity-catalog external access IAM policy"
  })
}

resource "aws_iam_role" "external_data_access" {
  name                = "${local.prefix}-external-access"
  assume_role_policy  = data.aws_iam_policy_document.passrole_for_uc.json
  managed_policy_arns = [aws_iam_policy.external_data_access.arn]
  tags = merge(local.tags, {
    Name = "${local.prefix}-unity-catalog external access IAM role"
  })
}

resource "time_sleep" "external_storage_iam_role_create" {
  create_duration = "20s"

  depends_on = [aws_iam_role.external_data_access]
}

// registering the iam role as storage credential
resource "databricks_storage_credential" "external" {
  provider = databricks.workspace
  name     = aws_iam_role.external_data_access.name
  aws_iam_role {
    role_arn = aws_iam_role.external_data_access.arn
  }
  comment = "Managed by TF"
  depends_on = [
    databricks_metastore_data_access.this,
    time_sleep.external_storage_iam_role_create
  ]
}

resource "databricks_grants" "external_creds" {
  provider           = databricks.workspace
  storage_credential = databricks_storage_credential.external.id
  grant {
    principal  = databricks_group.analyst.display_name
    privileges = ["CREATE_TABLE", "READ_FILES"]
  }
  depends_on = [
    databricks_group.analyst
  ]
}

// Adding location as well to simplify querying of data
// so we don't need to use WITH(CREDENTIAL <credenial>) syntax in queries 
resource "databricks_external_location" "location" {
  provider        = databricks.workspace
  name            = "external"
  url             = "s3://${data.aws_s3_bucket.s3_existing_data.id}"
  credential_name = databricks_storage_credential.external.id
  comment         = "Managed by TF"
  depends_on = [
    databricks_group.analyst
  ]
}

resource "databricks_grants" "external_location" {
  provider          = databricks.workspace
  external_location = databricks_external_location.location.id
  grant {
    principal  = databricks_group.analyst.display_name
    privileges = ["CREATE_TABLE", "READ_FILES"]
  }
  depends_on = [
    databricks_group.analyst
  ]
}