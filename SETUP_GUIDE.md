# PostgreSQL S3 Backup & Restore - Setup Guide

Complete guide for setting up and using the PostgreSQL S3 backup system.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Configuration](#configuration)
4. [Creating Backups](#creating-backups)
5. [Restoring Backups](#restoring-backups)
6. [Troubleshooting](#troubleshooting)
7. [Common Issues & Solutions](#common-issues--solutions)

---

## Prerequisites

### Required Software

- **PostgreSQL** (running locally or in Docker)
- **AWS CLI** v2+
- **pg_dump** and **pg_restore** tools
- **Bash** shell

### AWS Requirements

- AWS Account with S3 access
- IAM user with S3 permissions
- S3 bucket created for storing backups

### Required AWS Permissions

Your IAM user needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

---

## Initial Setup

### 1. Clone or Navigate to Project

```bash
cd /home/ubuntu/pg-s3-backup
```

### 2. Verify Script Permissions

```bash
chmod +x pg-s3-backup.sh
chmod +x bin/*.sh
chmod +x lib/*.sh
```

### 3. Run Initial Configuration

```bash
./pg-s3-backup.sh config
```

Or configure individual components:
```bash
# Configure PostgreSQL (source database for backups)
./pg-s3-backup.sh config
# Select option 1

# Configure AWS credentials
./pg-s3-backup.sh config
# Select option 3

# Configure S3 bucket
./pg-s3-backup.sh config
# Select option 4
```

---

## Configuration

### 1. PostgreSQL Source Configuration (for Backups)

**Required Information:**
- Host: e.g., `localhost` or Docker container IP
- Port: e.g., `5432`
- Database name: e.g., `mas`
- Username: e.g., `postgres` or `shubham`
- Password: (your database password)

**For Docker PostgreSQL:**
```bash
# Find your Docker container
docker ps | grep postgres

# Use localhost if port is mapped (0.0.0.0:5432->5432/tcp)
# Or use container IP
docker inspect <container-id> | grep IPAddress
```

**Config File:** `config/postgres.conf`

### 2. AWS Credentials Configuration

**Steps to Get AWS Credentials:**

1. Go to [AWS Console → IAM](https://console.aws.amazon.com/iam/)
2. Click **Users** → Select your user
3. Click **Security credentials** tab
4. Click **Create access key**
5. Choose **Application running outside AWS**
6. Copy the **Access key ID** and **Secret access key** (save immediately!)

**Required Information:**
- AWS Access Key ID: Starts with `AKIA...`
- Secret Access Key: Long string (copy before closing!)
- AWS Region: e.g., `ap-south-1`, `us-east-1`

**Config File:** `config/aws.conf`

⚠️ **Important:** Keep your AWS credentials secure. The config file is set to 600 permissions (owner read/write only).

### 3. S3 Bucket Configuration

**Required Information:**
- S3 Bucket Name: e.g., `mr-mentor-database-backup`
- Backup Path Prefix: e.g., `postgres-backups`

**S3 Structure:**
```
s3://your-bucket-name/postgres-backups/YYYY-MM-DD/backup_file.dump
```

**Config File:** `config/s3.conf`

### 4. PostgreSQL Destination Configuration (Optional - for Restores)

If restoring to a different database:

```bash
./pg-s3-backup.sh config
# Select option 2
```

**Config File:** `config/postgres-dest.conf`

---

## Creating Backups

### Interactive Backup

```bash
./pg-s3-backup.sh backup
```

### Backup with Options

```bash
# Compressed backup
./pg-s3-backup.sh backup --compress

# Schema only
./pg-s3-backup.sh backup --schema-only

# Data only
./pg-s3-backup.sh backup --data-only

# Plain SQL format (instead of custom format)
./pg-s3-backup.sh backup --plain
```

### View Current Configuration

```bash
./pg-s3-backup.sh status
```

### Setup Automated Backups (Cron)

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/ubuntu/pg-s3-backup/pg-s3-backup.sh backup --compress

# Add backup every 6 hours
0 */6 * * * /home/ubuntu/pg-s3-backup/pg-s3-backup.sh backup --compress
```

---

## Restoring Backups

### List Available Backups

```bash
./pg-s3-backup.sh list
```

**Example Output:**
```
[1] mas_backup_20260104_050718.dump
     Size: 159686 | Date: 2026-01-03 23:37:20
[2] mas_backup_20260104_045617.dump
     Size: 159686 | Date: 2026-01-03 23:26:18
[3] mas_backup_20260104_044348.dump
     Size: 159686 | Date: 2026-01-03 23:17:09
```

### Interactive Restore

```bash
./pg-s3-backup.sh restore
```

Select a backup from the list and confirm.

### Direct Restore with S3 URI

```bash
./pg-s3-backup.sh restore s3://bucket-name/path/to/backup.dump
```

### Clean Restore (Drops Existing Data)

⚠️ **Warning:** This will DELETE all existing data in the database!

```bash
./pg-s3-backup.sh restore --clean s3://bucket-name/path/to/backup.dump
```

### Restore to New Database

```bash
./pg-s3-backup.sh restore --create-db s3://bucket-name/path/to/backup.dump
```

### Manual Restore (Using pg_restore directly)

If the script fails, you can restore manually:

```bash
# Download from S3
aws s3 cp s3://bucket-name/path/backup.dump /tmp/backup.dump

# Restore to database
export PGPASSWORD="your-password"
pg_restore -h localhost -p 5432 -U username \
  -d database-name \
  --clean --if-exists \
  --no-owner --no-acl \
  -v /tmp/backup.dump
```

---

## Troubleshooting

### Check Configuration

```bash
./pg-s3-backup.sh status
```

This shows all current configurations:
- PostgreSQL source (for backups)
- PostgreSQL destination (for restores)
- AWS credentials
- S3 bucket details

### View Logs

```bash
# View all logs
./pg-s3-backup.sh logs

# Log files are stored in:
ls -lh logs/
```

### Health Check

```bash
./pg-s3-backup.sh health
```

### Test Database Connection

```bash
export PGPASSWORD="your-password"
psql -h localhost -U username -d database-name -c "SELECT 1;"
```

### Test AWS Credentials

```bash
# Load your AWS config
source config/aws.conf

# Test S3 access
aws s3 ls s3://your-bucket-name/
```

---

## Common Issues & Solutions

### Issue 1: "No backups found in S3"

**Cause:** AWS credentials are invalid or expired.

**Solution:**
1. Go to AWS Console → IAM → Your User → Security Credentials
2. Create a new access key
3. Update configuration:
   ```bash
   ./pg-s3-backup.sh config
   # Select option 3 (AWS Credentials)
   ```
4. Or manually edit `config/aws.conf`

### Issue 2: "InvalidAccessKeyId"

**Cause:** The access key ID doesn't exist in AWS or was deleted.

**Solution:**
- Verify the access key is correct
- Create a new access key in AWS Console
- Update `config/aws.conf` with new credentials

### Issue 3: "relation already exists" (Restore Errors)

**Cause:** Database already has existing tables/data.

**Solution:**
Use the `--clean` flag to drop existing data:
```bash
./pg-s3-backup.sh restore --clean s3://bucket/path/backup.dump
```

Or manually clean the database:
```bash
export PGPASSWORD="your-password"
psql -h localhost -U username -d database-name \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
```

### Issue 4: "connection refused" to PostgreSQL

**Cause:** PostgreSQL is not running or wrong host/port.

**Solution:**

**If using Docker:**
```bash
# Check if PostgreSQL container is running
docker ps | grep postgres

# Start the container if stopped
docker start <container-name>

# Check port mapping
docker port <container-name>
```

**If PostgreSQL is local:**
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Start PostgreSQL
sudo systemctl start postgresql
```

### Issue 5: "could not connect to server"

**Cause:** Host is set to `localhost` but PostgreSQL is in Docker.

**Solution:**

Use `127.0.0.1` or `0.0.0.0` instead of `localhost`:
```bash
# Edit config
./pg-s3-backup.sh config
# Select option 1 (PostgreSQL)
# Use "127.0.0.1" as host (not "localhost")
```

### Issue 6: Script Permission Denied

**Cause:** Script files don't have execute permissions.

**Solution:**
```bash
chmod +x pg-s3-backup.sh
chmod +x bin/*.sh
chmod +x lib/*.sh
```

### Issue 7: AWS CLI Not Found

**Cause:** AWS CLI is not installed.

**Solution:**
```bash
# Install AWS CLI on Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version
```

### Issue 8: pg_restore: "duplicate key value violates unique constraint"

**Cause:** Restoring to database that already has data.

**Solution:**
```bash
# Drop and recreate database
export PGPASSWORD="your-password"
psql -h localhost -U postgres -d postgres \
  -c "DROP DATABASE database_name;"
psql -h localhost -U postgres -d postgres \
  -c "CREATE DATABASE database_name OWNER username;"

# Then restore again
./pg-s3-backup.sh restore --clean s3://bucket/path/backup.dump
```

---

## Quick Reference

### Configuration Files Location

```
pg-s3-backup/
├── config/
│   ├── postgres.conf          # Source DB (for backups)
│   ├── postgres-dest.conf     # Destination DB (for restores)
│   ├── aws.conf               # AWS credentials
│   └── s3.conf                # S3 bucket settings
├── backups/                   # Local backup storage
├── logs/                      # Log files
└── pg-s3-backup.sh           # Main script
```

### Main Commands

```bash
# Backup
./pg-s3-backup.sh backup                    # Interactive backup
./pg-s3-backup.sh backup --compress         # Compressed backup

# Restore
./pg-s3-backup.sh restore                   # Interactive restore
./pg-s3-backup.sh restore --clean           # Clean restore (drops existing)
./pg-s3-backup.sh restore s3://bucket/path  # Direct restore

# List & Status
./pg-s3-backup.sh list                      # List S3 backups
./pg-s3-backup.sh status                    # Show configuration
./pg-s3-backup.sh logs                      # View logs
./pg-s3-backup.sh health                    # Health check

# Configuration
./pg-s3-backup.sh config                    # Configure all settings
```

### Reset Configuration

```bash
./pg-s3-backup.sh config
# Select option 6 (Reset Configuration)
```

Or manually delete config files:
```bash
rm config/*.conf
```

---

## Security Best Practices

1. **Never commit `config/*.conf` files** to version control
   - Already excluded in `.gitignore`

2. **Use IAM users with least privilege**
   - Only grant S3 permissions to specific buckets
   - Rotate access keys regularly

3. **Set proper file permissions**
   ```bash
   chmod 600 config/*.conf
   ```

4. **Enable S3 bucket encryption**
   - Use SSE-S3 or SSE-KMS encryption

5. **Enable S3 versioning**
   - Protect against accidental deletion

6. **Schedule regular backups**
   - Use cron jobs for automated backups

7. **Test restores regularly**
   - Verify backups work by restoring to test database

---

## Support & Logs

### Log Files

Log files are stored in `logs/` directory:
- `backup_YYYYMMDD_HHMMSS.log` - Backup logs
- `restore_YYYYMMDD_HHMMSS.log` - Restore logs
- `restore_*.log.download` - Download logs
- `restore_*.log.restore` - pg_restore output

### Debug Mode

To see detailed debug output:

```bash
# Edit lib/common.sh
# Uncomment or add: set -x

# Or run with bash debug
bash -x ./pg-s3-backup.sh backup
```

---

## Summary: Complete Setup Workflow

1. **Install prerequisites** (PostgreSQL, AWS CLI, pg_dump/pg_restore)
2. **Navigate to project directory**
3. **Run configuration wizard**: `./pg-s3-backup.sh config`
4. **Configure PostgreSQL** (database to backup)
5. **Configure AWS credentials** (access key, secret, region)
6. **Configure S3 bucket** (bucket name, backup path)
7. **Test backup**: `./pg-s3-backup.sh backup`
8. **Test restore**: `./pg-s3-backup.sh restore --clean`
9. **Setup cron jobs** for automated backups (optional)
10. **Monitor logs** regularly: `./pg-s3-backup.sh logs`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-03
**Compatible with:** pg-s3-backup v1.0.0
