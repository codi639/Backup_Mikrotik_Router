#!/bin/bash

# set -x # Console debug purpose

# Router variables
Router_Username="Username" # Username to connect to the router (I recommend to create a different user than admin).
Router_Password="Password" # Change this password with the password of user you want to use to connect to the router.

SSH_Export_Conf="/export file=Configuration;" # Mikrotic command to export the configuration
SSH_Export_Backup="/system backup save name=Backup;" # Mikrotic command to export the backup

timeout_ssh=5 # Timeout for the ssh and scp command


# Telegram bot information
TOKEN="1234567890:AAAABBBBCCCCCDDDDDEEEEE"
chat_id="-1234567890"


# Mail information
dst_email="email@exemple.com"
subject_email="Daily router backup reports."

# Forbidden addresses
Forbidden_Addresses=(10.144.1.2 10.144.1.3 10.144.1.35 10.144.1.39 10.144.1.207 10.144.1.14 10.144.1.15 10.144.1.13 10.144.1.16 10.144.1.19)


# Some more variables
deployed_user_file="/path/of/your/script/user_deploy/user_deploy_report.txt"
router_IP_file="/path/of/your/TXT_file/Router_IPs.txt"

File_Name=$(date +'%d-%m-%Y')

local_path_to_save="/path/of/your/script/backbone/backup"

max_backup=89 # Number of backups to keep

nbr_router_OK=0
nbr_router_KO=0

backup_start_time=$(date +"%y-%m-%d %T")


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
        if [ "$ip_to_check" == "$Forbidden_IP" ]; then
            echo "Skipping action for Router_IP: $ip_to_check"
            return 0  # Skip action
        fi
    done
    return 1  # Do action
}

check_existing_user() {
    local ip_to_check="$1"

    grep "$ip_to_check " $deployed_user_file &> /dev/null
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        {
            echo "user backup for $ip_to_check not correctly setup."
        }
    fi
}

rotate_report


i=1
# Execution of the backup
for Router_IP in $(cat $router_IP_file); 
do

    export IP_$1=$Router_IP # Extraction of IPs addresses from Router_IPs.txt

    # Test if the router is supposed to be backuped (Forbidden Addresses)
    if forbidden_router "$Router_IP"; then
        continue
    fi


    # Done only if the router is reachable
    if check_ping; then
        echo "$Router_IP is responsive. Backup in progress..."
        scp_state=0
        error_status=0
        sleep 1
        
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
        sshpass -p"$Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh "$Router_Username"@"$Router_IP" "$SSH_Export_Conf" &> /dev/null # Connection and execution of the export command
        exit_code=$?

        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1

                if [ $exit_code -eq 255 ]; then
                    {
                    echo "$Router_IP SSH export failed (timeout)"
                    } | tee -a backup/report/report.0
                else
                    {
                    echo "$Router_IP SSH export failed"
                    } | tee -a backup/report/report.0
                fi
            }
        fi

        sshpass -p"$Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh "$Router_Username"@"$Router_IP" "$SSH_Export_Backup" &> /dev/null # Connection and execution of the backup command
        exit_code=$?

        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1

                if [ $exit_code -eq 255 ]; then
                    {
                    echo "$Router_IP SSH backup failed (timeout)"
                    } | tee -a backup/report/report.0
                else 
                    {
                    echo "$Router_IP SSH backup failed"
                    } | tee -a backup/report/report.0
                fi
            }
        fi

        # Copy of the backup files to the local machine.
        sshpass -p"$Router_Password"  scp -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh "$Router_Username"@"$Router_IP":Configuration.rsc "$local_path_to_save/$Router_IP/backup.0/$File_Name-Conf.src" &> /dev/null # Copy of the export file from remote to local path
        exit_code=$?

        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1

                if [ $exit_code -eq 255 ]; then
                    {
                    echo "$Router_IP export failed (timeout)"
                    } | tee -a backup/report/report.0
                else
                    {
                    echo "$Router_IP export failed."
                    } | tee -a backup/report/report.0
                    scp_state=1
                fi
            }
        fi

        sshpass -p"$Router_Password"  scp -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh "$Router_Username"@"$Router_IP":Backup.backup "$local_path_to_save/$Router_IP/backup.0/$File_Name-Back.backup" &> /dev/null # Copy of the backup file from remote to local path
        exit_code=$?

        sleep 1
            # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1
                
                if [ $exit_code -eq 255 ]; then
                    {
                    echo "$Router_IP backup failed (timeout)"
                    } | tee -a backup/report/report.0
                else
                    {
                    echo "$Router_IP backup failed."
                    } | tee -a backup/report/report.0
                    scp_state=1
                fi
            }
        fi


        if [ $scp_state -ne 0 ]; then
            nbr_router_KO=$((nbr_router_KO+1))
        else
            nbr_router_OK=$((nbr_router_OK+1))
        fi

        if [ $error_status -ne 0 ]; then

                {
                    check_existing_user "$Router_IP"
                    echo "__________________________________"
                    echo
                } >> backup/report/report.0
        fi

        echo


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


true > /tmp/brief_report.txt

{
    echo "Sauvegarde Mikrotik reseau hertzien :"
    echo "Start backup: $backup_start_time"
    echo
    echo "$nbr_router_OK sauvegarde OK"
    echo "$nbr_router_KO sauvegarde FAILED"
    echo
    echo "total backup time : $total_backup_hours hours $total_backup_minutes minutes $total_backup_seconds seconds"
} >> /tmp/brief_report.txt


# Send the email
message=$(cat "/tmp/brief_report.txt" "backup/report/report.0") 
echo "$message" | mail -s "$subject_email" "$dst_email"


# Send to the Telegram bot
cp backup/report/report.0 backup/report/report.0.log
#cp backup/report/report.0 /tmp/report.0.log

message_telegram=$(cat /tmp/brief_report.txt)

curl -s "https://api.telegram.org/bot$TOKEN/sendDocument" \
    -F chat_id="$chat_id" \
    -F document=@"backup/report/report.0.log" \
    -F caption="$message_telegram" \
    > /dev/null

