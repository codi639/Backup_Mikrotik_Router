#!/bin/bash

# set -x # Console debug purpose

# Local variables
Router_Username="user" # Username to connect to the router (I recommend to create a different user than admin).
Router_Password="passwd" # Change this password with the password of user you want to use to connect to the router.

File_Name=$(date +'%d-%m-%Y')

local_path_to_save="$HOME/path/to/save/the/backup"

SSH_Export_Conf="/export file=Configuration;" # Mikrotic command to export the configuration
SSH_Export_Backup="/system backup save name=Backup;" # Mikrotic command to export the backup

max_backup=199 # Number of backups to keep

i=1

timeout_ssh=5 # Timeout for the ssh and scp command

nbr_router_OK=0
nbr_router_KO=0

# Database variables
DB_User="root"
DB_Password="DB_passwd" # Change this password with the password of user you want to use to connect to the database.
DB_Name="DB_name"
DB_Host="1.3.5.7"

DB_Query="SELECT value FROM radreply WHERE attribute='DHCP-Your-IP-Address';" # Change this query according to your database.

# Forbidden addresses
Forbidden_Addresses=(1.1.1.1 1.2.3.4 5.6.7.8 10.12.14.16)

# Create the backup directory if it does not exists
if [ -d "backup" ]; then
    echo "Directory backup exists."
else
    echo "Error: Directory backup does not exists. Creating..."
    mkdir "backup"
fi

if [ -d "backup/report" ]; then
    echo "Directory report exists."
else
    echo "Error: Directory report does not exists. Creating..."
    mkdir "backup/report"
    for (( i=0; i<=$max_backup; i++ )); do
        touch "backup/report/report.$i"
    done
fi

