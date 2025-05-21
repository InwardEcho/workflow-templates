# Phase 1: Pull Request Validation Workflow Design

This document outlines the detailed design for the Pull Request (PR) validation workflow (`pr-checks.yml`) and the initial set of reusable workflows it directly depends upon. The goal is to ensure code quality, security, and adherence to standards before any code is merged into the default branch.

## A. `pr-checks.yml` (Caller Workflow)

*   **Filename:** `.github/workflows/pr-checks.yml`
*   **Purpose:** To validate code changes upon pull request creation or update against the default branch (e.g., `main`). This workflow ensures that code meets quality and security standards before being considered for merge. It does *not* publish any packages or deploy.
*   **Trigger:**
    ```yaml
    on:
      pull_request:
        branches:
          - main # Or your organization's default branch name
        types: [opened, synchronize, reopened] # Triggers on PR creation, updates (new commits), and reopening
    ```
*   **Permissions (Top Level):**
    ```yaml
    permissions:
      contents: read      # To checkout code
      pull-requests: write # To post comments or update PR checks (if reusable workflows do this)
      actions: read        # To read workflow run information
      security-events: write # For CodeQL to upload results
    ```
*   **Concurrency:**
    ```yaml
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.sha }}
      cancel-in-progress: true
    ```
*   **Jobs:**

    1.  **`validate_pr`**
        *   `name: Validate Pull Request`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `build_test_status: ${{ steps.build_test.outputs.status }}`
            *   `security_scan_status: ${{ steps.security_scan.outputs.status }}`
            *   `sast_status: ${{ steps.sast.outputs.status }}`
        *   **Steps:**
            *   **Checkout Code:**
                ```yaml
                - name: Checkout repository
                  uses: actions/checkout@v4
                  with:
                    fetch-depth: 0 # Required for some tools or for accurate blame
                ```
            *   **Setup .NET SDK:**
                ```yaml
                - name: Setup .NET SDK
                  uses: actions/setup-dotnet@v4
                  with:
                    dotnet-version: |
                      6.0.x
                      7.0.x
                      8.0.x
                ```
            *   **Call Reusable Build & Test:**
                ```yaml
                - name: Build and Test
                  id: build_test
                  uses: ./.github/workflows/reusable-build-test-dotnet.yml
                  with:
                    solution-path: '**/*.sln'
                    build-configuration: 'Release'
                    dotnet-version-to-use: '8.0.x' # Example, can be made more dynamic
                    run-tests: true
                    test-filter: ''
                    artifact-name-prefix: 'pr-check'
                    package-application: false # No packaging for PR checks
                    upload-build-artifacts: false
                    upload-test-results-artifact: true # Keep test results for review
                ```
            *   **Call Reusable Security Scan (GitHub Native):**
                ```yaml
                - name: Run GitHub Security Checks
                  id: security_scan
                  uses: ./.github/workflows/reusable-security-github.yml
                  with:
                    enable-codeql: true
                    codeql-language: 'csharp'
                    fail-on-codeql-error: false
                    fail-on-codeql-severity: 'warning' # Example: fail PR on warnings or errors
                ```
            *   **Call Reusable Static Code Analysis (SAST):**
                ```yaml
                - name: Run Static Code Analysis
                  id: sast
                  uses: ./.github/workflows/reusable-static-code-analysis.yml
                  with:
                    solution-path: '**/*.sln'
                    fail-on-issues: true
                    # sonarqube-project-key: ${{ vars.SONAR_PROJECT_KEY_PREFIX }}-${{ github.event.repository.name }}
                    # sonarqube-host-url: ${{ vars.SONAR_HOST_URL }}
                  secrets:
                    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
                ```

    2.  **`report_pr_status`**
        *   `name: Report PR Check Status`
        *   `runs-on: ubuntu-latest`
        *   `needs: [validate_pr]`
        *   `if: always()` # Run even if previous jobs fail to report the failure
        *   **Steps:**
            *   **Call Reusable Observability Hook:**
                ```yaml
                - name: Notify PR Check Status
                  uses: ./.github/workflows/reusable-observability-hooks.yml
                  with:
                    status: ${{ needs.validate_pr.result }}
                    workflow-name: ${{ github.workflow }}
                    pr-number: ${{ github.event.pull_request.number }}
                    commit-sha: ${{ github.event.pull_request.head.sha }}
                    run-url: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
                    message-details: |
                      Build & Test: ${{ needs.validate_pr.outputs.build_test_status }}
                      Security Scan: ${{ needs.validate_pr.outputs.security_scan_status }}
                      SAST: ${{ needs.validate_pr.outputs.sast_status }}
                    notification-channel: 'github-pr-comment' # Example: post a comment
                  secrets:
                    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # Required for PR comments
                    # SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL_PR_CHECKS }}
                ```

