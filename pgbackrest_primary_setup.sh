#!/bin/bash
#===============================================================================
# pgBackRest Primary Setup Script - Part 1
#
# This script handles:
# 1. Setting up pgBackRest on primary server with backup volume
# 2. Taking initial backup and creating EBS snapshot
# 3. Setting up periodic snapshots (optional)
#
# Author: Generated Script
# Version: 1.0
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default configuration - MODIFY THESE VALUES FOR YOUR ENVIRONMENT
readonly DEFAULT_PRIMARY_IP="10.40.0.24"
readonly DEFAULT_PG_VERSION="13"
readonly DEFAULT_STANZA_NAME="txn_cluster"
readonly DEFAULT_BACKUP_VOLUME_SIZE="100"
readonly DEFAULT_AWS_REGION="ap-northeast-1"
readonly DEFAULT_AVAILABILITY_ZONE="ap-northeast-1a"

# Configuration variables
PRIMARY_IP="${PRIMARY_IP:-$DEFAULT_PRIMARY_IP}"
PG_VERSION="${PG_VERSION:-$DEFAULT_PG_VERSION}"
STANZA_NAME="${STANZA_NAME:-$DEFAULT_STANZA_NAME}"
BACKUP_VOLUME_SIZE="${BACKUP_VOLUME_SIZE:-$DEFAULT_BACKUP_VOLUME_SIZE}"
AWS_REGION="${AWS_REGION:-$DEFAULT_AWS_REGION}"
AVAILABILITY_ZONE="${AVAILABILITY_ZONE:-$DEFAULT_AVAILABILITY_ZONE}"
SETUP_PERIODIC_SNAPSHOTS="${SETUP_PERIODIC_SNAPSHOTS:-true}"

# Backup scheduling configuration
BACKUP_MODE="${BACKUP_MODE:-auto}"  # auto, setup, full, incr, skip
FORCE_FULL_BACKUP="${FORCE_FULL_BACKUP:-false}"
SKIP_SNAPSHOT="${SKIP_SNAPSHOT:-false}"
SKIP_BACKUP="${SKIP_BACKUP:-false}"
CLEANUP_OLD_SNAPSHOTS="${CLEANUP_OLD_SNAPSHOTS:-true}"

# Derived configuration
readonly PG_DATA_DIR="/var/lib/pgsql/${PG_VERSION}/data"
readonly PG_BIN_DIR="/usr/pgsql-${PG_VERSION}/bin"
readonly BACKUP_MOUNT_POINT="/backup/pgbackrest"
readonly BACKUP_DEVICE="/dev/xvdb"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/pgbackrest_primary_setup_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${SCRIPT_DIR}/pgbackrest_primary_state.env"

# Global variables
BACKUP_VOLUME_ID=""
SNAPSHOT_ID=""
SCHEDULED_MODE=false

#===============================================================================
# Utility Functions
#===============================================================================

log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}[${timestamp}]${NC} ${message}" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] ✅ ${message}${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ❌ ERROR: ${message}${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] ⚠️  WARNING: ${message}${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}] ℹ️  INFO: ${message}${NC}" | tee -a "$LOG_FILE"
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command '$cmd' not found"
        exit 1
    fi
}

execute_remote() {
    local host="$1"
    local command="$2"
    local description="${3:-Executing remote command}"

    log "Executing on $host: $description"
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$host" "$command"; then
        log_success "Command executed successfully on $host"
        return 0
    else
        log_error "Command failed on $host: $command"
        return 1
    fi
}

save_state() {
    local key="$1"
    local value="$2"

    # Create or update state file
    if [ -f "$STATE_FILE" ]; then
        # Remove existing key if present
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || touch "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi

    # Add new key-value pair with proper quoting for values containing spaces
    if [[ "$value" =~ [[:space:]] ]]; then
        echo "${key}=\"${value}\"" >> "$STATE_FILE"
    else
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
    log_info "State saved: ${key}=${value}"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        log_info "State loaded from: $STATE_FILE"
    else
        log_info "No existing state file found"
    fi
}

#===============================================================================
# Smart Backup Type Detection
#===============================================================================

determine_backup_type() {
    # If backup is explicitly skipped
    if [[ "$SKIP_BACKUP" == "true" ]] || [[ "$BACKUP_MODE" == "skip" ]]; then
        echo "skip"
        return
    fi

    # If explicitly set, use that
    if [[ "$BACKUP_MODE" == "full" ]]; then
        echo "full"
        return
    elif [[ "$BACKUP_MODE" == "incr" ]]; then
        echo "incr"
        return
    elif [[ "$BACKUP_MODE" == "setup" ]]; then
        echo "full"
        return
    fi

    # Auto mode: determine based on day of week and existing backups
    local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday

    if [[ "$day_of_week" == "7" ]] || [[ "$FORCE_FULL_BACKUP" == "true" ]]; then
        # Sunday or forced full backup
        echo "full"
    else
        # Monday-Saturday: check if we have a recent full backup
        local has_recent_full
        has_recent_full=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
            if sudo -u postgres pgbackrest --stanza=$STANZA_NAME info --output=json 2>/dev/null | grep -q '\"type\":\"full\"'; then
                echo 'true'
            else
                echo 'false'
            fi
        " 2>/dev/null || echo 'false')

        if [[ "$has_recent_full" == "true" ]]; then
            echo "incr"
        else
            log_warning "No recent full backup found, taking full backup instead of incremental"
            echo "full"
        fi
    fi
}

should_run_setup() {
    # Check if this is the first run (setup mode)
    if [[ "$BACKUP_MODE" == "setup" ]]; then
        return 0
    fi

    # In scheduled mode, never run setup
    if [[ "$SCHEDULED_MODE" == "true" ]]; then
        return 1
    fi

    # Check if already configured
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        if [[ "${PGBACKREST_CONFIGURED:-false}" == "true" ]] && [[ "${INITIAL_BACKUP_COMPLETED:-false}" == "true" ]]; then
            return 1  # Setup already completed
        fi
    fi

    return 0  # Needs setup
}

