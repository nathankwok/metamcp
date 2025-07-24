# Secret Manager Configuration for MetaMCP

This directory contains instructions for setting up secrets in Google Cloud Secret Manager for the MetaMCP Cloud Run deployment.

## Required Secrets

The following secrets need to be created in Google Cloud Secret Manager before deploying MetaMCP:

### 1. Database Password
**Secret Name:** `metamcp-db-password-{environment}`
**Description:** Password for the PostgreSQL database user
**Usage:** Backend service for database connections

```bash
# Create the secret
gcloud secrets create metamcp-db-password-production --data-file=-
# Then enter the password when prompted (or pipe from a file)
```

### 2. Database URL
**Secret Name:** `metamcp-database-url-{environment}`
**Description:** Complete database connection string
**Usage:** Backend service for database connections
**Format:** `postgresql://username:password@/database?host=/cloudsql/project:region:instance`

```bash
# This secret is automatically created by Terraform
# No manual action required
```

### 3. Better Auth Secret
**Secret Name:** `metamcp-better-auth-secret-{environment}`
**Description:** Secret key for Better Auth authentication
**Usage:** Backend service for session management and authentication

```bash
# Generate a secure random secret
openssl rand -hex 32 | gcloud secrets create metamcp-better-auth-secret-production --data-file=-
```

### 4. Additional Secrets (Optional)

You may need to create additional secrets based on your MCP server configurations:

#### API Keys for External Services
```bash
# Example: OpenAI API Key
echo "your-openai-api-key" | gcloud secrets create metamcp-openai-api-key-production --data-file=-

# Example: Anthropic API Key
echo "your-anthropic-api-key" | gcloud secrets create metamcp-anthropic-api-key-production --data-file=-
```

#### Webhook Secrets
```bash
# Example: GitHub webhook secret
echo "your-webhook-secret" | gcloud secrets create metamcp-webhook-secret-production --data-file=-
```

## Secret Management Commands

### List all secrets
```bash
gcloud secrets list --filter="name:metamcp"
```

### View secret versions
```bash
gcloud secrets versions list metamcp-db-password-production
```

### Update a secret
```bash
echo "new-secret-value" | gcloud secrets versions add metamcp-db-password-production --data-file=-
```

### Delete a secret
```bash
gcloud secrets delete metamcp-db-password-production
```

### Grant access to service accounts
```bash
# Grant access to backend service account
gcloud secrets add-iam-policy-binding metamcp-db-password-production \
    --member="serviceAccount:metamcp-backend-production@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
```

## Environment Variables

The following environment variables in the backend service will automatically reference these secrets:

```yaml
# In backend environment configuration
env:
  - name: DB_PASSWORD
    value_from:
      secret_key_ref:
        name: metamcp-db-password-production
        key: latest
  
  - name: DATABASE_URL
    value_from:
      secret_key_ref:
        name: metamcp-database-url-production
        key: latest
  
  - name: BETTER_AUTH_SECRET
    value_from:
      secret_key_ref:
        name: metamcp-better-auth-secret-production
        key: latest
```

## Security Best Practices

### 1. Use Different Secrets for Different Environments
Always use environment-specific secrets:
- `metamcp-db-password-development`
- `metamcp-db-password-staging`
- `metamcp-db-password-production`

### 2. Rotate Secrets Regularly
Set up a schedule to rotate sensitive secrets:

```bash
# Create a new version
echo "new-password" | gcloud secrets versions add metamcp-db-password-production --data-file=-

# Update the database user password
gcloud sql users set-password metamcp_user \
    --instance=metamcp-db-production \
    --password=new-password
```

### 3. Use IAM for Access Control
Grant minimal necessary permissions:

```bash
# Only grant access to specific service accounts
gcloud secrets add-iam-policy-binding SECRET_NAME \
    --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor"
```

### 4. Monitor Secret Access
Enable audit logging to monitor secret access:

```bash
# View audit logs
gcloud logging read 'resource.type="secretmanager.googleapis.com/Secret"'
```

## Terraform Integration

If you're using Terraform, secrets can be managed through the configuration:

```hcl
# In terraform/secrets.tf (not included by default for security)
resource "google_secret_manager_secret" "api_key" {
  secret_id = "metamcp-api-key-${var.environment}"
  
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_key" {
  secret      = google_secret_manager_secret.api_key.id
  secret_data = var.api_key_value
}
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Check IAM permissions
   gcloud secrets get-iam-policy SECRET_NAME
   ```

2. **Secret Not Found**
   ```bash
   # Verify secret exists
   gcloud secrets describe SECRET_NAME
   ```

3. **Service Account Access**
   ```bash
   # Test service account access
   gcloud auth activate-service-account --key-file=SERVICE_ACCOUNT_KEY.json
   gcloud secrets versions access latest --secret=SECRET_NAME
   ```

### Debug Commands

```bash
# Test secret access from Cloud Run
gcloud run services update SERVICE_NAME \
    --set-env-vars="DEBUG_SECRET=true" \
    --region=REGION

# View Cloud Run logs
gcloud logging read 'resource.type="cloud_run_revision"' --limit=50
```

## Migration from Other Systems

### From Environment Variables
If you currently use environment variables for secrets:

1. Create secrets in Secret Manager
2. Update environment configuration files
3. Redeploy services
4. Remove environment variables from deployment scripts

### From External Secret Management
If you use other secret management systems, create a migration script to transfer secrets to Google Cloud Secret Manager.

## Support

For issues with Secret Manager:
- [Google Cloud Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Secret Manager Pricing](https://cloud.google.com/secret-manager/pricing)
- [IAM Roles for Secret Manager](https://cloud.google.com/secret-manager/docs/access-control)