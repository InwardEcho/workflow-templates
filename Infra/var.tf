variable "github_owner" {
  description = "Your GitHub organization name or username."
  type        = string
  default     = "InwardEcho"
}

variable "managed_repository_names" {
  description = "A list of existing repository names to apply standard configurations to."
  type        = list(string)
  default     = ["SampleApp"]
}

# Variables for Team Slugs (Replace defaults with your actual slugs or provide at runtime)
variable "team_slug_team_leads" {
  description = "Slug for the 'Team Leads' team."
  type        = string
  default     = "team-leads"
}

variable "team_slug_qa_leads" {
  description = "Slug for the 'QA Leads' team."
  type        = string
  default     = "qa-leads"
}

variable "team_slug_release_managers" {
  description = "Slug for the 'Release Managers' team."
  type        = string
  default     = "release-managers"
}

variable "team_slug_tech_leads" {
  description = "Slug for the 'Tech Leads' team."
  type        = string
  default     = "tech-leads"
}

variable "team_slug_security_officers" {
  description = "Slug for the 'Security Officers' team."
  type        = string
  default     = "security-officers"
}

variable "team_slug_product_owners" {
  description = "Slug for the 'Product Owners' team."
  type        = string
  default     = "product-owners"
}

variable "team_slug_senior_developers" {
  description = "Slug for the 'Senior Developers' team (for branch protection dismissal)."
  type        = string
  default     = "senior-developers"
}

variable "team_slug_architects" {
  description = "Slug for the 'Architects' team (for branch protection dismissal)."
  type        = string
  default     = "architects"
}

variable "team_slug_devops_team" {
  description = "Slug for the 'DevOps Team' (for branch protection push restrictions)."
  type        = string
  default     = "devops-team"
}

# Variables for Environment Secrets (Provide these securely, e.g., via TF_VAR_... env vars or a tfvars file)
# These secrets will be applied to ALL repositories in the 'managed_repository_names' list for the respective environment type.
# If you need per-repository secret values, a more complex variable structure (e.g., a map of maps) would be required.
variable "secret_test_api_key" {
  description = "API Key for the Test environment."
  type        = string
  sensitive   = true
}

variable "secret_staging_api_key" {
  description = "API Key for the Staging environment."
  type        = string
  sensitive   = true
}

variable "secret_production_db_password" {
  description = "Database password for the Production environment."
  type        = string
  sensitive   = true
}