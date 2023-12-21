#!/bin/bash

#set -x

# Router variables
Router_Username="Username" # Username to connect to the router (I recommend creating a different user than admin with this script).
Router_Password="Password" # Change this password with the password of user you want to use to connect to the router.


# set the new user variables
new_user="user"
new_password="psswd"
new_address="@IP"
new_group="full"


# Database variables
DB_User="DBUser"
DB_Password="DBPassword" # Change this password with the password of user you want to use to connect to the database.
DB_Name="DBName"
DB_Host="@Host"

DB_Query="SELECT value FROM radreply WHERE attribute='DHCP-Your-IP-Address';" # Query to get the IP addresses of the routers (you might need to change the query to match your database).


# Forbidden addresses
Forbidden_Addresses=(10.144.1.2 10.144.1.3 10.144.1.35 10.144.1.39 10.144.1.207)


# Some more variables
timeout_ssh=20 # Timeout for the ssh and scp command


# Create the user_deploy directory if it does not exists
if [ -d "user_deploy" ]; then
    echo "Directory user_deploy exists."
else
    echo "Error: Directory user_deploy does not exists. Creating..."
    mkdir "user_deploy"
fi

true > user_deploy/user_deploy_report.txt # Clear or create the user_deploy_report.txt file

# Function to check if the router is reachable
check_ping() {
    if ping -c 2 "$Router_IP" &> /dev/null; then
        echo "$Router_IP responsive."
        return 0
    else
        echo "$Router_IP unreachable." >> user_deploy/user_deploy_report.txt
        echo >> user_deploy/user_deploy_report.txt
        return 1
    fi
}

forbidden_router() {
    local ip_to_check="$1"
    for Forbidden_IP in "${Forbidden_Addresses[@]}";do
        #echo "Checking IP: $ip_to_check against Forbidden IP: $Forbidden_IP" # Debug purpose
        if [ "$ip_to_check" == "$Forbidden_IP" ]; then
            { echo "Skipping action for Router_IP: $ip_to_check"; echo ; } >> user_deploy/user_deploy_report.txt
            echo "Skipping action for Router_IP: $ip_to_check"
            return 0  # Skip action
        fi
    done
    return 1  # Do action
}

i=1
for Router_IP in $(mysql -u $DB_User -p$DB_Password $DB_Name -h $DB_Host -N -B -e "$DB_Query"); do
    export IP_$1=$Router_IP # Export the IP address of the router to use it in the ssh command

    if forbidden_router "$Router_IP"; then
        continue
    fi 

    if check_ping; then
        sleep 2

        sshpass -p"$Router_Password" ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP" "/user remove [find name="$new_user"];" 2> /dev/null
        sshpass -p"$Router_Password" ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$Router_Username"@"$Router_IP" "/user add name=$new_user group=$new_group password=$new_password address=$new_address;" 2> /dev/null
        exit_code=$?
        sleep 1
        # Error handling
        if [ $exit_code -ne 0 ]; then
            {
                if [ $exit_code -eq 255 ]; then
                    {
                    echo "$Router_IP SSH deploy failed (timeout)"
                    echo
                    } | tee -a user_deploy/user_deploy_report.txt
                elif [ $exit_code -ne 0 ]; then
                    {
                    echo "$Router_IP SSH deploy failed"
                    echo
                    } | tee -a user_deploy/user_deploy_report.txt
        
                fi
            }
            
        else
            {
                # Check if the new user is correctly set
                sshpass -p"$new_password" ssh -q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o ConnectTimeout=$timeout_ssh -o KexAlgorithms=diffie-hellman-group14-sha1 "$new_user"@"$Router_IP" "/quit" 2> /dev/null
                exit_code=$?
                sleep 1
                # Error handling
                if [ $exit_code -eq 255 ]; then
                    {
                        echo "$Router_IP SSH connection failed (timeout)"
                        echo
                    } | tee -a user_deploy/user_deploy_report.txt
                elif [ $exit_code -ne 1 ] && [ $exit_code -ne 0 ] ; then
                    {
                        echo "$Router_IP SSH connection failed"
                        echo
                    } | tee -a user_deploy/user_deploy_report.txt
                fi
            }
            
        fi

    else
        echo "$Router_IP did not respond to ping. SSH user deploy aborted."
        echo
    fi


    i=$((i+1))
done
