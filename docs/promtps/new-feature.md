Let's start a new feature. The feature id and description will be sent in this prompt, in the form ${feature-id}: ${feature-description} ask for them if not found or sure.
Then:
* Make sure that the feature id is unique, by checking if there is a branch with matching name
* If so, abort and report.
* If not:
** create a new ticket with the feature id as title and description.
** create a new branch with the feature id
** switch to that branch
