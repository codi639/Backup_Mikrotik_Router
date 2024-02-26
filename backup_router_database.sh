#!/bin/bash

#set -x # Console debug purpose

# Router variables
Router_Username="backup" # Username to connect to the router (I recommend to create a different user than admin).
Router_Password="backup" # Change this password with the password of user you want to use to connect to the router for the backup.
New_Address="192.168.88.1"
New_Group="full"
Vog_Router_Username="admin" # Default username to connect and deploy the user backup
Vog_Router_Password="admin" # Default password to connect and deploy the password of backup user


SSH_Export_Conf="/export file=Configuration;" # Mikrotic command to export the configuration
SSH_Export_Backup="/system backup save name=Backup;" # Mikrotic command to export the backup

timeout_ssh=5 # Timeout for the ssh and scp command


# Database variables
DB_User="user"
DB_Password="password" # Change this password with the password of user you want to use to connect to the database.
DB_Name="base"
DB_Host="1.2.3.4"

DB_Query="SELECT value FROM radreply WHERE attribute='DHCP-Your-IP-Address';" # Change the query at you convenience


# Telegram bot information
TOKEN="1234567890:ZFf56gf2dsdg6s5g5df62qgqf62"
chat_id="-1234567890"


# Email information
dst_email="example@email.com"
subject_email="Rapport de sauvegarde routeurs hertzien."


# Forbidden addresses
Forbidden_Addresses=(10.144.1.2 10.144.1.3 10.144.1.35 10.144.1.39 10.144.1.207 10.144.1.14 10.144.1.15 10.144.1.13 10.144.1.16 10.144.1.19 10.144.1.53)


# Some more variables
basic_path="/the/script/path" # Absolute path for cronjob

nbr_router_OK=0
nbr_router_KO=0

File_Name=$(date +'%d-%m-%Y')

local_path_to_save="/the/script/path/backup"

max_backup=89 # Number of backups to keep

backup_start_time=$(date +"%y-%m-%d %T")


# Create the backup directory if it does not exists
if [ -d "$basic_path/backup" ]; then
    echo "Directory backup exists."
else
    echo "Error: Directory backup does not exists. Creating..."
    mkdir "$basic_path/backup"
fi

if [ -d "$basic_path/backup/report" ]; then
    echo "Directory report exists."
else
    echo "Error: Directory report does not exists. Creating..."
    mkdir "$basic_path/backup/report"
    for (( i=0; i<=$max_backup; i++ )); do
        touch "$basic_path/backup/report/report.$i"
    done
fi

