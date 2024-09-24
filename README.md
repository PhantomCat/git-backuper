# Backuping script set for studio git repos
This bash script automates the process of configuring email alerts and automated backups for a storage device. 

**Functionality:**

* Allows setting email recipients for notifications.
* Configures various parameters for automated backups like:
    * USB device name
    * Disk label prefix
    * Backup directory
    * Backup frequency (monthly, weekly, daily)
* Tests and validates email addresses before proceeding.
* Installs necessary software if not already present.
* Creates a configuration file (`gbkp.conf`) with the specified settings.
* Updates cron job to trigger the backup script.
* Configures SMTP settings for email alerts.

**Features:**

* Includes thorough validation for email addresses.
* Provides feedback to the user throughout the process.
* Offers a clear confirmation before committing changes.

First of all - get the repository list that you're want to back up.
 - To get the repository list in .json format you have to use gitlab api:
   - `https://your-gitlab-host/api/v4/projects`
      You can automate this, but I don't see the need of that step
 - After that, you need to save the .json file in directory, naming it like as:
   - gbkp_YOUR-REPO-NAME.json, the script will find it as the `gbkp*.json`

Second step - run the install script from superuser.
 - `sudo ./install.sh`
 - If you want to change parameters - change `/etc/gbkp.conf` file
 - If you want to add the repositories list to existing - put the new file in this directory and run the install script again with parameter `--add-json`
 - If you want to change the repositories list - put the new file in this directory and run the install script again with parameter `--new-json`


