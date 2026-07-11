export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  awsRegion: process.env.AWS_REGION || "us-east-1",
  s3BucketName: process.env.S3_BUCKET_NAME,
  dbSecretArn: process.env.DB_SECRET_ARN,
  dbSecretRoleArn: process.env.DB_SECRET_ROLE_ARN,
};
