data "github_team" "team_leads" {
  slug = var.team_slug_team_leads
}

data "github_team" "qa_leads" {
  slug = var.team_slug_qa_leads
}

data "github_team" "release_managers" {
  slug = var.team_slug_release_managers
}

data "github_team" "tech_leads" {
  slug = var.team_slug_tech_leads
}

data "github_team" "security_officers" {
  slug = var.team_slug_security_officers
}

data "github_team" "product_owners" {
  slug = var.team_slug_product_owners
}

data "github_team" "senior_developers" {
  slug = var.team_slug_senior_developers
}

data "github_team" "architects" {
  slug = var.team_slug_architects
}

data "github_team" "devops_team" {
  slug = var.team_slug_devops_team
}

data "github_repository" "managed_repos" {
  for_each = toset(var.managed_repository_names)
  name     = each.key
  # owner is implicitly the one configured for the provider, or var.github_owner if set for provider
}
