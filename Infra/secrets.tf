
resource "github_actions_environment_secret" "test_api_key" {
  for_each        = toset(var.managed_repository_names)
  repository      = each.key
  environment     = github_repository_environment.test_environment[each.key].environment # References the looped environment
  secret_name     = "API_KEY_TEST"
  plaintext_value = var.secret_test_api_key
}

resource "github_actions_environment_secret" "staging_api_key" {
  for_each        = toset(var.managed_repository_names)
  repository      = each.key
  environment     = github_repository_environment.staging_environment[each.key].environment
  secret_name     = "API_KEY_STAGING"
  plaintext_value = var.secret_staging_api_key
}

resource "github_actions_environment_secret" "production_db_password" {
  for_each        = toset(var.managed_repository_names)
  repository      = each.key
  environment     = github_repository_environment.production_environment[each.key].environment
  secret_name     = "DATABASE_PASSWORD_PRODUCTION"
  plaintext_value = var.secret_production_db_password
}