---

## B. `reusable-build-test-dotnet.yml`

*   **Filename:** `.github/workflows/reusable-build-test-dotnet.yml`
*   **Purpose:** Compiles, tests, and optionally packages .NET applications.
*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `solution-path`: (string, required, default: `**/*.sln`) Path to the .sln file or .csproj file.
        *   `build-configuration`: (string, required, default: `Release`) Build configuration.
        *   `dotnet-version-to-use`: (string, optional) Specific .NET SDK version to use. Assumes SDK is set up by caller if not provided.
        *   `run-tests`: (boolean, optional, default: `true`) Whether to run tests.
        *   `test-project-path`: (string, optional, default: value of `solution-path`) Path to test projects.
        *   `test-filter`: (string, optional, default: `''`) Filter for `dotnet test`.
        *   `test-results-format`: (string, optional, default: `trx`) Format for test results.
        *   `test-results-directory`: (string, optional, default: `TestResults`) Directory for test results.
        *   `package-application`: (boolean, optional, default: `false`) Whether to package the application (`dotnet publish`).
        *   `publish-output-directory`: (string, optional, default: `./publish`) Output directory for `dotnet publish`.
        *   `artifact-name-prefix`: (string, required) Prefix for uploaded artifacts.
        *   `upload-build-artifacts`: (boolean, optional, default: `false`) Whether to upload build artifacts. (Typically true if `package-application` is true).
        *   `upload-test-results-artifact`: (boolean, optional, default: `true`) Whether to upload test results.
        *   `cache-nuget-packages`: (boolean, optional, default: `true`) Whether to cache NuGet packages.
    *   **Outputs:**
        *   `status`: (string) Overall status ('success' or 'failure').
        *   `build-artifact-name`: (string) Name of the uploaded build artifact.
        *   `test-results-artifact-name`: (string) Name of the uploaded test results artifact.
        *   `published-output-path`: (string) Path to the published application output.
    *   **Secrets:**
        *   `NUGET_FEED_AUTH_TOKEN`: (string, optional) Token for private NuGet feeds.
*   **Jobs:**
    *   **`build_and_test_job`**:
        *   `name: Build, Test, and Package`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `job_status: ${{ steps.set_status.outputs.status }}`
            *   `build_artifact_name_output: ${{ steps.upload_build_artifact.outputs.artifact-name }}`
            *   `test_results_artifact_name_output: ${{ steps.upload_test_results.outputs.artifact-name }}`
            *   `published_output_path_output: ${{ inputs.publish-output-directory }}`
        *   **Steps:**
            *   (Caller handles .NET SDK setup for now, can be added here if desired for full independence)
            *   Cache NuGet packages (if `inputs.cache-nuget-packages`).
            *   Restore NuGet packages (using `secrets.NUGET_FEED_AUTH_TOKEN` if provided).
            *   Build solution/project.
            *   Run tests (if `inputs.run-tests`).
            *   Publish application (if `inputs.package-application`).
            *   Upload Test Results Artifact (if `inputs.upload-test-results-artifact`), `id: upload_test_results`.
            *   Upload Build Artifact (if `inputs.upload-build-artifacts`), `id: upload_build_artifact`.
            *   `id: set_status` step to determine overall success/failure and set `job_status`.

---

## C. `reusable-security-github.yml`

*   **Filename:** `.github/workflows/reusable-security-github.yml`
*   **Purpose:** Orchestrates GitHub's native security features.
*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `enable-codeql`: (boolean, optional, default: `true`) Whether to run CodeQL.
        *   `codeql-language`: (string, optional, default: `csharp`) Languages for CodeQL.
        *   `codeql-config-file`: (string, optional) Path to custom CodeQL config.
        *   `codeql-query-suite`: (string, optional) Path to custom CodeQL query suite.
        *   `fail-on-codeql-error`: (boolean, optional, default: `false`) Fail if CodeQL tool errors.
        *   `fail-on-codeql-severity`: (string, optional, default: `''`) Fail on CodeQL findings of this severity or higher (e.g., 'error', 'warning').
    *   **Outputs:**
        *   `status`: (string) Status of scan execution.
        *   `codeql-results-url`: (string) URL to CodeQL results.
