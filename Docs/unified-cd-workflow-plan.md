# Plan: Unified Continuous Deployment Workflow

**1. Goal:**
Consolidate the three separate CD workflow files (`cd-dev-environment.yml`, `cd-test-environment.yml`, and `cd-prod-environment.yml`) into a single `unified-cd-workflow.yml`. This aims to:
*   Ensure a consistent sequence of deployment operations (e.g., infrastructure, database migration, application deployment) across Dev, Test, and Production environments.
*   Reduce duplication of common workflow structures.
*   Maintain the ability to handle environment-specific configurations, secrets, and deployment strategies through parameterization and conditional logic.
*   Leverage GitHub Environments for managing secrets and protection rules (like manual approvals).

**2. Proposed Unified Workflow File Structure (`.github/workflows/unified-cd-workflow.yml`):**

*   **Name:** `Unified CD Workflow`
*   **Triggers (`on`):**
    *   `workflow_dispatch`: To allow manual triggering for any environment and for promotions between environments.
        *   **Inputs:**
            *   `version_to_deploy`: (string, required) The version tag or identifier.
            *   `source_artifact_name`: (string, required) Name of the build artifact.
            *   `target_environment_type`: (string, required, choices: `dev`, `test`, `prod`) Specifies the logical environment type.
            *   `source_branch_is_main`: (boolean, optional, default: `false`) Indicates if the trigger is part of a main branch pipeline (relevant for DEV -> TEST promotion).

*   **Permissions:**
    *   `contents: read`
    *   `actions: write` (to trigger itself for promotions)
    *   `id-token: write` (for OIDC)

*   **Concurrency:**
    *   `group: unified-cd-${{ github.event.inputs.target_environment_type }}-${{ github.event.inputs.version_to_deploy }}`
    *   `cancel-in-progress: false` (especially for test/prod)

*   **Environment Variables (Global):**
    *   `DOTNET_SKIP_FIRST_TIME_EXPERIENCE: true`
    *   `DOTNET_CLI_TELEMETRY_OPTOUT: true`

