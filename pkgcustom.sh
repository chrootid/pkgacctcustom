#!/bin/bash
# script custom pelengkap account backup
function _init_vars {
        WHMAPI1=$(which whmapi1)
        RSYNC=$(which rsync)
        TR=$(which tr)
        SSH=$(which ssh)
        JQ=$(which jq)
        DATE=$(which date)
        MKDIR=$(which mkdir)
        PKGACCT=/scripts/pkgacct
        CREATEMETADATA=/scripts/backups_create_metadata
        TMPBACKUPCONFIG=$(mktemp)
        TMPLISTACCTS=$(mktemp)
        TMPBACKUPDST=$(mktemp)
}

function _clear_tmp {
        rm -f "$TMPBACKUPCONFIG"
        rm -f "$TMPLISTACCTS"
        rm -f "$TMPBACKUPDST"
}

function _get_backup_destination_list {
        "$WHMAPI1" backup_destination_list --output=jsonpretty|"$JQ" -r '.' > "$TMPBACKUPDST"
}

function _get_listaccts {
        "$WHMAPI1" --output=jsonpretty listaccts > "$TMPLISTACCTS"
        if [[ "$($JQ -r '.metadata.result' "$TMPLISTACCTS")" -ne 1 ]];then
                "$JQ" -r '.metadata.reason' "$TMPLISTACCTS"
                rm -f "$TMPLISTACCTS"
                exit
        fi
}

function _backup_config_get {
        "$WHMAPI1" --output=jsonpretty backup_config_get > "$TMPBACKUPCONFIG"
        if [[ "$($JQ -r '.metadata.result' "$TMPBACKUPCONFIG")" -ne 1 ]];then
                "$JQ" -r '.metadata.reason' "$TMPBACKUPCONFIG"
                rm -f "$TMPBACKUPCONFIG"
                exit
        fi
}

function _backup_compressed {
        "$JQ" -r '.data.acct[].user' "$TMPLISTACCTS"|sort|while read -r CPUSER;do
                if [[ ! -f "$BACKUPFINALDIR/$CPUSER.tar.gz" ]];then
                        echo "[BACKUP] $CPUSER"
                        "$PKGACCT" --backup "$CPUSER" "$BACKUPFINALDIR" > /dev/null 2>&1
                elif [[ -f "$BACKUPFINALDIR/$CPUSER.tar.gz" ]];then
                        echo "[BACKUP] $CPUSER = already exist"
                fi
        done
}

function _backup_uncompressed {
        "$JQ" -r '.data.acct[].user' "$TMPLISTACCTS"|sort|while read -r CPUSER;do
                if [[ ! -f "$BACKUPFINALDIR/$CPUSER.tar" ]];then
                        echo "[BACKUP] $CPUSER"
                        "$PKGACCT" --backup --nocompress "$CPUSER" "$BACKUPFINALDIR" > /dev/null 2>&1
                elif [[ -f "$BACKUPFINALDIR/$CPUSER.tar" ]];then
                        echo "[BACKUP] $CPUSER = already exist"
                fi
        done
}

function _backup_incremental {
        "$JQ" -r '.data.acct[].user' "$TMPLISTACCTS"|sort|while read -r CPUSER;do
                if [[ ! -d "$BACKUPFINALDIR/$CPUSER" ]];then
                        echo "[BACKUP] $CPUSER"
                        "$PKGACCT" --backup --incremental "$CPUSER" "$BACKUPFINALDIR" > /dev/null 2>&1
                elif [[ -d "$BACKUPFINALDIR/$CPUSER" ]];then
                        echo "[BACKUP] $CPUSER = already exist"
                fi
        done
}

function _backup_type {
        BACKUPTYPE=$("$JQ" -r '.data.backup_config.backuptype' "$TMPBACKUPCONFIG");
        if [[ "$BACKUPTYPE" = "compressed" ]];then
                _backup_compressed
        elif [[ "$BACKUPTYPE" = "uncompressed" ]];then
                _backup_uncompressed
        elif [[ "$BACKUPTYPE" = "incremental" ]];then
                _backup_incremental
        fi
        
}

