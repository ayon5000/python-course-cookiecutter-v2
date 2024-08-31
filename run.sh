#!/bin/bash

set -e

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# install core and development Python dependencies into the currently activated venv
function install {
    python -m pip install --upgrade pip
    python -m pip install cookiecutter pytest pytest-cov pre-commit
}

# run linting, formatting, and other static code quality tools
function lint {
    pre-commit run --all-files
}

function lint:ci {
    # We skip no-commit-to-branch since that blocks commits to `main`.
    # All merged PRs are commits to `main` so this must be disabled.
    SKIP=no-commit-to-branch pre-commit run --all-files
}

function run-tests {
    python -m pytest ${@:-"$THIS_DIR/tests/"}
}


function generate-project {
    cookiecutter ./ \
    --output-dir "$THIS_DIR/sample"

    cd "$THIS_DIR/sample"
    cd $(ls)
    git init
    git add --all
    git branch -M main
    git commit -m "feat: generate sample project with python-course-cookiecutter-v2"
}

# remove all files generated by tests, builds, or operating this codebase
function clean {
    rm -rf dist build coverage.xml test-reports sample
    find . \
      -type d \
      \( \
        -name "*cache*" \
        -o -name "*.dist-info" \
        -o -name "*.egg-info" \
        -o -name "*htmlcov" \
      \) \
      -not -path "*env/*" \
      -exec rm -r {} + || true

    find . \
      -type f \
      -name "*.pyc" \
      -not -path "*env/*" \
      -exec rm {} +
}

# export the contents of .env as environment variables
function try-load-dotenv {
    if [ ! -f "$THIS_DIR/.env" ]; then
        echo "no .env file found"
        return 1
    fi

    while read -r line; do
        export "$line"
    done < <(grep -v '^#' "$THIS_DIR/.env" | grep -v '^$')
}


function execute-tests {
    pytest ./tests
}

# args:
#    REPO_NAME - name of the repository
#    GITHUB_USERNAME - name of my github user, e.g. phitoduck
function push-initial-readme-to-repo {
    rm -rf "$REPO_NAME"
    gh repo clone "$GITHUB_USERNAME/$REPO_NAME"
    cd "$REPO_NAME"
    echo "# $REPO_NAME" > "README.md"
    git branch -M main || true
    git add --all
    git commit -m "feat: created repository"
    if [[ -n "$GH_TOKEN" ]]; then
        git remote set-url origin "https://$GITHUB_USERNAME:$GH_TOKEN@github.com/$GITHUB_USERNAME/$REPO_NAME"
    fi
    git push origin main
}

# args:
#    REPO_NAME - name of the repository
#    GITHUB_USERNAME - name of my github user, e.g. phitoduck
#    IS_PUBLIC_REPO - if true, the repository will be public, otherwise private
function create-repo-if-not-exists {
    local IS_PUBLIC_REPO=${IS_PUBLIC_REPO:-false}

    # check to see if the repository exists; if it does, return
    echo "Checking to see if $GITHUB_USERNAME/$REPO_NAME exists..."
    gh repo view "$GITHUB_USERNAME/$REPO_NAME" > /dev/null \
        && echo "Repo exists" \
        && exit 0

    # otherwise we'll create the repository
    if [[ "$IS_PUBLIC_REPO" == "true" ]]; then
        PUBLIC_OR_PRIVATE="public"
    else
        PUBLIC_OR_PRIVATE="private"
    fi

    echo "Repository does not exist, creating..."
    gh repo create "$GITHUB_USERNAME/$REPO_NAME" "--$PUBLIC_OR_PRIVATE"

    push-initial-readme-to-repo
}