#===============================================================================
# Prerequisites Check
#===============================================================================

check_prerequisites() {
    log "Checking prerequisites for primary setup..."

    # Check required commands
    check_command "aws"
    check_command "ssh"
    check_command "nc"

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI not configured properly"
        exit 1
    fi

    # Test SSH connectivity to primary
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$PRIMARY_IP" "echo 'SSH test successful'" &>/dev/null; then
        log_error "Cannot SSH to primary server $PRIMARY_IP"
        exit 1
    fi

    # Verify PostgreSQL is running on primary
    if ! ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "sudo -u postgres psql -c 'SELECT version();'" &>/dev/null; then
        log_error "PostgreSQL not accessible on primary server $PRIMARY_IP"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

#===============================================================================
# Step 1: Setup PostgreSQL for Archiving on Primary
#===============================================================================

setup_primary_archiving() {
    log "=== STEP 1: Setting up PostgreSQL archiving on primary ($PRIMARY_IP) ==="

    # Configure PostgreSQL for archiving
    execute_remote "$PRIMARY_IP" "
        # Backup original postgresql.conf
        sudo -u postgres cp $PG_DATA_DIR/postgresql.conf $PG_DATA_DIR/postgresql.conf.backup-\$(date +%Y%m%d_%H%M%S)

        # Check if archive settings already exist
        if grep -q 'pgbackrest.*archive-push' $PG_DATA_DIR/postgresql.conf; then
            echo 'Archive settings already configured'
        else
            # Add archive settings
            sudo -u postgres tee -a $PG_DATA_DIR/postgresql.conf << 'EOF'

# Archive settings for pgBackRest - Added by setup script
archive_mode = on
archive_command = 'pgbackrest --stanza=$STANZA_NAME archive-push %p'
archive_timeout = 60
max_wal_senders = 10
wal_level = replica
EOF
        fi
    " "Configuring PostgreSQL for archiving"

    # Check if restart is actually needed
    local restart_needed
    restart_needed=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
        # Check if archive mode is already active
        ARCHIVE_MODE=\$(sudo -u postgres psql -t -c 'SHOW archive_mode;' 2>/dev/null | xargs || echo 'off')
        WAL_LEVEL=\$(sudo -u postgres psql -t -c 'SHOW wal_level;' 2>/dev/null | xargs || echo 'replica')

        if [ \"\$ARCHIVE_MODE\" = \"on\" ] && [ \"\$WAL_LEVEL\" = \"replica\" ]; then
            echo 'false'  # No restart needed
        else
            echo 'true'   # Restart needed
        fi
    " 2>/dev/null || echo 'true')

    if [ "$restart_needed" = "false" ]; then
        log_info "PostgreSQL already configured with archive mode - no restart needed"
    else
        log_info "PostgreSQL restart required to apply archive settings"

        # Restart PostgreSQL with improved error handling
        execute_remote "$PRIMARY_IP" "
            echo 'Restarting PostgreSQL to apply archive settings...'

            # First, verify configuration syntax before attempting restart
            echo 'Verifying PostgreSQL configuration syntax...'
            if ! sudo -u postgres $PG_BIN_DIR/postgres --check-config -D $PG_DATA_DIR 2>/dev/null; then
                echo 'ERROR: PostgreSQL configuration has syntax errors!'
                echo 'Restoring backup configuration...'
                sudo -u postgres cp $PG_DATA_DIR/postgresql.conf.backup-* $PG_DATA_DIR/postgresql.conf 2>/dev/null || true
                exit 1
            fi

            # Simple restart approach
            echo 'Stopping PostgreSQL service...'
            sudo systemctl stop postgresql-${PG_VERSION}.service

            # Wait for clean shutdown
            sleep 10

            # Start PostgreSQL service
            echo 'Starting PostgreSQL service...'
            sudo systemctl start postgresql-${PG_VERSION}.service

            # Wait for startup and verify
            sleep 15

            # Check if service is running
            if ! sudo systemctl is-active --quiet postgresql-${PG_VERSION}.service; then
                echo 'PostgreSQL service failed to start. Getting detailed error information...'

                # Show systemctl status
                echo '=== SystemCtl Status ==='
                sudo systemctl status postgresql-${PG_VERSION}.service || true

                # Show recent journal entries
                echo '=== Recent Journal Entries ==='
                sudo journalctl -u postgresql-${PG_VERSION}.service --no-pager -n 20 || true

                # Check PostgreSQL logs
                echo '=== PostgreSQL Logs ==='
                if [ -f /var/log/postgresql/postgresql.log ]; then
                    tail -20 /var/log/postgresql/postgresql.log || true
                fi

                if [ -d $PG_DATA_DIR/log ]; then
                    find $PG_DATA_DIR/log -name \"*.log\" -mtime -1 -exec tail -10 {} \; 2>/dev/null || true
                fi

                exit 1
            fi

            echo 'PostgreSQL service restarted successfully'
        " "Restarting PostgreSQL service"
    fi

    # Verify archive settings
    execute_remote "$PRIMARY_IP" "
        # Wait a bit more for PostgreSQL to be fully ready
        sleep 10

        echo 'Verifying PostgreSQL is accepting connections...'
        sudo -u postgres psql -c 'SELECT 1;' || {
            echo 'PostgreSQL not accepting connections yet, waiting longer...'
            sleep 20
            sudo -u postgres psql -c 'SELECT 1;'
        }

        echo 'Verifying archive configuration...'
        sudo -u postgres psql -c \"SHOW archive_mode;\" &&
        sudo -u postgres psql -c \"SHOW archive_command;\" &&
        sudo -u postgres psql -c \"SHOW wal_level;\"
    " "Verifying archive configuration"

    save_state "ARCHIVING_CONFIGURED" "true"
    log_success "Primary server archiving configuration completed"
}

#===============================================================================
# Step 2: Mount Backup Volume on Primary
#===============================================================================

setup_backup_volume() {
    log "=== STEP 2: Setting up backup volume on primary ($PRIMARY_IP) ==="

    # Check current mount situation and decide what to do
    execute_remote "$PRIMARY_IP" "
        echo '=== Checking existing backup volume setup ==='

        # Check if mount point already exists and is mounted
        if mount | grep -q '$BACKUP_MOUNT_POINT'; then
            MOUNT_SOURCE=\$(mount | grep '$BACKUP_MOUNT_POINT' | awk '{print \$1}')
            echo \"Backup mount point already exists and is mounted from: \$MOUNT_SOURCE\"

            # Check if it has the required structure
            if [ -d '$BACKUP_MOUNT_POINT/repo' ] && [ -d '$BACKUP_MOUNT_POINT/logs' ]; then
                echo 'Existing backup directory structure found - using existing setup'
                BACKUP_VOLUME_EXISTS=true
            else
                echo 'Mount point exists but missing pgBackRest structure - will create directories'
                BACKUP_VOLUME_EXISTS=true
            fi
        else
            echo 'No existing backup mount point found'
            BACKUP_VOLUME_EXISTS=false
        fi

        echo \"BACKUP_VOLUME_EXISTS=\$BACKUP_VOLUME_EXISTS\"
    " "Checking existing backup volume"

    # Get the result and decide next steps
    local backup_exists
    backup_exists=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
        if mount | grep -q '$BACKUP_MOUNT_POINT'; then
            if [ -d '$BACKUP_MOUNT_POINT/repo' ] && [ -d '$BACKUP_MOUNT_POINT/logs' ]; then
                echo 'true'
            else
                echo 'partial'
            fi
        else
            echo 'false'
        fi
    ")

    if [ "$backup_exists" = "true" ]; then
        log_info "Existing backup volume setup found - skipping volume creation"
        execute_remote "$PRIMARY_IP" "
            # Just ensure proper permissions on existing setup
            sudo chown -R postgres:postgres $BACKUP_MOUNT_POINT
            sudo chmod 750 $BACKUP_MOUNT_POINT

            # Verify existing setup
            echo '=== Existing Backup Volume Status ==='
            df -h $BACKUP_MOUNT_POINT
            ls -la $BACKUP_MOUNT_POINT/
            sudo -u postgres touch $BACKUP_MOUNT_POINT/test && sudo -u postgres rm $BACKUP_MOUNT_POINT/test
            echo 'Existing backup volume verified and ready'
        " "Verifying existing backup volume"

    elif [ "$backup_exists" = "partial" ]; then
        log_info "Partial backup setup found - completing directory structure"
        execute_remote "$PRIMARY_IP" "
            # Set permissions
            sudo chown -R postgres:postgres $BACKUP_MOUNT_POINT
            sudo chmod 750 $BACKUP_MOUNT_POINT

            # Create missing directory structure
            sudo -u postgres mkdir -p $BACKUP_MOUNT_POINT/{repo,logs,archive}

            # Verify setup
            df -h $BACKUP_MOUNT_POINT
            ls -la $BACKUP_MOUNT_POINT/
            sudo -u postgres touch $BACKUP_MOUNT_POINT/test && sudo -u postgres rm $BACKUP_MOUNT_POINT/test
            echo 'Backup directory structure completed'
        " "Completing backup directory structure"

    else
        log_info "No existing backup volume found - creating new backup volume"

        # Check if we should create a new EBS volume or use existing device
        execute_remote "$PRIMARY_IP" "
            echo '=== Setting up new backup volume ==='

            # Check if backup device exists but is not mounted
            if lsblk | grep -q '${BACKUP_DEVICE##*/}'; then
                echo 'Backup device ${BACKUP_DEVICE##*/} found but not mounted - will mount it'
                DEVICE_EXISTS=true
            else
                echo 'No backup device found - will need to create and attach EBS volume'
                DEVICE_EXISTS=false
            fi

            if [ \"\$DEVICE_EXISTS\" = \"true\" ]; then
                # Device exists, format and mount it
                echo 'Setting up existing device...'

                # Check if volume needs formatting
                if ! sudo file -s $BACKUP_DEVICE | grep -q 'ext4'; then
                    echo 'Formatting backup device...'
                    sudo mkfs.ext4 $BACKUP_DEVICE
                else
                    echo 'Device already formatted with ext4'
                fi

                # Create mount point and mount
                sudo mkdir -p $BACKUP_MOUNT_POINT
                sudo mount $BACKUP_DEVICE $BACKUP_MOUNT_POINT

                # Add to fstab for persistence
                if ! grep -q '$BACKUP_DEVICE' /etc/fstab; then
                    echo '$BACKUP_DEVICE $BACKUP_MOUNT_POINT ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
                fi

                echo 'Existing device mounted successfully'
            else
                echo 'No backup device found - will create backup directory on root volume'
                echo 'For production use, consider attaching a dedicated EBS volume'
                sudo mkdir -p $BACKUP_MOUNT_POINT
            fi

            # Set permissions regardless of setup type
            sudo chown -R postgres:postgres $BACKUP_MOUNT_POINT
            sudo chmod 750 $BACKUP_MOUNT_POINT

            # Create directory structure
            sudo -u postgres mkdir -p $BACKUP_MOUNT_POINT/{repo,logs,archive}

            # Verify setup
            echo '=== New Backup Volume Status ==='
            df -h $BACKUP_MOUNT_POINT
            ls -la $BACKUP_MOUNT_POINT/
            sudo -u postgres touch $BACKUP_MOUNT_POINT/test && sudo -u postgres rm $BACKUP_MOUNT_POINT/test
            echo 'New backup volume setup completed'
        " "Setting up new backup volume"
    fi

    # Check if we need to create and attach an EBS volume
    local needs_ebs_volume
    needs_ebs_volume=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
        if mount | grep -q '$BACKUP_MOUNT_POINT'; then
            MOUNT_SOURCE=\$(mount | grep '$BACKUP_MOUNT_POINT' | awk '{print \$1}')
            if [[ \"\$MOUNT_SOURCE\" == \"$BACKUP_DEVICE\" ]]; then
                echo 'false'  # Already using dedicated device
            elif [[ \"\$MOUNT_SOURCE\" == *\"/dev/\"* ]]; then
                echo 'false'  # Using some other device
            else
                echo 'true'   # Using directory on root filesystem
            fi
        else
            echo 'true'  # No mount point at all
        fi
    ")

    if [ "$needs_ebs_volume" = "true" ]; then
        log_warning "Currently using root filesystem for backups"
        log_info "For production use, consider creating and attaching a dedicated EBS volume:"
        log_info "1. Create EBS volume: aws ec2 create-volume --size $BACKUP_VOLUME_SIZE --availability-zone $AVAILABILITY_ZONE"
        log_info "2. Attach to instance: aws ec2 attach-volume --volume-id vol-xxx --instance-id i-xxx --device $BACKUP_DEVICE"
        log_info "3. Re-run this script to use the dedicated volume"
    fi

    save_state "BACKUP_VOLUME_CONFIGURED" "true"
    save_state "BACKUP_USES_DEDICATED_DEVICE" "$([[ "$needs_ebs_volume" = "false" ]] && echo 'true' || echo 'false')"
    log_success "Backup volume setup completed"
}

#===============================================================================
# Step 3: Install and Configure pgBackRest on Primary
#===============================================================================

configure_pgbackrest_primary() {
    log "=== STEP 3: Configuring pgBackRest on primary ($PRIMARY_IP) ==="

    execute_remote "$PRIMARY_IP" "
        # Install pgBackRest from source if not already installed
        if ! command -v pgbackrest &> /dev/null; then
            echo 'Installing pgBackRest from source...'

            # Install build dependencies
            sudo yum install -y python3-devel gcc postgresql-devel openssl-devel \
                libxml2-devel pkgconfig lz4-devel libzstd-devel bzip2-devel zlib-devel \
                libyaml-devel libssh2-devel wget tar gzip

            # Install meson and ninja build tools
            sudo yum install -y python3-pip
            sudo pip3 install meson ninja

            # Download and extract pgBackRest source
            cd /tmp
            wget -O - https://github.com/pgbackrest/pgbackrest/archive/release/2.55.1.tar.gz | tar zx
            cd pgbackrest-release-2.55.1

            # Build pgBackRest
            meson setup build
            ninja -C build

            # Install binary
            sudo cp build/src/pgbackrest /usr/bin/
            sudo chmod 755 /usr/bin/pgbackrest

            # Verify installation
            pgbackrest version

            # Cleanup
            cd /
            rm -rf /tmp/pgbackrest-release-2.55.1
        else
            echo 'pgBackRest already installed'
            pgbackrest version
        fi

        # Create pgBackRest directories
        sudo mkdir -p /etc/pgbackrest /var/spool/pgbackrest /var/log/pgbackrest
        sudo chown postgres:postgres /etc/pgbackrest /var/spool/pgbackrest /var/log/pgbackrest

        # Check socket path
        SOCKET_PATH=\$(sudo -u postgres psql -t -c \"SHOW unix_socket_directories;\" | xargs)
        echo \"PostgreSQL socket path: \$SOCKET_PATH\"

        # Configure pgBackRest (try socket first, fallback to TCP)
        sudo -u postgres tee /etc/pgbackrest/pgbackrest.conf << EOF
[$STANZA_NAME]
pg1-path=$PG_DATA_DIR
pg1-port=5432
pg1-socket-path=/tmp

[global]
repo1-path=$BACKUP_MOUNT_POINT/repo
repo1-retention-full=4
repo1-retention-diff=3
repo1-retention-archive=10
process-max=12
start-fast=y
stop-auto=y
delta=y
compress-type=zst
compress-level=3
log-level-console=info
log-level-file=detail
log-path=$BACKUP_MOUNT_POINT/logs
EOF

        # Test pgBackRest connection
        echo 'Testing pgBackRest connection...'
        if ! sudo -u postgres pgbackrest --stanza=$STANZA_NAME check; then
            echo 'Socket connection failed, trying TCP connection...'
            # Fallback to TCP connection
            sudo -u postgres tee /etc/pgbackrest/pgbackrest.conf << EOF
[$STANZA_NAME]
pg1-path=$PG_DATA_DIR
pg1-port=5432
pg1-host=127.0.0.1
pg1-host-user=postgres

[global]
repo1-path=$BACKUP_MOUNT_POINT/repo
repo1-retention-full=4
repo1-retention-diff=3
repo1-retention-archive=10
process-max=12
start-fast=y
stop-auto=y
delta=y
compress-type=zst
compress-level=3
log-level-console=info
log-level-file=detail
log-path=$BACKUP_MOUNT_POINT/logs
EOF
        fi
    " "Installing and configuring pgBackRest"

    save_state "PGBACKREST_CONFIGURED" "true"
    log_success "pgBackRest configuration completed"
}

#===============================================================================
# Step 4: Create Stanza and Take Smart Backup
#===============================================================================

create_stanza_and_backup() {
    local backup_type=$(determine_backup_type)

    log_info "DEBUG: backup_type determined as: $backup_type"
    log_info "DEBUG: SKIP_BACKUP is: ${SKIP_BACKUP:-not_set}"
    log_info "DEBUG: BACKUP_MODE is: ${BACKUP_MODE:-not_set}"

    if [[ "$backup_type" == "skip" ]]; then
        log "=== STEP 4: Skipping backup creation (SKIP_BACKUP=true) ==="
        log_info "Backup creation skipped - using existing backups"

        # Show current backup information (lenient mode - don't fail on WAL timeout)
        execute_remote "$PRIMARY_IP" "
            # Show current backup information
            echo 'Current backup information...'
            sudo -u postgres pgbackrest --stanza=$STANZA_NAME info
        " "Getting existing backup information"

        # Get the most recent backup type from existing backups
        local latest_backup_type
        latest_backup_type=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
            sudo -u postgres pgbackrest --stanza=$STANZA_NAME info --output=json 2>/dev/null | \
            grep -o '\"type\":\"[^\"]*\"' | tail -1 | cut -d'\"' -f4
        " 2>/dev/null || echo "unknown")

        save_state "INITIAL_BACKUP_COMPLETED" "true"
        save_state "LAST_BACKUP_TYPE" "$latest_backup_type"
        save_state "LAST_BACKUP_DATE" "$(date '+%Y-%m-%d %H:%M:%S') (skipped - using existing)"
        log_success "Backup step skipped - using existing $latest_backup_type backup"
        return
    fi

    log "=== STEP 4: Creating stanza and taking $backup_type backup ==="

    execute_remote "$PRIMARY_IP" "
        # Test pgBackRest connection
        echo 'Testing pgBackRest connection...'
        sudo -u postgres pgbackrest --stanza=$STANZA_NAME check || {
            echo 'pgBackRest check failed, attempting to fix...'
            # Try to create stanza anyway
        }

        # Create stanza (if it doesn't exist)
        echo 'Creating pgBackRest stanza...'
        sudo -u postgres pgbackrest --stanza=$STANZA_NAME stanza-create

        # Take backup based on determined type
        echo \"Taking $backup_type backup...\"
        sudo -u postgres pgbackrest --stanza=$STANZA_NAME --type=$backup_type backup

        # Verify backup
        echo 'Verifying backup...'
        sudo -u postgres pgbackrest --stanza=$STANZA_NAME info

        # Check backup contents
        ls -la /backup/pgbackrest/repo/backup/$STANZA_NAME/ 2>/dev/null || echo 'Backup directory listing not available'
    " "Creating stanza and taking $backup_type backup"

    save_state "INITIAL_BACKUP_COMPLETED" "true"
    save_state "LAST_BACKUP_TYPE" "$backup_type"
    save_state "LAST_BACKUP_DATE" "$(date '+%Y-%m-%d %H:%M:%S')"
    log_success "$backup_type backup completed"
}

#===============================================================================
# Step 5: Take EBS Snapshot
#===============================================================================

create_ebs_snapshot() {
    if [[ "$SKIP_SNAPSHOT" == "true" ]]; then
        log_info "Snapshot creation skipped (SKIP_SNAPSHOT=true)"
        return 0
    fi

    log "=== STEP 5: Creating EBS snapshot ==="

    # Check if we're using a dedicated backup device
    local uses_dedicated_device
    uses_dedicated_device=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
        if mount | grep -q '$BACKUP_MOUNT_POINT'; then
            MOUNT_SOURCE=\$(mount | grep '$BACKUP_MOUNT_POINT' | awk '{print \$1}')
            if [[ \"\$MOUNT_SOURCE\" == \"$BACKUP_DEVICE\" ]]; then
                echo 'true'
            elif [[ \"\$MOUNT_SOURCE\" == *\"/dev/\"* ]]; then
                echo 'device'  # Using some other device
            else
                echo 'false'  # Using directory on root filesystem
            fi
        else
            echo 'false'
        fi
    ")

    if [ "$uses_dedicated_device" = "false" ]; then
        log_warning "Backup is stored on root filesystem - cannot create EBS snapshot"
        log_info "To enable EBS snapshots:"
        log_info "1. Create and attach a dedicated EBS volume for backups"
        log_info "2. Re-run this script to use the dedicated volume"
        log_info "3. EBS snapshots will then be available for standby creation"

        save_state "SNAPSHOT_AVAILABLE" "false"
        save_state "SNAPSHOT_REASON" "no_dedicated_volume"
        log_warning "Skipping EBS snapshot creation - using root filesystem"
        return 0
    fi

    # Get the backup volume ID using IMDSv2
    local instance_id
    instance_id=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" '
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
        if [ -n "$TOKEN" ]; then
            curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id
        fi
    ')

    if [[ -z "$instance_id" ]]; then
        log_warning "Could not retrieve instance ID from metadata service"
        save_state "SNAPSHOT_AVAILABLE" "false"
        save_state "SNAPSHOT_REASON" "instance_id_not_found"
        log_warning "Skipping EBS snapshot creation - instance ID not found"
        return 0
    fi

    log_info "Instance ID: $instance_id"

    # Try different device names based on the mount point
    local actual_device
    actual_device=$(ssh -o StrictHostKeyChecking=no "root@$PRIMARY_IP" "
        mount | grep '$BACKUP_MOUNT_POINT' | awk '{print \$1}'
    ")

    log_info "Backup is using device: $actual_device"

    # Get volume ID for the actual device
    BACKUP_VOLUME_ID=$(aws ec2 describe-volumes \
        --filters "Name=attachment.instance-id,Values=$instance_id" \
        --query "Volumes[?Attachments[?Device=='$actual_device']].VolumeId | [0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    # Try alternative device mappings if not found (FIXED VERSION)
    if [[ "$BACKUP_VOLUME_ID" == "None" ]] || [[ -z "$BACKUP_VOLUME_ID" ]] || [[ "$BACKUP_VOLUME_ID" == "null" ]]; then
        log_info "Direct device lookup failed, trying alternative mappings..."
        for alt_device in "/dev/sdb" "/dev/xvdb" "/dev/nvme1n1"; do
            log_info "Trying AWS device mapping: $alt_device"
            BACKUP_VOLUME_ID=$(aws ec2 describe-volumes \
                --filters "Name=attachment.device,Values=$alt_device" \
                "Name=attachment.instance-id,Values=$instance_id" \
                --query 'Volumes[0].VolumeId' --output text \
                --region "$AWS_REGION" 2>/dev/null)
            if [[ "$BACKUP_VOLUME_ID" != "None" ]] && [[ -n "$BACKUP_VOLUME_ID" ]] && [[ "$BACKUP_VOLUME_ID" != "null" ]]; then
                log_info "Found backup volume using alternative device mapping: $alt_device -> $BACKUP_VOLUME_ID"
                break
            fi
        done
    fi

    if [[ "$BACKUP_VOLUME_ID" == "None" ]] || [[ -z "$BACKUP_VOLUME_ID" ]] || [[ "$BACKUP_VOLUME_ID" == "null" ]]; then
        log_warning "Could not determine backup volume ID automatically"
        save_state "SNAPSHOT_AVAILABLE" "false"
        save_state "SNAPSHOT_REASON" "volume_id_not_found"
        log_warning "Skipping EBS snapshot creation - volume ID not found"
        return 0
    fi

    log_info "Backup Volume ID: $BACKUP_VOLUME_ID"

    # Determine snapshot type and description
    local backup_type="${LAST_BACKUP_TYPE:-$(determine_backup_type)}"
    local day_name=$(date +%A)
    local snapshot_desc="pgbackrest-$STANZA_NAME-$backup_type-$(date +%Y%m%d-%H%M%S)"
    local snapshot_tag_type

    if [[ "$backup_type" == "full" ]]; then
        snapshot_tag_type="weekly-full"
    else
        snapshot_tag_type="daily-incremental"
    fi

    # Create snapshot
    SNAPSHOT_ID=$(aws ec2 create-snapshot \
        --volume-id "$BACKUP_VOLUME_ID" \
        --description "$snapshot_desc" \
        --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$snapshot_desc},{Key=BackupType,Value=$snapshot_tag_type},{Key=Stanza,Value=$STANZA_NAME},{Key=Source,Value=primary},{Key=Day,Value=$day_name},{Key=ActualBackupType,Value=$backup_type}]" \
        --query 'SnapshotId' --output text \
        --region "$AWS_REGION")

    if [[ -z "$SNAPSHOT_ID" ]] || [[ "$SNAPSHOT_ID" == "None" ]]; then
        log_error "Failed to create snapshot"
        save_state "SNAPSHOT_AVAILABLE" "false"
        save_state "SNAPSHOT_REASON" "creation_failed"
        return 1
    fi

    log_info "Snapshot created: $SNAPSHOT_ID"

    # Don't wait for completion in scheduled mode to speed up execution
    if [[ "$BACKUP_MODE" == "setup" ]]; then
        log "Waiting for snapshot to complete (this may take several minutes)..."
        aws ec2 wait snapshot-completed --snapshot-ids "$SNAPSHOT_ID" --region "$AWS_REGION"
        log_success "Snapshot completed: $SNAPSHOT_ID"
    else
        log_info "Snapshot creation initiated: $SNAPSHOT_ID (completion will happen in background)"
    fi

    # Save state
    save_state "BACKUP_VOLUME_ID" "$BACKUP_VOLUME_ID"
    save_state "LATEST_SNAPSHOT_ID" "$SNAPSHOT_ID"
    save_state "LAST_SNAPSHOT_DATE" "$(date '+%Y-%m-%d %H:%M:%S')"
    save_state "SNAPSHOT_AVAILABLE" "true"

    # Cleanup old snapshots if enabled
    if [[ "$CLEANUP_OLD_SNAPSHOTS" == "true" ]] && [[ "$backup_type" == "full" ]]; then
        cleanup_old_snapshots
    fi

    log_success "Snapshot creation completed: $SNAPSHOT_ID"
}

#===============================================================================
# Step 6: Cleanup Old Snapshots
#===============================================================================

cleanup_old_snapshots() {
    if [[ "$CLEANUP_OLD_SNAPSHOTS" != "true" ]]; then
        return 0
    fi

    log "=== Cleaning up old snapshots ==="

    # Cleanup daily incremental snapshots older than 7 days
    local daily_retention_days=7
    local cutoff_date=$(date -d "${daily_retention_days} days ago" '+%Y-%m-%d')

    log_info "Cleaning up daily snapshots older than ${daily_retention_days} days (before $cutoff_date)..."

    local old_daily_snapshots
    old_daily_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Stanza,Values=${STANZA_NAME}" "Name=tag:BackupType,Values=daily-incremental" \
        --query "Snapshots[?StartTime<='${cutoff_date}'].SnapshotId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    local deleted_count=0
    for snapshot in $old_daily_snapshots; do
        if [ -n "$snapshot" ] && [ "$snapshot" != "None" ]; then
            log_info "Deleting old daily snapshot: $snapshot"
            if aws ec2 delete-snapshot --snapshot-id "$snapshot" --region "$AWS_REGION" 2>/dev/null; then
                ((deleted_count++))
            else
                log_warning "Failed to delete snapshot $snapshot"
            fi
        fi
    done

    # Keep only the last 4 weekly full backup snapshots
    log_info "Cleaning up old weekly snapshots (keeping last 4)..."

    local old_weekly_snapshots
    old_weekly_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Stanza,Values=${STANZA_NAME}" "Name=tag:BackupType,Values=weekly-full" \
        --query "Snapshots | sort_by(@, &StartTime) | [:-4].SnapshotId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    for snapshot in $old_weekly_snapshots; do
        if [ -n "$snapshot" ] && [ "$snapshot" != "None" ]; then
            log_info "Deleting old weekly snapshot: $snapshot"
            if aws ec2 delete-snapshot --snapshot-id "$snapshot" --region "$AWS_REGION" 2>/dev/null; then
                ((deleted_count++))
            else
                log_warning "Failed to delete snapshot $snapshot"
            fi
        fi
    done

    if [ $deleted_count -gt 0 ]; then
        log_success "Cleaned up $deleted_count old snapshots"
    else
        log_info "No old snapshots to clean up"
    fi
}

#===============================================================================
# Step 7: Setup Periodic Snapshots (Optional)
#===============================================================================

setup_periodic_snapshots() {
    log "=== STEP 7: Setting up periodic snapshots ==="

    if [[ "$SETUP_PERIODIC_SNAPSHOTS" != "true" ]]; then
        log_info "Periodic snapshots disabled, skipping..."
        return 0
    fi

    # Create a wrapper script that calls this main script in scheduled mode
    cat > "${SCRIPT_DIR}/scheduled_backup.sh" << EOF
#!/bin/bash
# Scheduled backup wrapper script
# This script calls the main pgbackrest setup script in scheduled mode

set -euo pipefail

# Source the state file to get configuration
if [ -f "${STATE_FILE}" ]; then
    source "${STATE_FILE}"
fi

# Set environment variables for scheduled execution
export BACKUP_MODE="auto"
export PRIMARY_IP="${PRIMARY_IP}"
export STANZA_NAME="${STANZA_NAME}"
export AWS_REGION="${AWS_REGION}"
export SKIP_SNAPSHOT="\${SKIP_SNAPSHOT:-false}"
export CLEANUP_OLD_SNAPSHOTS="\${CLEANUP_OLD_SNAPSHOTS:-true}"

# Log file with date
LOG_FILE="/var/log/pgbackrest_scheduled_\$(date +%Y%m%d_%H%M%S).log"

echo "\$(date): Starting scheduled backup execution" | tee -a "\$LOG_FILE"
echo "Backup mode: auto (will determine full vs incremental based on day)" | tee -a "\$LOG_FILE"
echo "Day of week: \$(date +%A)" | tee -a "\$LOG_FILE"

# Execute the main script in non-interactive mode
"${SCRIPT_DIR}/$(basename "$0")" --scheduled >> "\$LOG_FILE" 2>&1

EXIT_CODE=\$?

if [ \$EXIT_CODE -eq 0 ]; then
    echo "\$(date): Scheduled backup completed successfully" | tee -a "\$LOG_FILE"
else
    echo "\$(date): Scheduled backup failed with exit code \$EXIT_CODE" | tee -a "\$LOG_FILE"
fi

exit \$EXIT_CODE
EOF

    chmod +x "${SCRIPT_DIR}/scheduled_backup.sh"

    log_info "Scheduled backup wrapper created: ${SCRIPT_DIR}/scheduled_backup.sh"
    log_info ""
    log_info "To setup automatic scheduled backups, add this to your crontab:"
    log_info "  # Daily backup at 2 AM (full on Sunday, incremental Mon-Sat)"
    log_info "  0 2 * * * ${SCRIPT_DIR}/scheduled_backup.sh"
    log_info ""
    log_info "Or run: echo '0 2 * * * ${SCRIPT_DIR}/scheduled_backup.sh' | crontab -"

    save_state "PERIODIC_SNAPSHOTS_CONFIGURED" "true"
    log_success "Periodic snapshot setup completed"
}

#===============================================================================
# Summary and Information
#===============================================================================

show_primary_summary() {
    local backup_type="${LAST_BACKUP_TYPE:-unknown}"

    log "=== PRIMARY SETUP COMPLETED SUCCESSFULLY! ==="
    echo
    log_info "=== CONFIGURATION SUMMARY ==="
    log_info "Primary Server: $PRIMARY_IP"
    log_info "PostgreSQL Version: $PG_VERSION"
    log_info "Stanza Name: $STANZA_NAME"
    log_info "Last Backup Type: $backup_type"
    if [ -n "$BACKUP_VOLUME_ID" ]; then
        log_info "Backup Volume: $BACKUP_VOLUME_ID"
    fi
    if [ -n "$SNAPSHOT_ID" ]; then
        log_info "Latest Snapshot: $SNAPSHOT_ID"
    fi
    echo
    log_info "=== BACKUP SCHEDULE ==="
    log_info "Sunday: Full backup + snapshot"
    log_info "Monday-Saturday: Incremental backup + snapshot"
    log_info "Automatic cleanup: Old snapshots removed"
    echo
    log_info "=== STATE FILE ==="
    log_info "Configuration saved to: $STATE_FILE"
    if [ -f "$STATE_FILE" ]; then
        log_info "Current state:"
        while IFS= read -r line; do
            log_info "  $line"
        done < "$STATE_FILE"
    fi
    echo
    log_info "=== SCHEDULED EXECUTION ==="
    log_info "To enable automatic daily backups, run:"
    log_info "  echo '0 2 * * * ${SCRIPT_DIR}/scheduled_backup.sh' | crontab -"
    echo
    log_info "=== MANUAL OPERATIONS ==="
    log_info "1. Force full backup:"
    log_info "   FORCE_FULL_BACKUP=true $0 --scheduled"
    echo
    log_info "2. Force incremental backup:"
    log_info "   BACKUP_MODE=incr $0 --scheduled"
    echo
    log_info "3. Skip snapshot creation:"
    log_info "   SKIP_SNAPSHOT=true $0 --scheduled"
    echo
    log_info "4. Skip backup, only snapshot:"
    log_info "   SKIP_BACKUP=true $0 --scheduled"
    echo
    log_info "5. Check backup status:"
    log_info "   ssh root@$PRIMARY_IP 'sudo -u postgres pgbackrest --stanza=$STANZA_NAME info'"
    echo
    log_info "6. Check recent snapshots:"
    log_info "   aws ec2 describe-snapshots --owner-ids self --filters 'Name=tag:Stanza,Values=$STANZA_NAME' --region $AWS_REGION"
    echo
    log_success "Log file saved to: $LOG_FILE"
}

#===============================================================================
# Usage Information
#===============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Modes:"
    echo "  --scheduled             Run in scheduled mode (non-interactive, smart backup type)"
    echo "  --setup                 Run initial setup (interactive, full backup)"
    echo
    echo "Environment Variables:"
    echo "  PRIMARY_IP              Primary server IP (default: $DEFAULT_PRIMARY_IP)"
    echo "  PG_VERSION              PostgreSQL version (default: $DEFAULT_PG_VERSION)"
    echo "  STANZA_NAME             pgBackRest stanza name (default: $DEFAULT_STANZA_NAME)"
    echo "  BACKUP_VOLUME_SIZE      Backup volume size in GB (default: $DEFAULT_BACKUP_VOLUME_SIZE)"
    echo "  AWS_REGION              AWS region (default: $DEFAULT_AWS_REGION)"
    echo "  AVAILABILITY_ZONE       AWS availability zone (default: $DEFAULT_AVAILABILITY_ZONE)"
    echo "  SETUP_PERIODIC_SNAPSHOTS Enable periodic snapshots (default: true)"
    echo
    echo "Backup Control:"
    echo "  BACKUP_MODE             Backup mode: auto, setup, full, incr, skip (default: auto)"
    echo "  FORCE_FULL_BACKUP       Force full backup even on weekdays (default: false)"
    echo "  SKIP_BACKUP             Skip backup entirely, only create snapshots (default: false)"
    echo "  SKIP_SNAPSHOT           Skip EBS snapshot creation (default: false)"
    echo "  CLEANUP_OLD_SNAPSHOTS   Clean up old snapshots (default: true)"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --dry-run               Show what would be done without executing"
    echo "  --skip-prerequisites    Skip prerequisites check"
    echo "  --no-periodic           Disable periodic snapshot setup"
    echo "  --scheduled             Run in scheduled/cron mode (non-interactive)"
    echo
    echo "Examples:"
    echo "  # Initial setup (interactive)"
    echo "  $0"
    echo "  $0 --setup"
    echo
    echo "  # Scheduled execution (for cron)"
    echo "  $0 --scheduled"
    echo
    echo "  # Force full backup"
    echo "  FORCE_FULL_BACKUP=true $0 --scheduled"
    echo
    echo "  # Incremental backup only"
    echo "  BACKUP_MODE=incr $0 --scheduled"
    echo
    echo "  # Backup without snapshot"
    echo "  SKIP_SNAPSHOT=true $0 --scheduled"
    echo
    echo "  # Skip backup, only create snapshot from existing backup"
    echo "  SKIP_BACKUP=true $0 --scheduled"
    echo "  BACKUP_MODE=skip $0 --scheduled"
    echo
    echo "Scheduled Mode Behavior:"
    echo "  - Sunday: Full backup + snapshot"
    echo "  - Monday-Saturday: Incremental backup + snapshot"
    echo "  - Automatic cleanup of old snapshots"
    echo "  - Non-interactive execution"
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    local scheduled_mode=false
    local interactive_mode=true

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --dry-run)
                log_warning "DRY RUN MODE - No changes will be made"
                DRY_RUN=true
                shift
                ;;
            --skip-prerequisites)
                SKIP_PREREQ=true
                shift
                ;;
            --no-periodic)
                SETUP_PERIODIC_SNAPSHOTS=false
                shift
                ;;
            --scheduled)
                scheduled_mode=true
                interactive_mode=false
                SCHEDULED_MODE=true
                BACKUP_MODE="${BACKUP_MODE:-auto}"
                shift
                ;;
            --setup)
                BACKUP_MODE="setup"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Print header
    if [[ "$interactive_mode" == "true" ]]; then
        echo -e "${CYAN}"
        echo "==============================================================================="
        echo "  pgBackRest Primary Setup Script - Part 1"
        echo "==============================================================================="
        echo -e "${NC}"
    fi

    # Load existing state
    load_state

    # Show configuration
    if [[ "$interactive_mode" == "true" ]]; then
        log_info "Configuration:"
        log_info "  Primary IP: $PRIMARY_IP"
        log_info "  PostgreSQL Version: $PG_VERSION"
        log_info "  Stanza Name: $STANZA_NAME"
        log_info "  AWS Region: $AWS_REGION"
        log_info "  Backup Mode: $BACKUP_MODE"
        log_info "  Periodic Snapshots: $SETUP_PERIODIC_SNAPSHOTS"
        log_info "  Log File: $LOG_FILE"
        log_info "  State File: $STATE_FILE"
        echo

        # Confirmation prompt
        read -p "Do you want to proceed with the primary setup? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    else
        # Scheduled mode - log basic info
        log_info "=== SCHEDULED BACKUP EXECUTION ==="
        log_info "Backup Mode: $BACKUP_MODE"
        log_info "Day: $(date +%A)"
        log_info "Time: $(date '+%Y-%m-%d %H:%M:%S')"

        if [[ "$BACKUP_MODE" == "auto" ]]; then
            local backup_type=$(determine_backup_type)
            log_info "Determined Backup Type: $backup_type"
        fi
    fi

    # Execute setup steps
    if [[ "${SKIP_PREREQ:-false}" != "true" ]]; then
        check_prerequisites
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_warning "DRY RUN - Skipping actual execution"
        exit 0
    fi

    # Execute primary setup steps based on mode
    if should_run_setup; then
        # Full setup mode
        setup_primary_archiving
        setup_backup_volume
        configure_pgbackrest_primary
        create_stanza_and_backup
        create_ebs_snapshot
        setup_periodic_snapshots
        show_primary_summary
    else
        # Scheduled backup mode - only run backup and snapshot
        log_info "=== SCHEDULED BACKUP/SNAPSHOT EXECUTION ==="

        # Debug: Check what we're about to call
        local backup_type=$(determine_backup_type)
        log_info "DEBUG: About to call create_stanza_and_backup with backup_type: $backup_type"

        create_stanza_and_backup  # This will determine the right backup type
        create_ebs_snapshot

        if [[ "$interactive_mode" == "true" ]]; then
            show_primary_summary
        else
            log_success "Scheduled execution completed successfully"
            log_info "Backup type: ${LAST_BACKUP_TYPE:-unknown}"
            log_info "Snapshot ID: ${SNAPSHOT_ID:-none}"
        fi
    fi

    log_success "Execution completed successfully!"
}

# Execute main function with all arguments
main "$@"
