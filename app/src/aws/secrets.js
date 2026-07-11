import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { fromTokenFile } from "@aws-sdk/credential-providers";
import { config } from "../config.js";

// The DB secret lives under its own IRSA role (module.rds.db_secret_irsa_role_arn),
// trusted for the same ServiceAccount subject as the default S3 role. Since a pod
// can only get one role auto-injected via the ServiceAccount annotation, this
// client explicitly assumes the DB-secret role instead.
const dbSecretsClient = new SecretsManagerClient({
  region: config.awsRegion,
  credentials: config.dbSecretRoleArn
    ? fromTokenFile({ roleArn: config.dbSecretRoleArn })
    : undefined,
});

export async function getDbCredentials() {
  const output = await dbSecretsClient.send(
    new GetSecretValueCommand({ SecretId: config.dbSecretArn })
  );
  return JSON.parse(output.SecretString);
}
