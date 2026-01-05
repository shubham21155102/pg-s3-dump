# PostgreSQL S3 Backup Manager

A comprehensive, organized solution for backing up PostgreSQL databases to Amazon S3 and restoring them.

## Features

- **Backup to S3**: Dump PostgreSQL databases directly to Amazon S3
- **Restore from S3**: Download and restore databases from S3 backups
- **Interactive Menu**: User-friendly CLI interface for all operations
- **Configuration Management**: Secure credential storage
- **Multiple Backup Formats**: Support for custom format and plain SQL dumps
- **Compression**: Optional gzip compression for backups
- **Health Checks**: Validate connections and setup
- **Backup History**: Track and view backup history

## Directory Structure

```
pg-s3-backup/
├── pg-s3-backup.sh          # Main entry point (interactive menu)
├── README.md                # This file
├── bin/
│   ├── backup-to-s3.sh      # Backup database to S3
│   └── restore-from-s3.sh   # Restore database from S3
├── lib/
│   ├── common.sh            # Common functions and utilities
│   └── config.sh            # Configuration management
├── config/                  # Configuration files (auto-generated)
│   ├── postgres.conf
│   ├── aws.conf
│   └── s3.conf
├── backups/                 # Local backup storage
└── logs/                    # Log files
```

## Requirements

- **PostgreSQL client tools**: `pg_dump`, `pg_restore`, `psql`
- **AWS CLI**: `aws` command
- **Optional**: `jq` for better JSON parsing

### Installation

```bash
# macOS
brew install postgresql awscli jq

# Ubuntu/Debian
apt-get install postgresql-client awscli jq

# CentOS/RHEL
yum install postgresql awscli jq
```

## Quick Start

### Option 1: Docker (Recommended)

The easiest way to use this tool is with Docker:

```bash
# Pull the image
docker pull ghcr.io/shubham21155102/pg-s3-dump:latest

# Set up environment variables
cp .env.example .env
# Edit .env with your credentials

# Run a backup
docker-compose run --rm pg-s3-backup backup
```