*   **Jobs:**
    *   **`prepare_deployment_info`:**
        *   Runs on: `ubuntu-latest`
        *   Outputs: `version`, `artifact_name`, `is_main_pipeline`, `github_environment_name` (maps `dev` to "Development", `test` to "Test", `prod` to "Production").
        *   Steps:
            *   Validate inputs.
            *   Determine `github_environment_name` based on `inputs.target_environment_type`.
            *   Set outputs.
    *   **`deploy_and_validate`:**
        *   Runs on: `ubuntu-latest`
        *   Needs: `prepare_deployment_info`
        *   `environment`:
            *   `name: ${{ needs.prepare_deployment_info.outputs.github_environment_name }}`
            *   `url: ` (Dynamically generated based on environment and version, using GitHub variables like `vars.ENVIRONMENT_BASE_URL_${{ inputs.target_environment_type }}`)
        *   Steps:
            1.  **Checkout Repository:** `actions/checkout@v4`
            2.  **Download Application Artifact:** `actions/download-artifact@v4`
                *   `name: ${{ needs.prepare_deployment_info.outputs.artifact_name }}`
                *   `path: ./app-to-deploy`
            3.  **Apply Infrastructure (Terraform):**
                *   Uses: `./.github/workflows/reusable-iac-terraform.yml`
                *   `with`:
                    *   `working-directory: ./Infra/${{ inputs.target_environment_type }}`
                    *   `terraform-command: apply`
                    *   `environment: ${{ inputs.target_environment_type }}`
                    *   `var-file: terraform.${{ inputs.target_environment_type }}.tfvars`
                    *   `apply-auto-approve: ${{ inputs.target_environment_type == 'prod' && 'false' || 'true' }}`
                *   `secrets`: (e.g., `AZURE_CLIENT_ID: secrets.AZURE_CLIENT_ID`) - *Assumes secrets like `AZURE_CLIENT_ID` are defined with the same name in GitHub, but with different values scoped to each GitHub Environment ("Development", "Test", "Production").*
            4.  **Apply Database Migrations:**
                *   `if: steps.terraform_apply.outputs.status == 'success'`
                *   Uses: `./.github/workflows/reusable-database-migration-efcore.yml`
                *   `with`:
                    *   `efcore-project-path: 'src/MyProject.DataAccess/MyProject.DataAccess.csproj'`
                    *   `environment: ${{ inputs.target_environment_type }}`
                    *   `connection-string: ${{ secrets.DB_CONNECTION_STRING }}` (scoped per GitHub Environment)
                    *   `backup-required: ${{ inputs.target_environment_type == 'prod' && 'true' || 'false' }}`
            5.  **Deploy Application:**
                *   `if: steps.db_migration.outputs.status == 'success'`
                *   **Conditional Step for Production (Canary):**
                    *   `if: inputs.target_environment_type == 'prod'`
                    *   Uses: `./.github/workflows/reusable-canary-deployment.yml`
                    *   `id: app_deploy_prod_canary`
                    *   `with`: (parameters for canary, e.g., `canary-percentage`, `observation-period-minutes`, `health-check-url-pattern` from `vars`, `version` from `needs.prepare_deployment_info.outputs.version`)
                    *   `secrets`: (e.g., `AZURE_CREDENTIALS: secrets.AZURE_CREDENTIALS_APP_SERVICE`) (scoped per GitHub Environment)
                *   **Conditional Step for Dev/Test (Direct Deploy):**
                    *   `if: inputs.target_environment_type != 'prod'`
                    *   Uses: `./.github/workflows/reusable-deploy-environment.yml`
                    *   `id: app_deploy_non_prod`
                    *   `with`: (parameters for direct deploy, e.g., `azure-app-name` from `vars.AZURE_APP_NAME` (scoped per GitHub Environment), `version-being-deployed`)
                    *   `secrets`: (e.g., `AZURE_CREDENTIALS: secrets.AZURE_CREDENTIALS_APP_SERVICE`) (scoped per GitHub Environment)
    *   **`trigger_next_stage`:**
        *   Runs on: `ubuntu-latest`
        *   Needs: `[prepare_deployment_info, deploy_and_validate]`
        *   `if: success() && needs.deploy_and_validate.result == 'success'`
        *   Steps:
            *   **Promote DEV to TEST:**
                *   `if: inputs.target_environment_type == 'dev' && needs.prepare_deployment_info.outputs.is_main_pipeline == 'true'`
                *   Uses: `benc-uk/workflow-dispatch@v1`
                *   `with`:
                    *   `workflow: unified-cd-workflow.yml` (or ` ${{ github.workflow }}`)
                    *   `token: ${{ secrets.WORKFLOW_DISPATCH_PAT }}`
                    *   `inputs: |
                        {
                          "version_to_deploy": "${{ needs.prepare_deployment_info.outputs.version }}",
                          "source_artifact_name": "${{ needs.prepare_deployment_info.outputs.artifact_name }}",
                          "target_environment_type": "test",
                          "source_branch_is_main": "false"
                        }`
            *   **Promote TEST to PROD:**
                *   `if: inputs.target_environment_type == 'test'`
                *   Uses: `benc-uk/workflow-dispatch@v1`
                *   `with`:
                    *   `workflow: unified-cd-workflow.yml`
                    *   `token: ${{ secrets.WORKFLOW_DISPATCH_PAT }}`
                    *   `inputs: |
                        {
                          "version_to_deploy": "${{ needs.prepare_deployment_info.outputs.version }}",
                          "source_artifact_name": "${{ needs.prepare_deployment_info.outputs.artifact_name }}",
                          "target_environment_type": "prod",
                          "source_branch_is_main": "false"
                        }`
    *   **`report_cd_status`:**
        *   Runs on: `ubuntu-latest`
        *   Needs: `[prepare_deployment_info, deploy_and_validate]`
        *   `if: always()`
        *   Steps:
            *   Uses: `./.github/workflows/reusable-observability-hooks.yml`
            *   `with`:
                *   `status: ${{ needs.deploy_and_validate.result }}`
                *   `workflow-name: "${{ github.workflow }} - ${{ inputs.target_environment_type }}"`
                *   `environment-name: ${{ needs.prepare_deployment_info.outputs.github_environment_name }}`
                *   `version-deployed: ${{ needs.prepare_deployment_info.outputs.version }}`
                *   `message-details: "Deployment to ${{ inputs.target_environment_type }} status: ${{ needs.deploy_and_validate.result }}. ${{ inputs.target_environment_type == 'prod' && format('Canary outcome: {0}', needs.deploy_and_validate.outputs.canary_status || 'N/A') || '' }}"`
                *   `notification-channel: 'slack'`
            *   `secrets`: `SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}` (scoped per GitHub Environment)