# args:
#    TEST_PYPI_TOKEN, PROD_PYPI_TOKEN - auth token for test and prod PyPI
#    REPO_NAME - name of the repository
#    GITHUB_USERNAME - name of my github user, e.g. phitoduck
function configure-repo {
    # configure github actions secrets
    gh secret set TEST_PYPI_TOKEN \
        --body "$TEST_PYPI_TOKEN" \
        --repo "$GITHUB_USERNAME/$REPO_NAME"
    gh secret set PROD_PYPI_TOKEN \
        --body "$PROD_PYPI_TOKEN" \
        --repo "$GITHUB_USERNAME/$REPO_NAME"

    # protect main branch, enforcing passing build on feature branch before merge
    BRANCH_NAME="main"
    gh api -X PUT "repos/$GITHUB_USERNAME/$REPO_NAME/branches/$BRANCH_NAME/protection" \
        -H "Accept: application/vnd.github+json" \
        -F "required_status_checks[strict]=true" \
        -F "required_status_checks[checks][][context]=check-version-txt" \
        -F "required_status_checks[checks][][context]=lint-format-and-static-code-checks" \
        -F "required_status_checks[checks][][context]=build-wheel-and-sdist" \
        -F "required_status_checks[checks][][context]=execute-tests" \
        -F "required_pull_request_reviews[required_approving_review_count]=0" \
        -F "enforce_admins=null" \
        -F "restrictions=null" > /dev/null
}

# args:
#    REPO_NAME - name of the repository
#    GITHUB_USERNAME - name of my github user, e.g. phitoduck
#    PACKAGE_IMPORT_NAME - e.g. if "exapmle_pkg" then "import example_pkg"
function open-pr-with-generated-project {
    rm -rf "$REPO_NAME" ./outdir
    install

    # clone the repository
    gh repo clone "$GITHUB_USERNAME/$REPO_NAME"

    # delete repository contents
    mv "$REPO_NAME/.git" "./$REPO_NAME.git.bak"
    rm -rf "$REPO_NAME"
    mkdir "$REPO_NAME"
    mv "./$REPO_NAME.git.bak" "$REPO_NAME/.git"

    # generate the project into the repository folder
    OUTDIR="./outdir/"
    CONFIG_FILE_PATH="./$REPO_NAME.config.yaml"
    cat <<EOF > "$CONFIG_FILE_PATH"
default_context:
    repo_name: $REPO_NAME
    package_import_name: $PACKAGE_IMPORT_NAME
EOF

    cookiecutter ./ \
        --output-dir "$OUTDIR" \
        --no-input \
        --config-file $CONFIG_FILE_PATH
    rm $CONFIG_FILE_PATH

    # stage the generated files on a new feature branch
    mv "$REPO_NAME/.git" "$OUTDIR/$REPO_NAME/"
    cd "$OUTDIR/$REPO_NAME"

    UUID=$(cat /proc/sys/kernel/random/uuid)
    UNIQUE_BRANCH_NAME=populate-from-template-${UUID:0:6}

    git checkout -b "$UNIQUE_BRANCH_NAME"
    git add --all

    # apply formatting and linting autofixes to the generated files
    lint:ci || true

    # re-stage the files modified by pre-commit
    git add --all

    # commit the changes and push them to the remote feature branch
    git commit -m 'feat!: populated from `python-course-cookiecutter-v2` template'

    # if GH_TOKEN is set, set the remote url to it
    if [[ -n "$GH_TOKEN" ]]; then
        git remote set-url origin "https://$GITHUB_USERNAME:$GH_TOKEN@github.com/phitoduck/$REPO_NAME"
    fi
    git push origin "$UNIQUE_BRANCH_NAME"

    # open a PR from the feature branch into main
    gh pr create \
        --title "feat: populated from \`python-course-cookiecutter-v2\` template" \
        --body "This PR was generated by \`python-course-cookiecutter-v2\`" \
        --base main \
        --head "$UNIQUE_BRANCH_NAME" \
        --repo "$GITHUB_USERNAME/$REPO_NAME"
}

function create-sample-repo {
    git add .github/ run.sh \
    && git commit -m "fix: debugging the create-or-update-repo.yaml workflow" \
    && git push origin main || true

    gh workflow run .github/workflows/create-or-update-repo.yaml \
        -f repo_name=generated-repo-$REPO_NUMBER \
        -f package_import_name=generated_repo_$REPO_NUMBER \
        -f is_public_repo=false \
        --ref main
}


# print all functions in this file
function help {
    echo "$0 <task> <args>"
    echo "Tasks:"
    compgen -A function | cat -n
}

TIMEFORMAT="Task completed in %3lR"
time ${@:-help}