function _do_generate_backup {
        _backup_type

        "$JQ" -r '.data.acct[].user' "$TMPLISTACCTS"|sort|while read -r CPUSER;do
                echo "[METADATA] $CPUSER"
                "$CREATEMETADATA" --user="$CPUSER" > /dev/null 2>&1
        done
}

function _backup_monthly_enable {
        if [[ "$("$JQ" -r '.data.backup_config.backup_monthly_enable' "$TMPBACKUPCONFIG")" -eq 1 ]];then
                BACKUPDIR=$($JQ -r '.data.backup_config.backupdir' "$TMPBACKUPCONFIG")
                BACKUPFINALDIR="$BACKUPDIR/monthly/$(date +%F)/accounts"
                BACKUPREMOTEDIR="monthly/$(date +%F)"
                TODAY=$("$DATE" +%e)
                $JQ -r '.data.backup_config.backup_monthly_dates' "$TMPBACKUPCONFIG"|"$TR" ',' '\n'|while read -r MONTHLYDAYS;do
                        if [[ "$TODAY" -eq $MONTHLYDAYS ]];then
                                if [[ -d "$BACKUPFINALDIR" ]];then
                                        _do_generate_backup
                                elif [[ ! -d "$BACKUPFINALDIR" ]];then
                                        "$MKDIR" -p "$BACKUPFINALDIR"
                                        _do_generate_backup
                                fi
                                _is_additional_backup_enable
                        fi
                done
        fi
}

function _backup_weekly_enable {
        if [[ "$("$JQ" -r '.data.backup_config.backup_weekly_enable' "$TMPBACKUPCONFIG")" -eq 1 ]];then
                BACKUPDIR=$($JQ -r '.data.backup_config.backupdir' "$TMPBACKUPCONFIG")
                BACKUPFINALDIR="$BACKUPDIR/weekly/$(date +%F)/accounts"
                BACKUPREMOTEDIR="weekly/$(date +%F)"
                TODAY=$("$DATE" +%w)
                WEEKLYDAY=$($JQ -r '.data.backup_config.backup_weekly_day' "$TMPBACKUPCONFIG")
                if [[ "$TODAY" -eq "$WEEKLYDAY" ]];then
                        if [[ -d "$BACKUPFINALDIR" ]];then
                                _do_generate_backup
                        elif [[ ! -d "$BACKUPFINALDIR" ]];then
                                "$MKDIR" -p "$BACKUPFINALDIR"
                                _do_generate_backup
                        fi
                        _is_additional_backup_enable
                fi
        fi
}

function _backup_dailiy_enable {
        if [[ "$("$JQ" -r '.data.backup_config.backup_daily_enable' "$TMPBACKUPCONFIG")" -eq 1 ]];then
                BACKUPDIR=$($JQ -r '.data.backup_config.backupdir' "$TMPBACKUPCONFIG")
                BACKUPFINALDIR="$BACKUPDIR/$(date +%F)/accounts"
                BACKUPREMOTEDIR="$(date +%F)"
                TODAY=$("$DATE" +%w)
                $JQ -r '.data.backup_config.backupdays' "$TMPBACKUPCONFIG"|"$TR" ',' '\n'|while read -r DAILYDAYS;do
                        if [[ "$TODAY" -eq $DAILYDAYS ]];then
                                if [[ -d "$BACKUPFINALDIR" ]];then
                                        _do_generate_backup
                                elif [[ ! -d "$BACKUPFINALDIR" ]];then
                                        "$MKDIR" -p "$BACKUPFINALDIR"
                                        _do_generate_backup
                                fi
                                _is_additional_backup_enable
                        fi
                done
        fi
}

function _send_to_destinaton_backup_ftp {
        echo "[REMOTE BACKUP] Remote Backup to FTP Server is under development - Skipped to [$SFTPHOST]"
}

