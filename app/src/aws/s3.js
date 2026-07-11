import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { config } from "../config.js";

// Default credential provider chain: the pod-identity webhook injects
// AWS_ROLE_ARN / AWS_WEB_IDENTITY_TOKEN_FILE from the ServiceAccount annotation.
const s3 = new S3Client({ region: config.awsRegion });

export async function uploadAttachment({ key, body, contentType }) {
  await s3.send(
    new PutObjectCommand({
      Bucket: config.s3BucketName,
      Key: key,
      Body: body,
      ContentType: contentType,
    })
  );
}

export async function presignAttachmentUrl(key, expiresInSeconds = 300) {
  const command = new GetObjectCommand({ Bucket: config.s3BucketName, Key: key });
  return getSignedUrl(s3, command, { expiresIn: expiresInSeconds });
}

export async function deleteAttachment(key) {
  await s3.send(new DeleteObjectCommand({ Bucket: config.s3BucketName, Key: key }));
}