# Function to rotate backups
rotate_backups() {
    # Loop that run every backup folder from the last one to the first one (198 to 199 ....... 0 to 1 in my case)
    for (( c=$max_backup-1; c>=0; c-- )); do
        src_folder="backup/$Router_IP/backup.$c"
        dst_folder="backup/$Router_IP/backup.$((c+1))"

        if [ -d "$src_folder" ]; then
            # Move individual files within src_folder to dst_folder
            for file in "$src_folder"/*; do
                if [ -f "$file" ]; then
                    mv "$file" "$dst_folder/"
                fi  
            done
            #mv "$src_folder"/* "$dst_folder" # for simplier version (still working but with error message)
        fi
    done
}

rotate_report() {
    # Loop that runs through every report folder from the last on to the first one (198 to 199 ....... 0 to 1 in my case)
    for (( i = $max_backup - 1; i >= 0; i-- )); do
        src_file="backup/report/report.$i"
        dst_file="backup/report/report.$((i+1))"

        if [ -f "$src_file" ]; then
            cp -r "$src_file" "$dst_file"
        fi
    done

    true > backup/report/report.0
}

# Function to check if the router is reachable
check_ping() {
    if ping -c 1 "$Router_IP" &> /dev/null; then
        echo "$Router_IP responsive."
        return 0
    else
        {
            echo "$Router_IP unreachable."
            echo "__________________________________"
            echo
        } | tee -a backup/report/report.0
        return 1
    fi
}

forbidden_router() {
    local ip_to_check="$1"
    for Forbidden_IP in "${Forbidden_Addresses[@]}";do
        #echo "Checking IP: $ip_to_check against Forbidden IP: $Forbidden_IP" # Debug purpose
        if [ "$ip_to_check" == "$Forbidden_IP" ]; then
            echo "Skipping action for Router_IP: $ip_to_check"
            return 0  # Skip action
        fi
    done
    return 1  # Do action
}

rotate_report

backup_start_time=$(date +"%y-%m-%d %T")

# Execution of the backup
for Router_IP in $(mysql -u $DB_User -p$DB_Password $DB_Name -N -B -e "$DB_Query") # Might need to add a '-h $DB_Host' option to specify the remote host of the database
do

    export IP_$1=$Router_IP # Extraction of IPs addresses from Router_IPs.txt


    # Test if the router is supposed to be backuped (Forbidden Addresses)
    if forbidden_router "$Router_IP"; then
        continue
    fi 


    # Done only if the router is reachable
    if check_ping; then
        echo "$Router_IP is responsive. Backup in progress..."

        # If Routers directory does not exists, create it.
        if [ -d "backup/$Router_IP" ]; then
            echo "Directory $Router_IP exists."
        else
            echo "Error: Directory $Router_IP does not exists. Creating..."
            mkdir "backup/$Router_IP"
        fi

        # If backup folders does not exists, create them.
        for rep in $(seq 0 $max_backup)
        do
            backup_folder="backup.$rep"
            if [ -d "backup/$Router_IP/$backup_folder" ]; then
                echo "Directory $backup_folder exists." > /dev/null
            else
                echo "Directory $backup_folder does not exists. Creating..." > /dev/null
                mkdir "backup/$Router_IP/$backup_folder"
            fi
        done

        rotate_backups

        # Execution of the backup on the router.
        sshpass -p"$Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=5 "$Router_Username"@"$Router_IP" "$SSH_Export_Conf" &> /dev/null # Connection and execution of the export command
        exit_code=$?
        # Error handling
        if [ $exit_code -eq 255 ]; then
            {
                echo "$Router_IP SSH export failed (timeout)"
            } | tee -a backup/report/report.0
        elif [ $exit_code -ne 0 ]; then
            {
                echo "$Router_IP SSH export failed"
            } | tee -a backup/report/report.0
        fi

        timeout $timeout_ssh sshpass -p"$Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=5 "$Router_Username"@"$Router_IP" "$SSH_Export_Backup" &> /dev/null # Connection and execution of the backup command
        exit_code=$?
        # Error handling
        if [ $exit_code -eq 255 ]; then
            {
                echo "$Router_IP SSH backup failed (timeout)"
            } | tee -a backup/report/report.0
        elif [ $exit_code -ne 0 ]; then
            {
                echo "$Router_IP SSH backup failed"
            } | tee -a backup/report/report.0
        fi

        # Copy of the backup files to the local machine.
        scp -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=5 "$Router_Username"@"$Router_IP":Configuration.rsc "$local_path_to_save/$Router_IP/backup.0/$File_Name-Conf.src" &> /dev/null # Copy of the export file from remote to local path
        exit_code=$?
        # Error handling
        if [ $exit_code -eq 255 ]; then
            {
                echo "$Router_IP export failed (timeout)"
            } | tee -a backup/report/report.0
            scp_state=1
        elif [ $exit_code -ne 0 ]; then
            {
                echo "$Router_IP export failed."
            } | tee -a backup/report/report.0
            scp_state=1
        fi

        sshpass -p"$Router_Password"  scp -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=5 "$Router_Username"@"$Router_IP":Backup.backup "$local_path_to_save/$Router_IP/backup.0/$File_Name-Back.backup" &> /dev/null # Copy of the backup file from remote to local path
        exit_code=$?
        # Error handling
        if [ $exit_code -eq 255 ]; then
            {
                echo "$Router_IP backup failed (timeout)"
            } | tee -a backup/report/report.0
            scp_state=1
        elif [ $exit_code -ne 0 ]; then
            {
                echo "$Router_IP backup failed."
            } | tee -a backup/report/report.0
            scp_state=1
        fi

        if [ $scp_state -ne 0 ]; then
            nbr_router_KO=$((nbr_router_KO+1))
        else
            nbr_router_OK=$((nbr_router_OK+1))
        fi
        {
            echo "__________________________________"
            echo
        } >> backup/report/report.0


    else
        echo "$Router_IP did not respond to ping. Backup aborted."
        echo
        nbr_router_KO=$((nbr_router_KO+1))
    fi

    i=$((i+1))
done

backup_end_time=$(date +"%y-%m-%d %T")

total_backup_time=$(( $(date -d "$backup_end_time" +%s) - $(date -d "$backup_start_time" +%s) ))
total_backup_hours=$((total_backup_time / 3600))
total_backup_minutes=$(( (total_backup_time % 3600) / 60 ))
total_backup_seconds=$((total_backup_time % 60))

echo "$nbr_router_OK routers backed up successfully."
echo "$nbr_router_KO routers failed to backup."

# To send the report mail it is necessary to configure postfix correctly, which this script does not do.

true > /tmp/brief_report.txt


{
    echo "Mikrotik backup:"
    echo "Start backup: $backup_start_time"
    echo
    echo "$nbr_router_OK backup OK"
    echo "$nbr_router_KO backup KO"
    echo
    echo "total backup time : $total_backup_hours hours $total_backup_minutes minutes $total_backup_seconds seconds"
} >> /tmp/brief_report.txt

dst_email="your@email.com"
subject_email="Daily report of the backup."
message=$(cat "/tmp/brief_report.txt" "backup/report/report.0")
#echo "$message"

echo "$message" | mail -s "$subject_email" "$dst_email"

# Send to the Telegram bot

TOKEN="0123456789:YourTokenHere"
chat_id="-51465126154"

cp backup/report/report.0 backup/report/report.0.log
#cp backup/report/report.0 /tmp/report.0.log

message_telegram=$(cat /tmp/brief_report.txt)

#curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
#    -d "chat_id=$chat_id" \
#    -d "text=$message_telegram" \
#    -d "parse_mode=markdown" \
#    > /dev/null

curl -s "https://api.telegram.org/bot$TOKEN/sendDocument" \
    -F chat_id="$chat_id" \
    -F document=@"backup/report/report.0.log" \
    -F caption="$message_telegram" \
    > /dev/null
