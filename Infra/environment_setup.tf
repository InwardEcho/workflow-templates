resource "github_repository_environment" "test_environment" {
  for_each    = toset(var.managed_repository_names)
  repository  = each.key # Uses the repository name from the loop
  environment = "test"

  reviewers {
    teams = [
      data.github_team.team_leads.id,
      data.github_team.qa_leads.id
    ]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment" "staging_environment" {
  for_each    = toset(var.managed_repository_names)
  repository  = each.key
  environment = "staging"

  reviewers {
    teams = [
      data.github_team.release_managers.id,
      data.github_team.tech_leads.id
    ]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment" "production_environment" {
  for_each    = toset(var.managed_repository_names)
  repository  = each.key
  environment = "production"

  wait_timer = 60

  reviewers {
    teams = [
      data.github_team.release_managers.id,
      data.github_team.security_officers.id,
      data.github_team.product_owners.id
    ]
  }

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}
