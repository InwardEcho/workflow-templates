terraform {
  required_providers {
    github = {
      source  = "hashicorp/github"
      version = "~> 6.0" # This version constraint is compatible with the hashicorp/github provider
    }
  }
}

# Configure the GitHub Provider
# It will use the GITHUB_TOKEN environment variable by default.
provider "github" {
  token = var.github_token # If using an input variable
  owner = var.github_owner # Your GitHub organization or username
}
