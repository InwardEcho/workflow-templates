# Phase 2: Unified CI Workflow Design

This document outlines the detailed design for the `ci-unified.yml` caller workflow and the refined reusable workflows it critically depends on: `reusable-versioning.yml` and `reusable-publish-nuget.yml`. This phase focuses on creating a hybrid CI process that handles different branch strategies for versioning, packaging, and initiating deployment.

## A. `ci-unified.yml` (Caller Workflow)

*   **Filename:** `.github/workflows/ci-unified.yml`
*   **Purpose:** Triggered on pushes to specified branches, this workflow performs common CI tasks (versioning, build, test) and then executes branch-specific logic for packaging (pre-release vs. release) and initiating the `cd-dev-environment.yml` workflow.
*   **Trigger:**
    ```yaml
    on:
      push:
        branches:
          - main # Default branch
          - 'feature/**'
          - 'bugfix/**'
          - 'hotfix/**'
        # tags-ignore:
        #   - 'v*' # Optional: ignore version tags if they have a separate release process
    ```
*   **Permissions (Top Level):**
    ```yaml
    permissions:
      contents: read
      actions: write # To trigger cd-dev-environment.yml via workflow_dispatch
    ```
*   **Concurrency:**
    ```yaml
    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress: true
    ```
*   **Environment Variables (Workflow Level):**
    ```yaml
    env:
      DOTNET_SKIP_FIRST_TIME_EXPERIENCE: true
      DOTNET_CLI_TELEMETRY_OPTOUT: true
    ```
