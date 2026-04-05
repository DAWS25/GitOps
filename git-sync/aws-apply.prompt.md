take the following steps to apply changes to AWS infrastructure:
* review recent changed files.
* save and commit all files with reasonable message summarizing recent changes.
* check for anything that should not be commited, such as secrets, and remove them from the commit. if secrets are found, stop and report to user.
* sync git (pull, push) 
* source .envrc and execute the script mentioned in the end of this file.
* Monitor output for errors. 
* Verify script completion.

SCRIPT TO EXECUTE: aws-apply.sh