# =============================================================================
# PostgreSQL S3 Backup - Docker Image
# =============================================================================
# This image provides PostgreSQL backup/restore functionality with S3 storage
# =============================================================================

FROM alpine:3.19

# Install required dependencies
RUN apk add --no-cache \
    postgresql-client \
    aws-cli \
    bash \
    ca-certificates \
    curl \
    jq \
    gzip

# Set working directory
WORKDIR /app

# Copy project files
COPY --chmod=755 bin/ /app/bin/
COPY --chmod=644 lib/ /app/lib/
COPY --chmod=755 docker-entrypoint.sh /app/docker-entrypoint.sh
RUN echo "dev" > /app/VERSION

# Create necessary directories
RUN mkdir -p /app/backups /app/logs /app/config

# Set environment variables
ENV APP_DIR="/app" \
    BACKUP_DIR="/app/backups" \
    LOG_DIR="/app/logs" \
    CONFIG_DIR="/app/config" \
    PATH="/app/bin:$PATH" \
    PGHOST="${PGHOST:-}" \
    PGPORT="${PGPORT:-5432}" \
    PGDATABASE="${PGDATABASE:-}" \
    PGUSER="${PGUSER:-}" \
    PGPASSWORD="${PGPASSWORD:-}" \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}" \
    AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}" \
    S3_BUCKET="${S3_BUCKET:-}" \
    S3_BACKUP_PATH="${S3_BACKUP_PATH:-postgres-backups}"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD command -v pg_dump && command -v aws || exit 1

# Set entrypoint
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default command shows help
CMD ["--help"]