*   **Jobs:**

    1.  **`initialize_ci`**
        *   `name: Initialize CI & Determine Variables`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `is_main_branch: ${{ steps.determine_branch.outputs.is_main }}`
            *   `versioning_strategy: ${{ steps.determine_branch.outputs.version_strategy }}`
            *   `version_prerelease_suffix: ${{ steps.determine_branch.outputs.prerelease_suffix }}`
            *   `nuget_publish_feed_type: ${{ steps.determine_branch.outputs.nuget_feed_type }}`
            *   `build_artifact_prefix: ${{ steps.determine_branch.outputs.artifact_prefix }}`
        *   **Steps:**
            *   **Checkout Code:**
                ```yaml
                - name: Checkout repository
                  uses: actions/checkout@v4
                  with:
                    fetch-depth: 0
                ```
            *   **Determine Branch Type & CI Variables:**
                ```yaml
                - name: Determine Branch Type and CI Variables
                  id: determine_branch
                  shell: bash
                  run: |
                    IS_MAIN="false"
                    VERSION_STRATEGY="gitversion"
                    PRERELEASE_SUFFIX=""
                    NUGET_FEED_TYPE="prerelease"
                    ARTIFACT_PREFIX="feature"

                    REF_NAME="${{ github.ref_name }}"

                    if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
                      IS_MAIN="true"
                      NUGET_FEED_TYPE="release"
                      ARTIFACT_PREFIX="release"
                    elif [[ "$REF_NAME" == hotfix/* ]]; then
                      PRERELEASE_SUFFIX=$(echo "$REF_NAME" | sed 's|hotfix/||' | sed 's/[^a-zA-Z0-9.-]/-/g')
                      ARTIFACT_PREFIX="hotfix"
                    else # feature, bugfix branches
                      PRERELEASE_SUFFIX=$(echo "$REF_NAME" | sed 's|feature/||' | sed 's|bugfix/||' | sed 's/[^a-zA-Z0-9.-]/-/g')
                      if [[ -z "$PRERELEASE_SUFFIX" ]]; then
                        PRERELEASE_SUFFIX="dev"
                      fi
                    fi
                    # Further sanitize suffix
                    PRERELEASE_SUFFIX=$(echo "$PRERELEASE_SUFFIX" | sed 's/--*/-/g' | sed 's/^-//g' | sed 's/-$//g')

                    echo "is_main=$IS_MAIN" >> $GITHUB_OUTPUT
                    echo "version_strategy=$VERSION_STRATEGY" >> $GITHUB_OUTPUT
                    echo "prerelease_suffix=$PRERELEASE_SUFFIX" >> $GITHUB_OUTPUT
                    echo "nuget_feed_type=$NUGET_FEED_TYPE" >> $GITHUB_OUTPUT
                    echo "artifact_prefix=$ARTIFACT_PREFIX" >> $GITHUB_OUTPUT
                ```

    2.  **`version_and_build`**
        *   `name: Version, Build & Test`
        *   `runs-on: ubuntu-latest`
        *   `needs: initialize_ci`
        *   `outputs:`
            *   `calculated_version: ${{ steps.version.outputs.calculated-version }}`
            *   `build_test_status: ${{ steps.build_test.outputs.status }}`
            *   `build_artifact_name: ${{ steps.build_test.outputs.build-artifact-name }}`
            *   `test_results_artifact_name: ${{ steps.build_test.outputs.test-results-artifact-name }}`
            *   `published_output_path: ${{ steps.build_test.outputs.published-output-path }}`
        *   **Steps:**
            *   **Setup .NET SDK:** (As in `pr-checks.yml` from Phase 1 Design)
                ```yaml
                - name: Setup .NET SDK
                  uses: actions/setup-dotnet@v4
                  with:
                    dotnet-version: |
                      6.0.x
                      7.0.x
                      8.0.x
                ```
            *   **Call Reusable Versioning:**
                ```yaml
                - name: Calculate Version
                  id: version
                  uses: ./.github/workflows/reusable-versioning.yml
                  with:
                    strategy: ${{ needs.initialize_ci.outputs.versioning_strategy }}
                    prerelease-suffix-override: ${{ needs.initialize_ci.outputs.version_prerelease_suffix }}
                    fetch-depth: 0
                ```
            *   **Call Reusable Build & Test:**
                ```yaml
                - name: Build, Test, and Package Application
                  id: build_test
                  uses: ./.github/workflows/reusable-build-test-dotnet.yml
                  with:
                    solution-path: '**/*.sln'
                    build-configuration: 'Release'
                    dotnet-version-to-use: '8.0.x' # Or from matrix/input
                    run-tests: true
                    package-application: true
                    publish-output-directory: './app-publish'
                    artifact-name-prefix: ${{ needs.initialize_ci.outputs.build_artifact_prefix }}-${{ steps.version.outputs.calculated-version }}
                    upload-build-artifacts: true
                    upload-test-results-artifact: true
                ```

    3.  **`publish_package`**
        *   `name: Publish NuGet Package`
        *   `runs-on: ubuntu-latest`
        *   `needs: [initialize_ci, version_and_build]`
        *   `if: needs.version_and_build.outputs.build_test_status == 'success' && needs.version_and_build.outputs.calculated_version != ''`
        *   `outputs:`
            *   `nuget_publish_status: ${{ steps.publish_nuget.outputs.status }}`
        *   **Steps:**
            *   **Download Build Artifact:**
                ```yaml
                - name: Download Published Application Artifact
                  uses: actions/download-artifact@v4
                  with:
                    name: ${{ needs.version_and_build.outputs.build_artifact_name }}
                    path: ${{ needs.version_and_build.outputs.published_output_path }}
                ```
            *   **Call Reusable Publish NuGet:**
                ```yaml
                - name: Publish NuGet Package
                  id: publish_nuget
                  uses: ./.github/workflows/reusable-publish-nuget.yml
                  with:
                    package-path: '${{ needs.version_and_build.outputs.published_output_path }}/**/*.nupkg'
                    version: ${{ needs.version_and_build.outputs.calculated_version }}
                    nuget-feed-url: ${{ vars.NUGET_FEED_URL_BASE }}/${{ needs.initialize_ci.outputs.nuget_publish_feed_type }} # e.g., https://nuget.pkg.github.com/OWNER/index.json or specific for release/prerelease
                    is-prerelease: ${{ needs.initialize_ci.outputs.is_main_branch == 'false' }}
                  secrets:
                    NUGET_API_KEY: ${{ secrets.GH_PACKAGES_TOKEN }} # Or specific PAT/API Key
                ```

    4.  **`trigger_dev_deployment`**
        *   `name: Trigger DEV Deployment`
        *   `runs-on: ubuntu-latest`
        *   `needs: [initialize_ci, version_and_build, publish_package]`
        *   `if: needs.version_and_build.outputs.build_test_status == 'success'`
        *   **Steps:**
            *   **Dispatch `cd-dev-environment.yml`:**
                ```yaml
                - name: Dispatch DEV Deployment Workflow
                  uses: benc-uk/workflow-dispatch@v1
                  with:
                    workflow: cd-dev-environment.yml
                    token: ${{ secrets.WORKFLOW_DISPATCH_PAT }} # PAT with workflow write scope
                    inputs: '{
                      "version_to_deploy": "${{ needs.version_and_build.outputs.calculated_version }}",
                      "source_artifact_name": "${{ needs.version_and_build.outputs.build_artifact_name }}",
                      "source_branch_is_main": "${{ needs.initialize_ci.outputs.is_main_branch }}"
                    }'
                    ref: ${{ github.ref }}
                ```

    5.  **`report_ci_status`**
        *   `name: Report CI Status`
        *   `runs-on: ubuntu-latest`
        *   `needs: [initialize_ci, version_and_build, publish_package, trigger_dev_deployment]`
        *   `if: always()`
        *   **Steps:**
            *   **Call Reusable Observability Hook:**
                ```yaml
                - name: Notify CI Status
                  uses: ./.github/workflows/reusable-observability-hooks.yml
                  with:
                    status: ${{ (needs.version_and_build.outputs.build_test_status == 'success' && (needs.publish_package.result == 'success' || needs.publish_package.result == 'skipped' || needs.publish_package.result == '') && needs.trigger_dev_deployment.result == 'success') ? 'success' : 'failure' }}
                    workflow-name: ${{ github.workflow }}
                    branch-name: ${{ github.ref_name }}
                    commit-sha: ${{ github.sha }}
                    run-url: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
                    message-details: |
                      Version: ${{ needs.version_and_build.outputs.calculated_version }}
                      Build & Test: ${{ needs.version_and_build.outputs.build_test_status }}
                      NuGet Publish: ${{ needs.publish_package.outputs.nuget_publish_status || 'skipped' }}
                      DEV Dispatch: ${{ needs.trigger_dev_deployment.result }}
                    notification-channel: 'slack' # Or your preferred channel
                  secrets:
                    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL_CI }}
                ```

