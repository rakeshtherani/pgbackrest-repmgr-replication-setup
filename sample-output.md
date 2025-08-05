[root@txn-testing-0002-slave opt]# cat pgbackrest_primary_setup_20250801_082711.log
[2025-08-01 08:27:11] ℹ️  INFO: State loaded from: /opt/pgbackrest_primary_state.env
[2025-08-01 08:27:11] ℹ️  INFO: === SCHEDULED BACKUP EXECUTION ===
[2025-08-01 08:27:11] ℹ️  INFO: Backup Mode: auto
[2025-08-01 08:27:11] ℹ️  INFO: Day: Friday
[2025-08-01 08:27:11] ℹ️  INFO: Time: 2025-08-01 08:27:11
[2025-08-01 08:27:11] ℹ️  INFO: Determined Backup Type: skip
[2025-08-01 08:27:11] Checking prerequisites for primary setup...
[2025-08-01 08:27:12] ✅ Prerequisites check completed
[2025-08-01 08:27:12] ℹ️  INFO: === SCHEDULED BACKUP/SNAPSHOT EXECUTION ===
[2025-08-01 08:27:12] ℹ️  INFO: DEBUG: About to call create_stanza_and_backup with backup_type: skip
[2025-08-01 08:27:12] ℹ️  INFO: DEBUG: backup_type determined as: skip
[2025-08-01 08:27:12] ℹ️  INFO: DEBUG: SKIP_BACKUP is: true
[2025-08-01 08:27:12] ℹ️  INFO: DEBUG: BACKUP_MODE is: auto
[2025-08-01 08:27:12] === STEP 4: Skipping backup creation (SKIP_BACKUP=true) ===
[2025-08-01 08:27:12] ℹ️  INFO: Backup creation skipped - using existing backups
[2025-08-01 08:27:12] Executing on 10.40.0.24: Getting existing backup information
[2025-08-01 08:27:12] ✅ Command executed successfully on 10.40.0.24
[2025-08-01 08:27:12] ℹ️  INFO: State saved: INITIAL_BACKUP_COMPLETED=true
[2025-08-01 08:27:12] ℹ️  INFO: State saved: LAST_BACKUP_TYPE=full
[2025-08-01 08:27:12] ℹ️  INFO: State saved: LAST_BACKUP_DATE=2025-08-01 08:27:12 (skipped - using existing)
[2025-08-01 08:27:12] ✅ Backup step skipped - using existing full backup
[2025-08-01 08:27:12] === STEP 5: Creating EBS snapshot ===
[2025-08-01 08:27:13] ℹ️  INFO: Instance ID: i-0b97d5ff67837092c
[2025-08-01 08:27:13] ℹ️  INFO: Backup is using device: /dev/nvme1n1
[2025-08-01 08:27:14] ℹ️  INFO: Direct device lookup failed, trying alternative mappings...
[2025-08-01 08:27:14] ℹ️  INFO: Trying AWS device mapping: /dev/sdb
[2025-08-01 08:27:15] ℹ️  INFO: Found backup volume using alternative device mapping: /dev/sdb -> vol-0b12f33bcbe3cfda8
[2025-08-01 08:27:15] ℹ️  INFO: Backup Volume ID: vol-0b12f33bcbe3cfda8
[2025-08-01 08:27:16] ℹ️  INFO: Snapshot created: snap-04378344be427f879
[2025-08-01 08:27:16] ℹ️  INFO: Snapshot creation initiated: snap-04378344be427f879 (completion will happen in background)
[2025-08-01 08:27:16] ℹ️  INFO: State saved: BACKUP_VOLUME_ID=vol-0b12f33bcbe3cfda8
[2025-08-01 08:27:16] ℹ️  INFO: State saved: LATEST_SNAPSHOT_ID=snap-04378344be427f879
[2025-08-01 08:27:16] ℹ️  INFO: State saved: LAST_SNAPSHOT_DATE=2025-08-01 08:27:16
[2025-08-01 08:27:16] ℹ️  INFO: State saved: SNAPSHOT_AVAILABLE=true
[2025-08-01 08:27:16] === Cleaning up old snapshots ===
[2025-08-01 08:27:16] ℹ️  INFO: Cleaning up daily snapshots older than 7 days (before 2025-07-25)...
[2025-08-01 08:27:17] ℹ️  INFO: Cleaning up old weekly snapshots (keeping last 4)...
[2025-08-01 08:27:17] ℹ️  INFO: No old snapshots to clean up
[2025-08-01 08:27:17] ✅ Snapshot creation completed: snap-04378344be427f879
[2025-08-01 08:27:17] ✅ Scheduled execution completed successfully

=============================================



