#!/usr/bin/env bash
# Git repository fixtures for testing git-hex

set -euo pipefail

# Helper to configure a test repo with signing disabled
_configure_test_repo() {
	git config user.email "test@example.com"
	git config user.name "Test User"
	# Disable commit signing (avoids 1Password/GPG agent issues in CI/tests)
	git config commit.gpgsign false
	git config tag.gpgsign false
}

# Create a basic git repo with N commits
create_test_repo() {
	local repo_dir="$1"
	local num_commits="${2:-5}"
	
	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo
		
		for i in $(seq 1 "${num_commits}"); do
			echo "Content ${i}" > "file${i}.txt"
			git add "file${i}.txt"
			# Fixed dates for reproducibility
			GIT_COMMITTER_DATE="2024-01-0${i}T12:00:00" \
			GIT_AUTHOR_DATE="2024-01-0${i}T12:00:00" \
			git commit -m "Commit ${i}"
		done
	)
}

# Create a repo with fixup commits ready for autosquash
create_fixup_scenario() {
	local repo_dir="$1"
	
	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo
		
		echo "base" > base.txt
		git add base.txt && git commit -m "Initial commit"
		
		echo "feature" > feature.txt
		git add feature.txt && git commit -m "Add feature"
		
		echo "feature fixed" > feature.txt
		git add feature.txt && git commit -m "fixup! Add feature"
		
		echo "another" > another.txt
		git add another.txt && git commit -m "Add another file"
	)
}

# Create a repo with merge conflicts waiting to happen
# This creates a scenario where rebasing will definitely conflict
create_conflict_scenario() {
	local repo_dir="$1"
	
	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo
		
		# Base commit
		echo "original content" > conflict.txt
		git add conflict.txt && git commit -m "Initial"
		
		# Create a branch with one change
		git checkout -b feature
		echo "feature branch change" > conflict.txt
		git add conflict.txt && git commit -m "Feature change"
		
		# Go back to main and make a conflicting change
		git checkout main
		echo "main branch change" > conflict.txt
		git add conflict.txt && git commit -m "Main change"
		
		# Switch to feature - rebasing onto main will conflict
		git checkout feature
	)
}

# Create a repo with staged changes ready for fixup/amend
create_staged_changes_repo() {
	local repo_dir="$1"
	
	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo
		
		echo "initial" > file.txt
		git add file.txt && git commit -m "Initial commit"
		
		echo "modified" > file.txt
		git add file.txt
		# Leave changes staged but not committed
	)
}

# Create a repo with a feature branch
create_branch_scenario() {
	local repo_dir="$1"
	
	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo
		
		echo "base" > base.txt
		git add base.txt && git commit -m "Base commit"
		
		git checkout -b feature
		echo "feature1" > feature1.txt
		git add feature1.txt && git commit -m "Feature commit 1"
		
		echo "feature2" > feature2.txt
		git add feature2.txt && git commit -m "Feature commit 2"
		
		git checkout main
		echo "main update" > main.txt
		git add main.txt && git commit -m "Main branch update"
		
		git checkout feature
	)
}
