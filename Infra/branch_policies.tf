resource "github_branch_protection" "main_branch_protection" {
  for_each      = toset(var.managed_repository_names)
  repository_id = data.github_repository.managed_repos[each.key].node_id # Uses node_id from the data source
  pattern       = "main"

  required_pull_request_reviews {
    required_approving_review_count = 2
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = true

    dismissal_restrictions = [
      "${var.github_owner}/${var.team_slug_senior_developers}",
      "${var.github_owner}/${var.team_slug_architects}",
    ]
  }

  required_status_checks {
    strict   = true
    contexts = ["Build and Test", "Code Quality Gates", "Security Scan"]
  }

  enforce_admins = true

  restrict_pushes {
    push_allowances = [
      "${var.github_owner}/${var.team_slug_release_managers}",
      "${var.github_owner}/${var.team_slug_devops_team}",
    ]
  }

  # Other common and recommended protections:
  required_linear_history = true  # Prevents merge commits, forces squash or rebase.
  allows_force_pushes     = false # Protects branch history integrity. CRITICAL: Set to false.
  allows_deletions        = false # Protects against accidental deletion of the main branch. CRITICAL: Set to false.
  # require_signed_commits = true      # Enhances security by verifying commit authenticity.
  # Requires developers to set up GPG/SSH commit signing.
  # Consider enabling if your team is prepared for this.
  require_conversation_resolution = true # Ensures all review comments are addressed before merging.
}

# ------------------------------------------------------------------------------
# Repository Security & Analysis Settings
# Applied to each repository in var.managed_repository_names
# ------------------------------------------------------------------------------

resource "github_repository_dependabot_security_updates" "managed_repo_dependabot_updates" {
  for_each   = toset(var.managed_repository_names)
  repository = each.key # Uses the repository name from the loop
  enabled    = true
}

# Note on CODEOWNERS:
# For `require_code_owner_reviews = true` to be effective, a CODEOWNERS file
# must exist in the repository (typically at .github/CODEOWNERS, docs/CODEOWNERS, or CODEOWNERS in root).
# This file defines individuals or teams responsible for code in different parts of the repository.
# Managing the CODEOWNERS file content itself is usually done directly in the Git repository, not via Terraform.

# Organization level settings and CodeQL default setup are omitted for brevity.