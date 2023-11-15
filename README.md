# Mikrotik Router Backup Script

Simple scripts to locally save your configuration files.

These scripts will create a directory to store different backups of your router for up to 200 days. They will generate a report for each backup. These reports are saved locally, sent by email (you need to configure postfix to connect to a remote SMTP server), and sent to a Telegram bot.

You can choose to use them with a personal list of IP addresses in a text file or connect to your remote database. I'm using a MySQL connection, but you can easily change that if needed.