See [Docker Usage](#docker-usage) below for more details.

### Option 2: Standalone Scripts

#### 1. Make Scripts Executable

```bash
cd pg-s3-backup
chmod +x pg-s3-backup.sh bin/*.sh
```

#### 2. Run the Interactive Menu

```bash
./pg-s3-backup.sh
```

#### 3. Configure Settings (First Time)

Select option `4` from the menu to configure:
- PostgreSQL connection details
- AWS credentials
- S3 bucket information

## Docker Usage

### Using Docker Compose (Recommended)

1. Copy the example environment file:

```bash
cp .env.example .env
```

2. Edit `.env` with your credentials:

```bash
# PostgreSQL Configuration
PGHOST=your-postgres-host.example.com
PGPORT=5432
PGDATABASE=your_database_name
PGUSER=your_db_user
PGPASSWORD=your_secure_password

# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_DEFAULT_REGION=us-east-1

# S3 Configuration
S3_BUCKET=your-backup-bucket
S3_BACKUP_PATH=postgres-backups
```

3. Run commands:

```bash
# Backup to S3
docker-compose run --rm pg-s3-backup backup

# Backup with compression
docker-compose run --rm pg-s3-backup backup --compress

# List available backups
docker-compose run --rm pg-s3-backup list

# Restore from S3 (interactive)
docker-compose run --rm pg-s3-backup restore

# Restore with clean slate
docker-compose run --rm pg-s3-backup restore --clean
```

### Using Docker Directly

```bash
# Backup to S3
docker run --rm \
  -e PGHOST=db.example.com \
  -e PGDATABASE=mydb \
  -e PGUSER=admin \
  -e PGPASSWORD=secret \
  -e AWS_ACCESS_KEY_ID=AKIA... \
  -e AWS_SECRET_ACCESS_KEY=secret \
  -e S3_BUCKET=my-backups \
  ghcr.io/shubham21155102/pg-s3-dump:latest backup

# List backups
docker run --rm \
  -e AWS_ACCESS_KEY_ID=AKIA... \
  -e AWS_SECRET_ACCESS_KEY=secret \
  -e S3_BUCKET=my-backups \
  ghcr.io/shubham21155102/pg-s3-dump:latest list

# Restore from S3
docker run --rm -it \
  -e PGHOST=db.example.com \
  -e PGDATABASE=mydb \
  -e PGUSER=admin \
  -e PGPASSWORD=secret \
  -e AWS_ACCESS_KEY_ID=AKIA... \
  -e AWS_SECRET_ACCESS_KEY=secret \
  -e S3_BUCKET=my-backups \
  ghcr.io/shubham21155102/pg-s3-dump:latest restore --clean
```

### Automated Backups with Cron

Use the cron service for scheduled backups:

```bash
# Enable cron profile
docker-compose --profile cron up -d
```

Or set a custom schedule in `.env`:

```bash
# Daily at 2 AM
CRON_SCHEDULE="0 2 * * *"

# Every 6 hours
CRON_SCHEDULE="0 */6 * * *"

# Weekly on Sunday at 3 AM
CRON_SCHEDULE="0 3 * * 0"
```

### Building Locally

```bash
# Build the image
docker build -t pg-s3-backup:latest .

# Or use docker-compose to build
docker-compose build
```

### Container Images

Images are available at:
- `ghcr.io/shubham21155102/pg-s3-dump:latest` - Latest release
- `ghcr.io/shubham21155102/pg-s3-dump:v1.0.0` - Versioned releases

Multi-platform support: `linux/amd64`, `linux/arm64`

## Usage

### Interactive Menu Mode

```bash
./pg-s3-backup.sh
```

Menu options:
1. **Backup Database to S3** - Create a new backup
2. **Restore Database from S3** - Restore from a backup
3. **List Available Backups** - View backups in S3
4. **Configure Settings** - Update configuration
5. **Show Current Configuration** - View current settings
6. **View Backup Logs** - Check log files
7. **Maintenance Tools** - Health checks and cleanup

### Command Line Mode

```bash
# Backup to S3
./pg-s3-backup.sh backup

# Backup with compression
./pg-s3-backup.sh backup --compress

# Backup schema only
./pg-s3-backup.sh backup --schema-only

# Restore from S3 (interactive selection)
./pg-s3-backup.sh restore

# Restore with clean slate (drops existing data)
./pg-s3-backup.sh restore --clean

# Restore specific backup
./pg-s3-backup.sh restore s3://my-bucket/postgres-backups/2024-01-04/db.dump

# List available backups
./pg-s3-backup.sh list

# Show configuration
./pg-s3-backup.sh status

# Run health check
./pg-s3-backup.sh health
```

### Direct Script Usage

```bash
# Backup directly
./bin/backup-to-s3.sh [OPTIONS]

# Restore directly
./bin/restore-from-s3.sh [OPTIONS] [S3_URI]
```

## Configuration Options

### PostgreSQL Configuration

Stored in `config/postgres.conf`:
- **Host**: Database server address
- **Port**: Database port (default: 5432)
- **Database**: Database name
- **User**: Username
- **Password**: Password

### AWS Configuration

Stored in `config/aws.conf`:
- **Access Key ID**: AWS access key
- **Secret Access Key**: AWS secret key
- **Region**: AWS region (default: us-east-1)

### S3 Configuration

Stored in `config/s3.conf`:
- **Bucket**: S3 bucket name
- **Backup Path**: Path prefix for backups (default: postgres-backups)

## Backup Options

| Option | Description |
|--------|-------------|
| `--plain` | Use plain SQL format instead of custom format |
| `--schema-only` | Backup schema only (no data) |
| `--data-only` | Backup data only (no schema) |
| `--compress` | Compress the backup with gzip |
| `--no-upload` | Create local backup only, skip S3 upload |

## Restore Options

| Option | Description |
|--------|-------------|
| `--clean` | Drop existing schema before restore |
| `--create-db` | Create database if it doesn't exist |
| `--file URI` | Specify exact S3 URI to restore |
| `--list` | List available backups |

## S3 Backup Organization

Backups are organized in S3 as:

```
s3://your-bucket/postgres-backups/YYYY-MM-DD/dbname_backup_YYYYMMDD_HHMMSS.dump
```

Example:
```
s3://my-backups/postgres-backups/2024-01-04/mydb_backup_20240104_143022.dump
```

## Security Notes

1. Configuration files are stored with `600` permissions (read/write for owner only)
2. Passwords are never displayed in output
3. AWS credentials are exported as environment variables only during execution
4. Consider using AWS IAM roles instead of access keys when running on EC2

## Troubleshooting

### Database Connection Failed

- Verify PostgreSQL is accessible from your machine
- Check firewall rules allow outbound connections to PostgreSQL port
- Ensure the database user has necessary permissions

### AWS/S3 Access Denied

- Verify AWS credentials are correct
- Check IAM permissions for S3 operations
- Ensure the bucket exists and you have access

### Restore Failed

- Ensure the target database exists (use `--create-db` if needed)
- Check for schema conflicts (use `--clean` to drop existing schema)
- Verify the backup file format matches the restore method

## Examples

### Complete Backup and Restore Workflow

```bash
# 1. Initial configuration
./pg-s3-backup.sh config all

# 2. Create a backup
./pg-s3-backup.sh backup --compress

# 3. List available backups
./pg-s3-backup.sh list

# 4. Restore to a different database
PG_HOST=new-db-host PG_DATABASE=new_db ./bin/restore-from-s3.sh --clean
```

### Scheduled Backups (Cron)

```bash
# Add to crontab with: crontab -e
# Daily backup at 2 AM
0 2 * * * /path/to/pg-s3-backup/pg-s3-backup.sh backup --compress >> /var/log/pg-backup.log 2>&1
```

### Environment Variable Override

```bash
# Override config with environment variables
PG_HOST="prod-db.example.com" \
PG_DATABASE="production" \
PG_PASSWORD="secret" \
./pg-s3-backup.sh backup
```

## License

This script is provided as-is for database backup management.
# pg-s3-backup
# dump-db-package
# pg-s3-dump