*   **Jobs:**
    *   **`security_scan_job`**:
        *   `name: GitHub Security Scans`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `job_status: ${{ steps.set_status.outputs.status }}`
            *   `codeql_url_output: # Logic to get this URL if possible`
        *   **Steps:**
            *   Checkout code.
            *   Initialize CodeQL (if `inputs.enable-codeql`).
            *   Autobuild (if needed by CodeQL).
            *   Perform CodeQL Analysis.
            *   `id: set_status` step to determine overall success/failure based on inputs and CodeQL results.

---

## D. `reusable-static-code-analysis.yml`

*   **Filename:** `.github/workflows/reusable-static-code-analysis.yml`
*   **Purpose:** Performs SAST using tools like SonarQube.
*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `solution-path`: (string, required) Path to .sln or project files.
        *   `fail-on-issues`: (boolean, optional, default: `true`) Fail if quality gate fails or issues exceed threshold.
        *   `sonarqube-project-key`: (string, optional) SonarQube project key.
        *   `sonarqube-host-url`: (string, optional) SonarQube server URL.
        *   `sonarqube-organization`: (string, optional) SonarQube organization.
        *   `dotnet-version-for-scanner`: (string, optional, default: `7.0.x`) .NET SDK for SonarScanner.
        *   `extra-scanner-args`: (string, optional) Additional scanner arguments.
    *   **Outputs:**
        *   `status`: (string) Status of SAST execution.
        *   `analysis-url`: (string) URL to analysis report.
    *   **Secrets:**
        *   `SONAR_TOKEN`: (string, optional) SonarQube token.
*   **Jobs:**
    *   **`sast_job`**:
        *   `name: Static Analysis`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `job_status: ${{ steps.set_status.outputs.status }}`
            *   `analysis_url_output: # URL from SonarQube if available`
        *   **Steps:**
            *   Checkout code (`fetch-depth: 0`).
            *   Setup .NET SDK.
            *   Setup SonarScanner for .NET.
            *   Run SonarScanner `begin` step.
            *   Build the project (important for SonarScanner .NET).
            *   Run SonarScanner `end` step.
            *   `id: set_status` step to determine overall success/failure based on quality gate and `inputs.fail-on-issues`.

---

## E. `reusable-observability-hooks.yml`

*   **Filename:** `.github/workflows/reusable-observability-hooks.yml`
*   **Purpose:** Sends notifications about workflow status.
*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `status`: (string, required) Status of the calling workflow/job.
        *   `workflow-name`: (string, required) Name of the calling workflow.
        *   `run-url`: (string, required) URL to the GitHub Actions run.
        *   `pr-number`: (string, optional) Pull request number.
        *   `commit-sha`: (string, optional) Commit SHA.
        *   `branch-name`: (string, optional) Branch name.
        *   `environment-name`: (string, optional) Environment name (for CD).
        *   `version-deployed`: (string, optional) Version deployed (for CD).
        *   `message-details`: (string, optional) Additional custom message.
        *   `notification-channel`: (string, required) Target channel (e.g., 'slack', 'teams', 'github-pr-comment').
        *   `slack-mention-users-on-failure`: (string, optional) Slack user IDs to mention on failure.
    *   **Outputs:**
        *   `notification_sent_status`: (string) 'success' or 'failure'.
    *   **Secrets:**
        *   `SLACK_WEBHOOK_URL`: (string, optional)
        *   `TEAMS_WEBHOOK_URL`: (string, optional)
        *   `GITHUB_TOKEN`: (string, optional) Required for 'github-pr-comment'.
*   **Jobs:**
    *   **`send_notification_job`**:
        *   `name: Send Notification`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `job_status: ${{ steps.set_status.outputs.status }}`
        *   **Steps:**
            *   Construct message.
            *   Conditional steps for each `inputs.notification-channel`.
            *   `id: set_status` step to set `job_status`.
