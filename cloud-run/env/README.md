# Environment Configuration

This directory contains environment configuration files for the MetaMCP Cloud Run deployment. The files use environment variable substitution to allow dynamic configuration during deployment.

## Files

- `backend.env.yaml` - Backend service environment variables (development)
- `backend.prod.env.yaml` - Backend service environment variables (production)
- `frontend.env.yaml` - Frontend service environment variables (development)
- `frontend.prod.env.yaml` - Frontend service environment variables (production)

## Environment Variable Substitution

All configuration files support environment variable substitution using the format:
```yaml
VARIABLE_NAME: "${ENV_VAR_NAME:-default_value}"
```

Where:
- `ENV_VAR_NAME` is the environment variable to read from
- `default_value` is used if the environment variable is not set

## Required Environment Variables

### Backend Services

#### Database Configuration
- `DB_HOST` - Database host (Cloud SQL connection string or IP)
- `DB_PORT` - Database port (default: 5432)
- `DB_NAME` - Database name (dev: metamcp_dev, prod: metamcp_prod)
- `DB_USER` - Database username
- `DB_PASSWORD` - Database password (set via Secret Manager)

#### Authentication
- `BETTER_AUTH_URL` - Backend service URL for authentication
- `BETTER_AUTH_SECRET` - Authentication secret (set via Secret Manager)

#### Redis Configuration
- `REDIS_URL` - Redis connection URL for caching and sessions
- `REDIS_PASSWORD` - Redis password (set via Secret Manager if auth enabled)

#### CORS Configuration
- `CORS_ORIGINS` - Allowed CORS origins (dev: *, prod: specific domains)

### Frontend Services

#### Application Configuration
- `NEXT_PUBLIC_BACKEND_URL` - Backend service URL (set during deployment)
- `NEXT_PUBLIC_APP_NAME` - Application name (default: MetaMCP)
- `NEXT_PUBLIC_APP_VERSION` - Application version

#### Authentication (Optional)
- `NEXT_PUBLIC_AUTH_DOMAIN` - Auth0 domain
- `NEXT_PUBLIC_AUTH_CLIENT_ID` - Auth0 client ID

#### Error Tracking (Production)
- `NEXT_PUBLIC_SENTRY_DSN` - Sentry DSN for error tracking
- `NEXT_PUBLIC_SENTRY_ENVIRONMENT` - Sentry environment

#### Analytics (Production)
- `NEXT_PUBLIC_GA_TRACKING_ID` - Google Analytics tracking ID
- `NEXT_PUBLIC_GTM_ID` - Google Tag Manager ID

## Setting Environment Variables

### During Deployment

Environment variables can be set during deployment using:

1. **Cloud Run deployment scripts:**
   ```bash
   export DB_HOST="/cloudsql/my-project:us-central1:my-instance"
   export BETTER_AUTH_URL="https://my-backend-service-url"
   ./deploy.sh production
   ```

2. **Cloud Build substitutions:**
   ```yaml
   substitutions:
     _DB_HOST: "/cloudsql/my-project:us-central1:my-instance"
     _BETTER_AUTH_URL: "https://my-backend-service-url"
   ```

3. **Terraform variables:**
   ```hcl
   variable "db_host" {
     description = "Database host"
     type        = string
   }
   ```

### Using Secret Manager

Sensitive values like passwords and secrets should be stored in Google Secret Manager and referenced in the environment files:

```yaml
# In environment file - reference only
# DB_PASSWORD should be set via Secret Manager

# In deployment script
gcloud run services update backend \
  --update-secrets="DB_PASSWORD=db-password:latest"
```

## Environment-Specific Configurations

### Development
- Debug mode enabled
- Permissive CORS settings
- Development tools available
- Lower security requirements

### Production
- Debug mode disabled
- Restricted CORS origins
- Enhanced security headers
- Performance optimizations
- Error tracking enabled
- Analytics enabled

## Example Usage

1. **Set environment variables:**
   ```bash
   export DB_HOST="/cloudsql/my-project:us-central1:metamcp-db"
   export DB_NAME="metamcp_prod"
   export BETTER_AUTH_URL="https://metamcp-backend-12345-uc.a.run.app"
   export CORS_ORIGINS="https://metamcp-frontend-12345-uc.a.run.app"
   ```

2. **Deploy with environment variables:**
   ```bash
   ./deploy.sh production
   ```

3. **Verify configuration:**
   ```bash
   gcloud run services describe backend --region=us-central1
   ```

## Best Practices

1. **Never commit secrets to version control**
2. **Use Secret Manager for sensitive data**
3. **Set appropriate default values for non-sensitive configuration**
4. **Use environment-specific configurations (dev vs prod)**
5. **Validate required environment variables in deployment scripts**
6. **Document all required environment variables**
7. **Use meaningful variable names and descriptions**