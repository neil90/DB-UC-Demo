-- listing data in bucket with storage credential
LIST 's3://neilp-streaming-bucket/' WITH (CREDENTIAL `demo2rv4bm-external-access`);

-- -- Accessing data in bucket with storage credential
SELECT * FROM delta.`s3://neilp-streaming-bucket/tmp/testtable`
WITH (CREDENTIAL `demo2rv4bm-external-access`);

-- listing data in bucket with external location created
LIST 's3://neilp-streaming-bucket/';

-- -- Accessing data in bucket with external location
SELECT * FROM delta.`s3://neilp-streaming-bucket/tmp/testtable`;

------ Bringing data into managed UC-----------
-- using storage credential directly
CREATE OR REPLACE TABLE analyst_sandbox.viren_patel_analyst1.testtable AS 
SELECT *
FROM delta.`s3://neilp-streaming-bucket/tmp/testtable`
WITH (CREDENTIAL `demo2rv4bm-external-access`);

-- using external location we registered
CREATE OR REPLACE TABLE analyst_sandbox.viren_patel_analyst1.testtable AS 
SELECT *
FROM delta.`s3://neilp-streaming-bucket/tmp/testtable`;
