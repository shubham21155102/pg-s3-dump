# Server Deployment Guide

This guide covers deploying the PostgreSQL S3 Backup tool on a Linux server.

## Prerequisites

- Docker installed
- Docker Compose plugin (modern `docker compose` syntax)
- AWS credentials with S3 access
- PostgreSQL database access

## Quick Deploy

### Step 1: Install Docker (if not already installed)

```bash
# CentOS/RHEL/Amazon Linux
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user  # or your username

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

**Log out and log back in** for the group changes to take effect.

### Step 2: Pull the Docker Image

```bash
docker pull ghcr.io/shubham21155102/pg-s3-dump:latest
```

### Step 3: Create Deployment Directory

```bash
# Create a directory for the deployment
mkdir -p ~/pg-s3-backup
cd ~/pg-s3-backup
```

### Step 4: Create docker-compose.yml

Create the `docker-compose.yml` file in your deployment directory:

```bash
cat > docker-compose.yml << 'EOF'
services:
  pg-s3-backup:
    image: ghcr.io/shubham21155102/pg-s3-dump:latest
    container_name: pg-s3-backup

    environment:
      # PostgreSQL Configuration
      PGHOST: ${PGHOST}
      PGPORT: ${PGPORT:-5432}
      PGDATABASE: ${PGDATABASE}
      PGUSER: ${PGUSER}
      PGPASSWORD: ${PGPASSWORD}

      # AWS Configuration
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-us-east-1}

      # S3 Configuration
      S3_BUCKET: ${S3_BUCKET}
      S3_BACKUP_PATH: ${S3_BACKUP_PATH:-postgres-backups}
      TZ: ${TZ:-UTC}

    volumes:
      - ./backups:/app/backups
      - ./logs:/app/logs
EOF
```

### Step 5: Create .env File

```bash
cat > .env << 'EOF'
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

# Optional: Timezone
TZ=UTC
EOF
```

**Edit the `.env` file** with your actual values:

```bash
nano .env
# or
vi .env
```

### Step 6: Secure the .env File

```bash
chmod 600 .env
```

### Step 7: Run Commands

**Important**: You must be in the directory containing `docker-compose.yml` and `.env`.

```bash
cd ~/pg-s3-backup  # Your deployment directory

# Run a backup
docker compose run --rm pg-s3-backup backup

# Run a backup with compression
docker compose run --rm pg-s3-backup backup --compress

# List available backups
docker compose run --rm pg-s3-backup list

# Restore from S3 (interactive)
docker compose run --rm pg-s3-backup restore

# Restore with clean slate
docker compose run --rm pg-s3-backup restore --clean
```

## Troubleshooting

### "docker-compose: command not found"

Use the modern syntax instead:

```bash
# OLD (doesn't work on newer Docker installations)
docker-compose run --rm pg-s3-backup backup

# NEW (correct)
docker compose run --rm pg-s3-backup backup
```

Note: `docker compose` (without hyphen) is the modern syntax.

### "no configuration file provided: not found"

You are not in the directory containing `docker-compose.yml`.

```bash
# Navigate to your deployment directory first
cd ~/pg-s3-backup  # or wherever you created the directory

# Then run the command
docker compose run --rm pg-s3-backup backup
```

### "Permission denied" after pulling image

If you get permission errors:

```bash
sudo chown $USER:$(id -gn $USER) /var/run/docker.sock
```

Or use sudo (not recommended for production):

```bash
sudo docker compose run --rm pg-s3-backup backup
```

### Verify Docker is Working

```bash
# Check Docker is installed and running
docker --version
docker compose version

# List pulled images
docker images | grep pg-s3-dump
```

## Running with Docker Directly (Alternative)

If you don't want to use docker-compose:

```bash
docker run --rm \
  -e PGHOST=your-postgres-host \
  -e PGDATABASE=your_database \
  -e PGUSER=your_user \
  -e PGPASSWORD=your_password \
  -e AWS_ACCESS_KEY_ID=your_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret \
  -e S3_BUCKET=your-bucket \
  -v $(pwd)/backups:/app/backups \
  ghcr.io/shubham21155102/pg-s3-dump:latest backup
```

## Setting Up Automated Backups (Cron)

### Option 1: Using System Cron

```bash
# Open crontab
crontab -e

# Add this line for daily backups at 2 AM
0 2 * * * cd ~/pg-s3-backup && docker compose run --rm pg-s3-backup backup --compress >> ~/pg-s3-backup/logs/cron.log 2>&1
```

### Option 2: Create a Wrapper Script

```bash
cat > ~/pg-s3-backup/backup.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
/opt/docker-compose.sh  # see below
EOF

chmod +x ~/pg-s3-backup/backup.sh

# Add to crontab
# 0 2 * * * ~/pg-s3-backup/backup.sh
```

## Directory Structure After Deployment

```
~/pg-s3-backup/
├── docker-compose.yml     # Docker compose configuration
├── .env                    # Environment variables (secure!)
├── backups/                # Local backup storage (created automatically)
├── logs/                   # Log files (created automatically)
└── backup.sh              # Optional wrapper script
```

## Security Best Practices

1. **Never commit .env files** to version control
2. **Set restrictive permissions** on .env: `chmod 600 .env`
3. **Use IAM roles** instead of access keys when running on EC2
4. **Enable S3 encryption** at rest
5. **Rotate access keys** regularly
6. **Use separate AWS credentials** for backup operations

## Checking Logs

```bash
# View container logs
docker compose logs pg-s3-backup

# View application logs
cat ~/pg-s3-backup/logs/*.log

# Follow logs in real-time
tail -f ~/pg-s3-backup/logs/backup_*.log
```