**3. Key Changes & How Consistency is Addressed:**

*   **Single Orchestration Flow:** The `deploy_and_validate` job defines a consistent sequence: Infra -> DB Migration -> App Deployment.
*   **Reusable Workflows:** The actual work is done by the existing reusable workflows.
*   **Parameterization for Differences:** Secrets, variables, paths, and flags are derived from `inputs.target_environment_type` or scoped by GitHub Environments.

**4. Handling Inherent Differences (e.g., Test vs. Prod):**

*   **Deployment Strategy:** Conditional steps for Canary (Prod) vs. Direct (Dev/Test) deployments.
*   **Manual Approvals:** Enforced by GitHub Environment protection rules.
*   **Terraform `apply-auto-approve`:** `false` for production, `true` otherwise.
*   **Database `backup-required`:** `true` for production, `false` otherwise.

**5. Mermaid Diagram of the Unified Workflow:**

```mermaid
graph TD
    A[workflow_dispatch: version, artifact, target_env_type] --> B(prepare_deployment_info);
    B --> C{deploy_and_validate};
    C --> D[Checkout];
    D --> E[Download Artifact];
    E --> F[Apply Infrastructure (Terraform)];
    F --> G[Apply DB Migrations];
    G --> H{Target Env Type?};
    H -- prod --> I[Deploy App (Canary)];
    H -- dev/test --> J[Deploy App (Direct)];
    I --> K(End Deploy);
    J --> K;
    C --> L(report_cd_status);
    K --> M{Promotion?};
    M -- dev to test --> A_test(workflow_dispatch: target_env_type=test);
    M -- test to prod --> A_prod(workflow_dispatch: target_env_type=prod);
    M -- no / end --> N(End Workflow);
    L --> N;

    subgraph "Job: deploy_and_validate (targets GitHub Environment)"
        direction LR
        D
        E
        F
        G
        H
        I
        J
        K
    end

    style A fill:#D5F5E3,stroke:#333,stroke-width:2px
    style B fill:#EAF2F8,stroke:#333,stroke-width:2px
    style C fill:#E8DAEF,stroke:#333,stroke-width:2px
    style L fill:#FEF9E7,stroke:#333,stroke-width:2px
    style M fill:#FADBD8,stroke:#333,stroke-width:2px
```

**6. Benefits of Consolidation:**

*   **Improved Consistency:** Centralized orchestration logic.
*   **Reduced Duplication:** Common structures defined once.
*   **Simplified Maintenance:** Changes to the overall flow made in one place.

**7. Potential Drawbacks & Mitigations:**

*   **Increased File Complexity:** Unified file will be larger.
    *   **Mitigation:** Maximize reusable workflows; add clear comments.
*   **Risk of Broad Impact:** Errors could affect all environments.
    *   **Mitigation:** Thorough testing on non-critical branches/environments.
*   **Readability of Diffs:** Changes can be harder to review.
    *   **Mitigation:** Small, focused PRs.

**8. Next Steps:**
*   Review this plan.
*   If approved, switch to a "Code" mode to implement this `unified-cd-workflow.yml`.