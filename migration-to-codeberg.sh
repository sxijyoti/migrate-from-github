#!/bin/bash
#
# GitHub to Codeberg Migration Script
#

# -------------------------------------------------------------------
# USER CONFIGURATION
# -------------------------------------------------------------------
# PLEASE CHANGE TO THE RESPECTIVE VALUES
# GitHub username + token
GITHUB_USERNAME="lmao"
GITHUB_TOKEN="lol"

# Codeberg username and personal access token
CODEBERG_USERNAME="lmao"
CODEBERG_TOKEN="lol"

# Leave empty to migrate ALL repos
REPOSITORIES=(
#   "repo1"
#   "repo2"
)

# Only migrate repos owned by these users
OWNERS=(
    "lmfao"
    "another owner"
)

# Optional description prefix
DESCRIPTION_PREFIX=""

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------

array_contains() {
    local array="$1[@]"
    local seeking=$2

    for element in "${!array}"; do
        [[ "$element" == "$seeking" ]] && return 0
    done

    return 1
}

# -------------------------------------------------------------------
# START
# -------------------------------------------------------------------

printf "\n----------------------------------------------"
printf "\n GitHub → Codeberg Migration Script"
printf "\n----------------------------------------------\n"

printf "\n GitHub User   : %s" "$GITHUB_USERNAME"
printf "\n Codeberg User : %s" "$CODEBERG_USERNAME"

if [ ${#OWNERS[@]} -eq 0 ]; then
    printf "\n Owners         : all"
else
    printf "\n Owners         : %s" "${OWNERS[*]}"
fi

if [ ${#REPOSITORIES[@]} -eq 0 ]; then
    printf "\n Repositories   : all"
else
    printf "\n Repositories   : %s" "${REPOSITORIES[*]}"
fi

printf "\n\nPress ENTER to continue or CTRL+C to abort...\n"
read

printf "\n>>> Starting migration...\n\n"

# -------------------------------------------------------------------
# PAGINATION
# -------------------------------------------------------------------

GITHUB_PAGINATION=100
MAX_PAGES=20

# -------------------------------------------------------------------
# FETCH REPOSITORIES
# -------------------------------------------------------------------

for ((page=1; page<=MAX_PAGES; page++)); do

    repos=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user/repos?per_page=${GITHUB_PAGINATION}&page=${page}")

    # Stop if empty
    if [ "$(echo "$repos" | jq length)" -eq 0 ]; then
        break
    fi

    echo "$repos" | jq -c '.[]' | while read -r row; do

        repo_name=$(echo "$row" | jq -r '.name')
        repo_owner=$(echo "$row" | jq -r '.owner.login')

        # Filter repository list
        if ! array_contains REPOSITORIES "$repo_name" && [ ${#REPOSITORIES[@]} -ne 0 ]; then
            continue
        fi

        # Filter owners
        if ! array_contains OWNERS "$repo_owner" && [ ${#OWNERS[@]} -ne 0 ]; then
            continue
        fi

        repo_clone_url=$(echo "$row" | jq -r '.clone_url')
        repo_description="$DESCRIPTION_PREFIX$(echo "$row" | jq -r '.description // ""')"
        repo_is_private=$(echo "$row" | jq -r '.private')

        printf ">>> Migrating: %s (%s)\n" \
            "$repo_name" \
            "$([ "$repo_is_private" = "true" ] && echo "private" || echo "public")"

        json_payload=$(jq -n \
            --arg auth_username "$GITHUB_USERNAME" \
            --arg auth_token "$GITHUB_TOKEN" \
            --arg clone_addr "$repo_clone_url" \
            --argjson private "$repo_is_private" \
            --arg repo_name "$repo_name" \
            --arg repo_owner "$CODEBERG_USERNAME" \
            --arg description "$repo_description" \
            '{
                auth_username: $auth_username,
                auth_token: $auth_token,
                clone_addr: $clone_addr,
                private: $private,
                repo_name: $repo_name,
                repo_owner: $repo_owner,
                service: "github",
                description: $description
            }')

        response=$(curl \
            --retry 3 \
            --retry-delay 5 \
            -s \
            -w "\n%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $CODEBERG_TOKEN" \
            -d "$json_payload" \
            "https://codeberg.org/api/v1/repos/migrate")

        # macOS-compatible parsing
        response_body=$(echo "$response" | sed '$d')
        http_status=$(echo "$response" | tail -n 1)

        case $http_status in

            201)
                printf "    Success!\n\n"
                ;;

            409)
                printf "    Already exists on Codeberg.\n\n"
                ;;

            403)
                printf "    Forbidden (check token permissions).\n\n"
                ;;

            504)
                printf "    Timeout from Codeberg (repo may still import).\n\n"
                ;;

            *)
                error_message=$(echo "$response_body" | jq -r '.message // empty' 2>/dev/null)

                if [ -n "$error_message" ]; then
                    printf "    Error: %s (HTTP %s)\n\n" \
                        "$error_message" \
                        "$http_status"
                else
                    printf "    Unknown error (HTTP %s)\n\n" \
                        "$http_status"
                fi
                ;;
        esac

    done

done

echo ">>> Migration completed!"