# Function to rotate backups
rotate_backups() {
    # Loop that run every backup folder from the last one to the first one (88 to 89 ....... 0 to 1 in my case)
    for (( c=$max_backup-1; c>=0; c-- )); do
        src_folder="$basic_path/backup/$Router_IP/backup.$c"
        dst_folder="$basic_path/backup/$Router_IP/backup.$((c+1))"
#        echo "Moving files from $src_folder to $dst_folder"

        if [ -d "$src_folder" ]; then
#            echo "$src_folder Exist"
            # Move individual files within src_folder to dst_folder
            for file in "$src_folder"/*; do
                if [ -f "$file" ]; then
                    mv "$file" "$dst_folder/"
                fi  
            done
            rm -f "$src_folder"/*
#        else
#            echo "probleme dans la rotation des backups"
        fi
    done
}

rotate_report() {
    # Loop that runs through every report folder from the last on to the first one
    for (( i = $max_backup - 1; i >= 0; i-- )); do
        src_file="$basic_path/backup/report/report.$i"
        dst_file="$basic_path/backup/report/report.$((i+1))"

        if [ -f "$src_file" ]; then
            mv "$src_file" "$dst_file"
        fi
    done

    true > $basic_path/backup/report/report.0
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
        } | tee -a $basic_path/backup/report/report.0
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

    # grep the return of /user print command to check if backup is there
    sshpass -p"$Vog_Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Vog_Router_Username"@"$Router_IP" "/user print" | grep "backup" &> /dev/null
    local exit_code1=$?
    if [ $exit_code1 -ne 0 ]; then # If the grep command didn't return something, then the user is not deployed on the router
        {
            echo "User backup for $ip_to_check not correctly deployed."
            sshpass -p"$Vog_Router_Password" ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Vog_Router_Username"@"$Router_IP" "/user add name=$Router_Username group=$New_Group password=$Router_Password address=$New_Address;" 2> /dev/null

            local exit_code2=$?
            sleep 1
            # Error handling
            if [ $exit_code2 -ne 0 ]; then
                {
                    if [ $exit_code2 -eq 255 ]; then
                        {
                        echo "$Router_IP deploy user backup failed (timeout)"
                        } | tee -a $basic_path/backup/report/report.0
                    else
                        {
                        echo "$Router_IP deploy user backup failed"
                        } | tee -a $basic_path/backup/report/report.0
            
                    fi
                }
                
            else
                {
                    {
                    echo "$Router_IP user backup deployed"
                    } | tee -a $basic_path/backup/report/report.0
                    # Check if the new user is correctly set
                    sshpass -p"$Router_Password" ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP" "/quit" 2> /dev/null
                    exit_code=$?
                    sleep 1
                    # Error handling
                    if [ $exit_code -eq 255 ]; then
                        {
                            echo "User connection for $Router_IP failed (timeout)"
                            echo
                        } | tee -a $basic_path/backup/report/report.0
                    elif [ $exit_code -ne 1 ] && [ $exit_code -ne 0 ] ; then
                        {
                            echo "User connection for $Router_IP failed"
                            echo
                        } | tee -a $basic_path/backup/report/report.0
                    fi
                }
                
            fi
        } 
    fi
}

rotate_report

i=1
# Execution of the backup
for Router_IP in $(mysql -u $DB_User -p$DB_Password $DB_Name -h $DB_Host -N -B -e "$DB_Query")
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
        if [ -d "$basic_path/backup/$Router_IP" ]; then
            echo "Directory $Router_IP exists."
        else
            echo "Error: Directory $Router_IP does not exists. Creating..."
            mkdir "$basic_path/backup/$Router_IP"
        fi

        # If backup folders does not exists, create them.
        for rep in $(seq 0 $max_backup)
        do
            backup_folder="backup.$rep"
            if [ -d "$basic_path/backup/$Router_IP/$backup_folder" ]; then
                echo "Directory $backup_folder exists." > /dev/null
            else
                echo "Directory $backup_folder does not exists. Creating..." > /dev/null
                mkdir "$basic_path/backup/$Router_IP/$backup_folder"
            fi
        done

        rotate_backups

        # Check if the user is deployed on the router and deploy it if not.
        check_existing_user "$Router_IP"

        # Execution of the backup on the router.
        sshpass -p"$Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP" "$SSH_Export_Conf" &> /dev/null # Connection and execution of the export command
        exit_code=$?
    
        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1

                if [ $exit_code -eq 255 ]; then
                    {
                    echo "$Router_IP SSH export failed (timeout)"
                    } | tee -a $basic_path/backup/report/report.0
                else
                    {
                    echo "$Router_IP SSH export failed"
                    } | tee -a $basic_path/backup/report/report.0
                fi
            }
        fi

        sshpass -p"$Router_Password"  ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP" "$SSH_Export_Backup" &> /dev/null # Connection and execution of the backup command
        exit_code=$?
        
        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1

                if [ $exit_code -eq 255 ]; then
                        {
                        echo "$Router_IP SSH backup failed (timeout)"
                        } | tee -a $basic_path/backup/report/report.0
                else 
                        {
                        echo "$Router_IP SSH backup failed"
                        } | tee -a $basic_path/backup/report/report.0
                fi
            }
        fi

        # Copy of the backup files to the local machine.
        sshpass -p"$Router_Password"  scp -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP":Configuration.rsc "$local_path_to_save/$Router_IP/backup.0/$File_Name-Conf.src" &> /dev/null # Copy of the export file from remote to local path
        exit_code=$?
        
        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1
                {
                echo "$Router_IP export failed."
                } | tee -a $basic_path/backup/report/report.0
                scp_state=1
            }
        fi

        sshpass -p"$Router_Password"  scp -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP":Backup.backup "$local_path_to_save/$Router_IP/backup.0/$File_Name-Back.backup" &> /dev/null # Copy of the backup file from remote to local path
        exit_code=$?
        
        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                error_status=1
                {
                echo "$Router_IP backup failed."
                } | tee -a $basic_path/backup/report/report.0
                scp_state=1
            }
        fi

        if [ $scp_state -ne 0 ]; then
            nbr_router_KO=$((nbr_router_KO+1))
        else
            nbr_router_OK=$((nbr_router_OK+1))
        fi

        if [ $error_status -ne 0 ]; then
            {
                #check_existing_user "$Router_IP"
                echo "__________________________________"
                echo
            } | tee -a $basic_path/backup/report/report.0
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
message=$(cat "/tmp/brief_report.txt" "$basic_path/backup/report/report.0")
echo "$message" | mail -s "$subject_email" "$dst_email"


# Send to the Telegram bot
cp $basic_path/backup/report/report.0 $basic_path/backup/report/report.0.log
#cp backup/report/report.0 /tmp/report.0.log

message_telegram=$(cat /tmp/brief_report.txt)
curl -s "https://api.telegram.org/bot$TOKEN/sendDocument" \
    -F chat_id="$chat_id" \
    -F document=@"$basic_path/backup/report/report.0.log" \
    -F caption="$message_telegram" \
    > /dev/null


