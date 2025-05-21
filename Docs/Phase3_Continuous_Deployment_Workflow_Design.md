# Phase 3: Continuous Deployment (CD) Workflow Design

This document outlines the detailed design for the Continuous Deployment (CD) caller workflows: `cd-dev-environment.yml`, `cd-test-environment.yml`, and `cd-prod-environment.yml`. It also refines the specifications for the reusable workflows primarily used in these CD pipelines: `reusable-iac-terraform.yml`, `reusable-database-migration-efcore.yml`, `reusable-deploy-environment.yml`, and `reusable-canary-deployment.yml`.

## A. `cd-dev-environment.yml` (Caller Workflow)

*   **Filename:** `.github/workflows/cd-dev-environment.yml`
*   **Purpose:** Deploys a version from `ci-unified.yml` to the DEV environment. Triggers TEST deployment for main branch pipelines.
*   **Triggers:**
    ```yaml
    on:
      workflow_dispatch:
        inputs:
          version_to_deploy:
            description: 'Version to deploy (e.g., 1.2.3 or 1.2.3-feature-xyz.5)'
            required: true
            type: string
          source_artifact_name:
            description: 'Name of the build artifact (e.g., release-1.2.3-app-package)'
            required: true
            type: string
          source_branch_is_main:
            description: 'Was the CI source the main branch? (true/false)'
            required: true
            type: boolean
            default: false # Important: default to false for safety if manually dispatched
      workflow_run:
        workflows: ["ci-unified.yml"] # Name of the CI workflow file from Phase 2
        types:
          - completed
    ```
