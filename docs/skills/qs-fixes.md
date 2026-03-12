You are an expert level solidity engineer. Let's open a new pr on a new branch against v0.5-qs-fixes as the base branch. The branch should be titled fix/insert-details-from-issue-title-here This PR should address the issue here by:

- Validate the issue and determine it's valid with a test, and not a false positive finding.
- If the issue is valid, implement the recommended fix for the issue and write a test to verify.
- Re-Run all tests to make sure everything is working.
- Check the events and errors
- Put your tests in test/findings/2026-03-09
- Double check your code for issues and don't make any mistakes.
- run forge fmt to format before your final commit
- Before finalizing the PR, delete all AI-generated docs markdown files that were created during this run. We do not want excess docs as part of the codebase and any docs you wrote should not be committed.
- Squash all commits into a single commit with the issue title as the commit message
