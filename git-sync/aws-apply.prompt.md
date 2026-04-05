take the following steps, preferably in this order and same shell environment:
* review recent changed files, check for correctness and simplicity.
* save all changes and commit all files with reasonable message summarizing recent changes.
* check for anything that should not be commited, such as secrets, and remove them from the commit. if secrets are found, stop and report to user.
* sync git (pull, push) 
* source .envrc so that environment variables are loaded with parameters and secrets
* execute the target script mentioned in the end of this file.
* Monitor output for errors. 
* if errors are found, stop, try to fix them and re-run the script. if you cannot fix the errors, report to user and stop.
* Verify script completion.

TARGET SCRIPT TO EXECUTE: aws-apply.sh