function _send_to_destinaton_backup_sftp {
        SFTPUSERNAME=$("$JQ" -r '.data.destination_list[]|select(.id=="'"$IDS"'").username' "$TMPBACKUPDST")
        SFTPHOST=$("$JQ" -r '.data.destination_list[]|select(.id=="'"$IDS"'").host' "$TMPBACKUPDST")
        SFTPPORT=$("$JQ" -r '.data.destination_list[]|select(.id=="'"$IDS"'").port' "$TMPBACKUPDST")
        SFTPPRIVATEKEY=$("$JQ" -r '.data.destination_list[]|select(.id=="'"$IDS"'").privatekey' "$TMPBACKUPDST")

        echo "[REMOTE BACKUP] [$SFTPHOST] Create Remote Backup Dir at SFTP Remote Backup Server"
        "$SSH" -p "$SFTPPORT" -i "$SFTPPRIVATEKEY" "$SFTPUSERNAME"@"$SFTPHOST" "$MKDIR -p $BACKUPREMOTEDIR" > /dev/null 2>&1

        echo "[REMOTE BACKUP] [$SFTPHOST] Rsync Backup to SFTP Remote Backup Server"
        "$RSYNC" -avHP "$BACKUPFINALDIR" -e "$SSH -p $SFTPPORT -i $SFTPPRIVATEKEY" "$SFTPUSERNAME"@"$SFTPHOST":"$BACKUPREMOTEDIR" > /dev/null 2>&1

}

function _validate_destination_backup {
        if [[ $("$WHMAPI1" backup_destination_validate --output=jsonpretty id="$IDS" disableonfail="0"|"$JQ" -r '.metadata.result') -eq 1 ]];then
                echo "[REMOTE BACKUP] $IDS is valid"
                TYPE=$("$JQ" -r '.data.destination_list[]|select(.id=="'"$IDS"'").type' "$TMPBACKUPDST");
                if [[ "$TYPE" = "SFTP" ]];then
                        echo "[REMOTE BACKUP] $IDS is SFTP"
                        _send_to_destinaton_backup_sftp
                elif [[ "$TYPE" = "FTP" ]];then
                        echo "[REMOTE BACKUP] $IDS is FTP"
                        _send_to_destinaton_backup_ftp
                fi
        fi
}

function _sftp_additional_backup_check {
        if [[ $("$JQ" -r '.data.destination_list[]|select(.type=="SFTP" and .authtype=="key" and .disabled=="0").id' "$TMPBACKUPDST"|wc -l) -gt 0 ]];then
                echo "[REMOTE BACKUP] There is Additional SFTP Backup Enabled"
                "$JQ" -r '.data.destination_list[]|select(.type=="SFTP" and .authtype=="key" and .disabled=="0").id' "$TMPBACKUPDST"|while read -r IDS;do
                        _validate_destination_backup
                done
        fi
}

function _ftp_additional_backup_check {
        if [[ $("$JQ" -r '.data.destination_list[]|select(.type=="FTP" and .disabled=="0").id' "$TMPBACKUPDST"|wc -l) -gt 0 ]];then
                echo "[REMOTE BACKUP] There is Additional FTP Backup Enabled"
                "$JQ" -r '.data.destination_list[]|select(.type=="FTP" and .disabled=="0").id' "$TMPBACKUPDST"|while read -r IDS;do
                        _validate_destination_backup
                done
        fi
}

function _is_additional_backup_enable {
        _get_backup_destination_list
        if [[ "$($JQ -r '.metadata.result' "$TMPBACKUPDST")" -eq 1 ]];then
                _sftp_additional_backup_check
                _ftp_additional_backup_check
        fi
}

function _is_backup_enable {
        if [[ $("$JQ" -r '.data.backup_config.backupenable' "$TMPBACKUPCONFIG") -eq 1 ]];then
                _backup_dailiy_enable
                _backup_weekly_enable
                _backup_monthly_enable
        fi
}

_init_vars
_get_listaccts
_backup_config_get
_is_backup_enable
_clear_tmp