*   **Permissions:** `contents: read`, `actions: write`, `id-token: write`
*   **Concurrency:** `group: ${{ github.workflow }}-dev-${{ github.event.inputs.version_to_deploy || github.event.workflow_run.head_commit.id }}`, `cancel-in-progress: true`
*   **Jobs:**

    1.  **`prepare_deployment_info`**
        *   `name: Prepare DEV Deployment Information`
        *   `runs-on: ubuntu-latest`
        *   `outputs:` `version`, `artifact_name`, `is_main_pipeline`
        *   **Steps:**
            *   Consolidate trigger info (from `workflow_dispatch` or `workflow_run`).
                *   **Note on `workflow_run` artifact passing:** The `ci-unified.yml` should upload a small JSON artifact (e.g., `deployment-params-${{ github.run_id }}.json`) containing `version_to_deploy`, `source_artifact_name`, and `source_branch_is_main`. This step will download that specific artifact using `actions/download-artifact` (potentially needing to list artifacts from the triggering run if the name isn't perfectly predictable or passed via a more direct mechanism if GitHub Actions evolves this capability). For now, assume the artifact name is predictable or a mechanism to fetch it is implemented.
                ```yaml
                # Example for workflow_run artifact fetching (conceptual)
                # - name: Download parameters from CI run
                #   if: github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success'
                #   uses: dawidd6/action-download-artifact@v6 # Example action
                #   with:
                #     workflow: ${{ github.event.workflow_run.workflow_id }}
                #     run_id: ${{ github.event.workflow_run.id }}
                #     name: "deployment-params-${{ github.event.workflow_run.id }}" # Predictable name
                #     path: ./params
                # - name: Load parameters
                #   if: github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success'
                #   id: load_params
                #   run: |
                #     VERSION=$(jq -r .version_to_deploy ./params/params.json)
                #     # ... load other params ...
                #     echo "version=$VERSION" >> $GITHUB_OUTPUT
                ```

    2.  **`deploy_to_dev`**
        *   `name: Deploy to DEV Environment`
        *   `runs-on: ubuntu-latest`
        *   `needs: prepare_deployment_info`
        *   `if: needs.prepare_deployment_info.outputs.version != '' && needs.prepare_deployment_info.outputs.version != 'FETCHED_VERSION_FROM_CI_ARTIFACT'` # Ensure params were fetched
        *   `environment:` `name: Development`, `url: ${{ vars.DEV_ENVIRONMENT_URL }}`
        *   **Steps:**
            *   Download Application Artifact (using `needs.prepare_deployment_info.outputs.artifact_name`).
            *   Call `reusable-iac-terraform.yml` (for DEV).
            *   Call `reusable-database-migration-efcore.yml` (for DEV).
            *   Call `reusable-deploy-environment.yml` (for DEV).

    3.  **`trigger_test_deployment`**
        *   `name: Trigger TEST Deployment`
        *   `runs-on: ubuntu-latest`
        *   `needs: [prepare_deployment_info, deploy_to_dev]`
        *   `if: success() && needs.prepare_deployment_info.outputs.is_main_pipeline == 'true'`
        *   **Steps:** Dispatch `cd-test-environment.yml` (passing `version`, `artifact_name`).

    4.  **`report_dev_cd_status`**
        *   `name: Report DEV CD Status`
        *   `runs-on: ubuntu-latest`
        *   `needs: [prepare_deployment_info, deploy_to_dev]`
        *   `if: always()`
        *   **Steps:** Call `reusable-observability-hooks.yml`.

## B. `cd-test-environment.yml` (Caller Workflow)

*   **Filename:** `.github/workflows/cd-test-environment.yml`
*   **Purpose:** Deploys to TEST with approvals. Triggers PROD deployment.
*   **Triggers:** `workflow_dispatch` (inputs: `version_to_deploy`, `source_artifact_name`), `workflow_run` (from `cd-dev-environment.yml`).
*   **Permissions & Concurrency:** Similar to DEV CD, adjusted for TEST.
*   **Jobs:**

    1.  **`prepare_test_deployment_info`**: Similar to DEV, for TEST triggers.
    2.  **`deploy_to_test`**
        *   `name: Deploy to TEST Environment`
        *   `environment:` `name: Test`, `url: ${{ vars.TEST_ENVIRONMENT_URL }}` (Configure reviewers in GitHub Environment settings).
        *   **Steps:** Download Artifact, Call IAC (TEST), Call DB Migration (TEST), Call App Deployment (TEST).
    3.  **`trigger_prod_deployment`**: `if: success()`, Dispatches `cd-prod-environment.yml`.
    4.  **`report_test_cd_status`**: Reports TEST CD status.

## C. `cd-prod-environment.yml` (Caller Workflow)

*   **Filename:** `.github/workflows/cd-prod-environment.yml`
*   **Purpose:** Deploys to PROD with approvals and canary strategy.
*   **Triggers:** `workflow_dispatch` (inputs: `version_to_deploy`, `source_artifact_name`), `workflow_run` (from `cd-test-environment.yml`).
*   **Permissions & Concurrency:** Similar, for PROD.
*   **Jobs:**

    1.  **`prepare_prod_deployment_info`**: Similar, for PROD triggers.
    2.  **`deploy_to_prod`**
        *   `name: Deploy to PRODUCTION Environment (Canary)`
        *   `environment:` `name: Production`, `url: ${{ vars.PROD_ENVIRONMENT_URL }}` (Configure reviewers).
        *   **Steps:** Download Artifact, Call IAC (PROD), Call DB Migration (PROD - consider timing relative to canary), Call `reusable-canary-deployment.yml`.
    3.  **`report_prod_cd_status`**: Reports PROD CD status.

---
## D. `reusable-iac-terraform.yml` (Refined)

*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `working-directory`: (string, required) Terraform directory.
        *   `terraform-command`: (string, required) 'init', 'validate', 'plan', 'apply', 'destroy'.
        *   `environment`: (string, required) Target environment (e.g., 'dev', 'test', 'prod').
        *   `plan-output-file`: (string, optional, default: `tfplan.out`)
        *   `backend-config-file`: (string, optional) e.g., `backend-dev.config`
        *   `var-file`: (string, optional) e.g., `terraform.${{ inputs.environment }}.tfvars`
        *   `apply-auto-approve`: (boolean, optional) Default `true` for non-prod, `false` for prod.
    *   **Secrets:** Cloud provider credentials (e.g., `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`). These should be environment-specific secrets in GitHub if possible.
*   **Jobs/Steps:** Setup Terraform, `init` (with backend config), `workspace select/new`, execute `terraform-command` with options.

---
## E. `reusable-database-migration-efcore.yml` (Refined)

*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `efcore-project-path`: (string, required)
        *   `environment`: (string, required)
        *   `connection-string`: (string, required, **Note: Passed as a secret from the caller, not directly as input value**)
        *   `backup-required`: (boolean, optional) Default `true` for prod, `false` otherwise.
        *   `migration-timeout`: (string, optional, default: `5m`)
    *   **Secrets:** (The caller passes the actual connection string via a secret that this workflow receives, e.g. `DB_CONNECTION_STRING_FROM_CALLER`)
*   **Jobs/Steps:** Optional backup, `dotnet ef database update --connection "${{ secrets.DB_CONNECTION_STRING_FROM_CALLER }}"`.

---
## F. `reusable-deploy-environment.yml` (Refined)

*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `environment-name`: (string, required)
        *   `artifact-path`: (string, required) Path to downloaded application artifact.
        *   `deployment-target-type`: (string, required) 'azure-app-service', 'kubernetes-manifest', 'custom-script'.
        *   `version-being-deployed`: (string, optional)
        *   *(Target-specific inputs: `azure-app-name`, `kubernetes-namespace`, `custom-script-path`, etc.)*
        *   `health-check-url`: (string, optional)
    *   **Secrets:** Deployment credentials (e.g., `AZURE_CREDENTIALS`, `KUBE_CONFIG_DATA`).
*   **Jobs/Steps:** Target-specific deployment steps, optional health check.

---
## G. `reusable-canary-deployment.yml` (Refined)

*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `environment-name`: (string, required) Base environment name (e.g., 'prod').
        *   `artifact-path`: (string, required)
        *   `version`: (string, required)
        *   `canary-percentage`: (integer, optional, default: `10`)
        *   `observation-period-minutes`: (integer, optional, default: `30`)
        *   `health-check-url-pattern`: (string, required) e.g., `https://my-app-${{ inputs.environment-name }}-canary.example.com/health`
        *   `primary-deployment-target-type`: (string, required)
        *   *(Target-specific inputs for canary slice and primary, e.g., `azure-app-name-canary-slot`, `azure-app-name-production-slot`)*
        *   `rollback-on-failure`: (boolean, optional, default: `true`)
    *   **Secrets:** Deployment credentials.
*   **Jobs/Steps:** Deploy to canary, Monitor, Promote or Rollback. This workflow might internally call `reusable-deploy-environment.yml` for the actual deployment to canary and primary instances/slots.