[root@txn-testing-0002-slave opt]# cat pgbackrest_standby_setup_20250805_045355.log
[2025-08-05 04:53:55] ⚠️  WARNING: DRY RUN MODE - No changes will be made
[2025-08-05 04:53:55] ℹ️  INFO: State loaded from: /opt/pgbackrest_standby_state.env
[2025-08-05 04:53:55] ℹ️  INFO: Configuration:
[2025-08-05 04:53:55] ℹ️  INFO:   Primary IP: 10.40.0.24
[2025-08-05 04:53:55] ℹ️  INFO:   Existing Standby IP: 10.40.0.27
[2025-08-05 04:53:55] ℹ️  INFO:   New Standby IP: 10.40.0.17
[2025-08-05 04:53:55] ℹ️  INFO:   PostgreSQL Version: 13
[2025-08-05 04:53:55] ℹ️  INFO:   Stanza Name: txn_cluster
[2025-08-05 04:53:55] ℹ️  INFO:   AWS Region: ap-northeast-1
[2025-08-05 04:53:55] ℹ️  INFO:   Target Snapshot: snap-04378344be427f879
[2025-08-05 04:53:55] ℹ️  INFO:   Log File: /opt/pgbackrest_standby_setup_20250805_045355.log
[2025-08-05 04:53:55] ℹ️  INFO:   State File: /opt/pgbackrest_standby_state.env
[2025-08-05 04:53:57] Checking prerequisites for standby setup...
[2025-08-05 04:53:59] ℹ️  INFO: PostgreSQL 13 verified on standby server
[2025-08-05 04:53:59] ✅ Prerequisites check completed
[2025-08-05 04:53:59] ⚠️  WARNING: DRY RUN - Skipping actual execution
[root@txn-testing-0002-slave opt]# cat pgbackrest_standby_setup_20250802_150944.log
[2025-08-02 15:09:44] ℹ️  INFO: State loaded from: /opt/pgbackrest_standby_state.env
[2025-08-02 15:09:44] ℹ️  INFO: Configuration:
[2025-08-02 15:09:44] ℹ️  INFO:   Primary IP: 10.40.0.24
[2025-08-02 15:09:44] ℹ️  INFO:   Existing Standby IP: 10.40.0.27
[2025-08-02 15:09:44] ℹ️  INFO:   New Standby IP: 10.40.0.17
[2025-08-02 15:09:44] ℹ️  INFO:   PostgreSQL Version: 13
[2025-08-02 15:09:44] ℹ️  INFO:   Stanza Name: txn_cluster
[2025-08-02 15:09:44] ℹ️  INFO:   AWS Region: ap-northeast-1
[2025-08-02 15:09:44] ℹ️  INFO:   Target Snapshot: snap-04378344be427f879
[2025-08-02 15:09:44] ℹ️  INFO:   Log File: /opt/pgbackrest_standby_setup_20250802_150944.log
[2025-08-02 15:09:44] ℹ️  INFO:   State File: /opt/pgbackrest_standby_state.env
[2025-08-02 15:09:46] Checking prerequisites for standby setup...
[2025-08-02 15:09:48] ℹ️  INFO: PostgreSQL 13 verified on standby server
[2025-08-02 15:09:48] ✅ Prerequisites check completed
[2025-08-02 15:09:48] === STEP 1: Finding latest snapshot ===
[2025-08-02 15:09:48] ℹ️  INFO: Using snapshot from state file: snap-04378344be427f879
[2025-08-02 15:09:49] ℹ️  INFO: State saved: LATEST_SNAPSHOT_ID=snap-04378344be427f879
[2025-08-02 15:09:49] ✅ Verified snapshot: snap-04378344be427f879
[2025-08-02 15:09:49] === STEP 2: Creating new volume from latest snapshot ===
[2025-08-02 15:09:49] ℹ️  INFO: Volume vol-00d3a4960ff4cfc8d already exists and is in-use - checking attachment
[2025-08-02 15:09:49] ℹ️  INFO: State saved: VOLUME_EXISTS=true
[2025-08-02 15:09:49] ✅ Using existing in-use volume: vol-00d3a4960ff4cfc8d
[2025-08-02 15:09:49] === STEP 3: Attaching volume to new standby server (10.40.0.17) ===
[2025-08-02 15:09:50] ℹ️  INFO: Target instance: i-0b7fc7c40f824a8b9
[2025-08-02 15:09:50] Executing on 10.40.0.17: Checking for existing backup mount
[2025-08-02 15:09:51] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:09:51] ✅ Backup is already mounted and contains valid data - skipping mount setup
[2025-08-02 15:09:51] ℹ️  INFO: State saved: NEW_INSTANCE_ID=i-0b7fc7c40f824a8b9
[2025-08-02 15:09:51] ℹ️  INFO: State saved: VOLUME_ATTACHED=true
[2025-08-02 15:09:51] ℹ️  INFO: State saved: BACKUP_MOUNT_READY=true
[2025-08-02 15:09:51] === STEP 4: Installing pgBackRest on new standby (10.40.0.17) ===
[2025-08-02 15:09:51] Executing on 10.40.0.17: Installing pgBackRest
[2025-08-02 15:09:52] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:09:52] ℹ️  INFO: State saved: PGBACKREST_INSTALLED=true
[2025-08-02 15:09:52] ✅ pgBackRest installation completed
[2025-08-02 15:09:52] === STEP 5: Configuring pgBackRest for restore on new standby ===
[2025-08-02 15:09:52] Executing on 10.40.0.17: Configuring pgBackRest for restore
[2025-08-02 15:09:52] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:09:52] ℹ️  INFO: State saved: PGBACKREST_CONFIGURED=true
[2025-08-02 15:09:52] ✅ pgBackRest restore configuration completed
[2025-08-02 15:09:52] === STEP 6: Checking database status and backup version ===
[2025-08-02 15:09:53] ℹ️  INFO: Latest available backup: 20250801-052759F
none
[2025-08-02 15:09:53] ℹ️  INFO: PostgreSQL data directory exists - checking current state
[2025-08-02 15:09:53] ℹ️  INFO: Current restored backup label: pgBackRest
[2025-08-02 15:09:53] ℹ️  INFO: Standby signal file found - checking if PostgreSQL is running
[2025-08-02 15:09:54] ℹ️  INFO: PostgreSQL service is not running
[2025-08-02 15:09:54] ℹ️  INFO: Current backup (pgBackRest) differs from latest (20250801-052759F
none)
[2025-08-02 15:09:54] ℹ️  INFO: Will restore latest backup to ensure standby is up-to-date
[2025-08-02 15:09:54] ℹ️  INFO: Data directory has substantial content (477351340 KB)
[2025-08-02 15:09:54] ℹ️  INFO: Current: pgBackRest, Latest: 20250801-052759F
none
[2025-08-02 15:09:54] ℹ️  INFO: Will restore latest backup
[2025-08-02 15:09:54] ℹ️  INFO: Data directory has substantial content (477351340 KB)
[2025-08-02 15:09:54] ℹ️  INFO: Attempting to use existing data and configure as standby
[2025-08-02 15:09:54] ℹ️  INFO: Verifying standby configuration...
[2025-08-02 15:09:54] Executing on 10.40.0.17: Verifying standby configuration
[2025-08-02 15:09:54] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:09:54] ℹ️  INFO: Starting PostgreSQL with existing data
[2025-08-02 15:10:06] ✅ PostgreSQL started successfully as standby with existing data
[2025-08-02 15:10:06] ℹ️  INFO: State saved: DATABASE_RESTORED=true
[2025-08-02 15:10:06] ℹ️  INFO: State saved: STANDBY_RUNNING=true
[2025-08-02 15:10:06] ℹ️  INFO: State saved: BACKUP_CURRENT=true
[2025-08-02 15:10:06] === STEP 7: Setting up replication slot on primary ===
[2025-08-02 15:10:06] Executing on 10.40.0.24: Setting up replication slot
[2025-08-02 15:10:07] ✅ Command executed successfully on 10.40.0.24
[2025-08-02 15:10:07] ℹ️  INFO: State saved: REPLICATION_SLOT_CREATED=true
[2025-08-02 15:10:07] ✅ Replication slot setup completed
[2025-08-02 15:10:07] === STEP 8: Configuring and starting new standby server ===
[2025-08-02 15:10:07] Executing on 10.40.0.17: Configuring and starting new standby
[2025-08-02 15:10:08] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:10:08] ℹ️  INFO: State saved: STANDBY_CONFIGURED=true
[2025-08-02 15:10:08] ✅ New standby server configuration completed
[2025-08-02 15:10:08] === STEP 9: Registering with repmgr and final verification ===
[2025-08-02 15:10:08] Executing on 10.40.0.17: Testing connections
[2025-08-02 15:10:08] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:10:08] Executing on 10.40.0.17: Registering with repmgr
[2025-08-02 15:10:09] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:10:09] ℹ️  INFO: State saved: REPMGR_REGISTERED=true
[2025-08-02 15:10:09] ✅ repmgr registration completed
[2025-08-02 15:10:09] === STEP 10: Final verification and testing ===
[2025-08-02 15:10:09] Executing on 10.40.0.17: Checking standby status
[2025-08-02 15:10:09] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:10:09] Executing on 10.40.0.24: Checking primary status and testing replication
[2025-08-02 15:10:10] ✅ Command executed successfully on 10.40.0.24
[2025-08-02 15:10:25] Executing on 10.40.0.17: Verifying replication on standby
[2025-08-02 15:10:25] ✅ Command executed successfully on 10.40.0.17
[2025-08-02 15:10:25] Executing on 10.40.0.24: Showing cluster status
[2025-08-02 15:10:25] ✅ Command executed successfully on 10.40.0.24
[2025-08-02 15:10:25] ℹ️  INFO: State saved: VERIFICATION_COMPLETED=true
[2025-08-02 15:10:25] ℹ️  INFO: State saved: SETUP_COMPLETED=2025-08-02 15:10:25
[2025-08-02 15:10:25] ✅ Final verification completed
[2025-08-02 15:10:25] === STANDBY SETUP COMPLETED SUCCESSFULLY! ===
[2025-08-02 15:10:25] ℹ️  INFO: === DEPLOYMENT SUMMARY ===
[2025-08-02 15:10:25] ℹ️  INFO: Primary Server: 10.40.0.24
[2025-08-02 15:10:25] ℹ️  INFO: Existing Standby: 10.40.0.27
[2025-08-02 15:10:25] ℹ️  INFO: New Standby: 10.40.0.17
[2025-08-02 15:10:25] ℹ️  INFO: PostgreSQL Version: 13
[2025-08-02 15:10:25] ℹ️  INFO: Stanza Name: txn_cluster
[2025-08-02 15:10:25] ℹ️  INFO: Source Snapshot: snap-04378344be427f879
[2025-08-02 15:10:25] ℹ️  INFO: New Volume: vol-00d3a4960ff4cfc8d
[2025-08-02 15:10:25] ℹ️  INFO: === CLUSTER STRUCTURE ===
[2025-08-02 15:10:25] ℹ️  INFO: Node 1 (10.40.0.24) = Primary
[2025-08-02 15:10:25] ℹ️  INFO: Node 2 (10.40.0.27) = Existing Standby
[2025-08-02 15:10:25] ℹ️  INFO: Node 3 (10.40.0.17) = New Standby
[2025-08-02 15:10:25] ℹ️  INFO: === STATE FILE ===
[2025-08-02 15:10:25] ℹ️  INFO: Configuration saved to: /opt/pgbackrest_standby_state.env
[2025-08-02 15:10:25] ℹ️  INFO: Current state:
[2025-08-02 15:10:25] ℹ️  INFO:   NEW_VOLUME_ID=vol-00d3a4960ff4cfc8d
[2025-08-02 15:10:25] ℹ️  INFO:   VOLUME_ALREADY_MOUNTED=true
[2025-08-02 15:10:25] ℹ️  INFO:   LATEST_SNAPSHOT_ID=snap-04378344be427f879
[2025-08-02 15:10:25] ℹ️  INFO:   VOLUME_EXISTS=true
[2025-08-02 15:10:25] ℹ️  INFO:   NEW_INSTANCE_ID=i-0b7fc7c40f824a8b9
[2025-08-02 15:10:25] ℹ️  INFO:   VOLUME_ATTACHED=true
[2025-08-02 15:10:25] ℹ️  INFO:   BACKUP_MOUNT_READY=true
[2025-08-02 15:10:25] ℹ️  INFO:   PGBACKREST_INSTALLED=true
[2025-08-02 15:10:25] ℹ️  INFO:   PGBACKREST_CONFIGURED=true
[2025-08-02 15:10:25] ℹ️  INFO:   DATABASE_RESTORED=true
[2025-08-02 15:10:25] ℹ️  INFO:   STANDBY_RUNNING=true
[2025-08-02 15:10:25] ℹ️  INFO:   BACKUP_CURRENT=true
[2025-08-02 15:10:25] ℹ️  INFO:   REPLICATION_SLOT_CREATED=true
[2025-08-02 15:10:25] ℹ️  INFO:   STANDBY_CONFIGURED=true
[2025-08-02 15:10:25] ℹ️  INFO:   REPMGR_REGISTERED=true
[2025-08-02 15:10:25] ℹ️  INFO:   VERIFICATION_COMPLETED=true
[2025-08-02 15:10:25] ℹ️  INFO:   SETUP_COMPLETED="2025-08-02 15:10:25"
[2025-08-02 15:10:25] ℹ️  INFO: === MONITORING COMMANDS ===
[2025-08-02 15:10:25] ℹ️  INFO: === FAILOVER COMMANDS ===
[2025-08-02 15:10:25] ✅ Log file saved to: /opt/pgbackrest_standby_setup_20250802_150944.log
[2025-08-02 15:10:25] ✅ Standby setup completed successfully!
[2025-08-01 08:27:17] ℹ️  INFO: Backup type: full
[2025-08-01 08:27:17] ℹ️  INFO: Snapshot ID: snap-04378344be427f879
[2025-08-01 08:27:17] ✅ Execution completed successfully!