---

## B. `reusable-versioning.yml` (Refined)

*   **Filename:** `.github/workflows/reusable-versioning.yml`
*   **Purpose:** Calculates application versions based on different strategies, supporting pre-release suffixes.
*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `strategy`: (string, required, default: `gitversion`) Versioning strategy ('gitversion', 'tag_based', 'run_number_semantic').
        *   `prerelease-suffix-override`: (string, optional) Specific suffix for pre-releases. If strategy is 'gitversion', this might be appended or used to influence GitVersion's output if GitVersion itself doesn't produce the desired suffix.
        *   `gitversion-config-file`: (string, optional, default: `GitVersion.yml`) Path to GitVersion.yml.
        *   `fetch-depth`: (integer, optional, default: `0`) Fetch depth for checkout.
        *   `default-version`: (string, optional, default: `0.1.0-alpha`) Default version for some strategies.
        *   `github-ref`: (string, required) The `github.ref` from the caller, used to infer branch type if needed.
    *   **Outputs:**
        *   `calculated-version`: (string) Full calculated version string.
        *   `major`: (string)
        *   `minor`: (string)
        *   `patch`: (string)
        *   `prerelease-tag`: (string)
        *   `build-metadata`: (string) (e.g., commit SHA short)
        *   `is-prerelease`: (boolean)
*   **Jobs:**
    *   **`calculate_version_job`**:
        *   `name: Calculate Version`
        *   `runs-on: ubuntu-latest`
        *   `outputs:` (Map all internal step outputs to job outputs)
        *   **Steps:**
            *   Checkout code (if not already done by caller, using `inputs.fetch-depth`).
            *   **If `inputs.strategy == 'gitversion'`:**
                *   Setup GitVersion tool.
                *   Run GitVersion (using `inputs.gitversion-config-file`).
                *   Parse GitVersion JSON output (`MajorMinorPatch`, `PreReleaseTag`, `CommitsSinceVersionSourcePadded`, `Sha`, etc.).
                *   Construct `calculated-version`. If `inputs.prerelease-suffix-override` is set and GitVersion's PreReleaseTag is empty (for a main branch release build), this override should NOT apply. If GitVersion's PreReleaseTag is present, the override might be appended or used contextually.
                *   Set `is-prerelease` based on GitVersion's `PreReleaseTag`.
            *   **(Other strategies like `tag_based`, `run_number_semantic` would have their logic here)**
            *   Set all version part outputs.

---

## C. `reusable-publish-nuget.yml` (Refined)

*   **Filename:** `.github/workflows/reusable-publish-nuget.yml`
*   **Purpose:** Publishes NuGet packages.
*   **`on: workflow_call:`**
    *   **Inputs:**
        *   `package-path`: (string, required) Glob pattern for `.nupkg` files.
        *   `version`: (string, required) Package version.
        *   `nuget-feed-url`: (string, required) NuGet feed URL.
        *   `is-prerelease`: (boolean, optional, default: `false`) Hint for feed behavior or if different feeds are used.
        *   `dotnet-version-to-use`: (string, optional, default: `8.0.x`) .NET SDK for `dotnet nuget push`.
        *   `skip-duplicate`: (boolean, optional, default: `true`) Skip if package version exists.
    *   **Outputs:**
        *   `status`: (string) 'success', 'failure', or 'skipped'.
        *   `published-packages`: (string) JSON array of published package names/versions.
    *   **Secrets:**
        *   `NUGET_API_KEY`: (string, required) API key for the NuGet feed.
*   **Jobs:**
    *   **`publish_nuget_job`**:
        *   `name: Publish NuGet Package(s)`
        *   `runs-on: ubuntu-latest`
        *   `outputs:`
            *   `job_status: ${{ steps.set_status.outputs.status }}`
            *   `job_published_packages: ${{ steps.do_publish.outputs.published_list }}`
        *   **Steps:**
            *   Setup .NET SDK.
            *   `id: do_publish` step to find and loop through .nupkg files, running `dotnet nuget push` for each. Collect names of successfully pushed packages.
            *   `id: set_status` step to determine overall success/failure/skipped.