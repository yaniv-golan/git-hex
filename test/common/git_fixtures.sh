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
			echo "Content ${i}" >"file${i}.txt"
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

		echo "base" >base.txt
		git add base.txt && git commit -m "Initial commit"

		echo "feature" >feature.txt
		git add feature.txt && git commit -m "Add feature"

		echo "feature fixed" >feature.txt
		git add feature.txt && git commit -m "fixup! Add feature"

		echo "another" >another.txt
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
		echo "original content" >conflict.txt
		git add conflict.txt && git commit -m "Initial"

		# Create a branch with one change
		git checkout -b feature
		echo "feature branch change" >conflict.txt
		git add conflict.txt && git commit -m "Feature change"

		# Go back to main and make a conflicting change
		git checkout main
		echo "main branch change" >conflict.txt
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

		echo "initial" >file.txt
		git add file.txt && git commit -m "Initial commit"

		echo "modified" >file.txt
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

		echo "base" >base.txt
		git add base.txt && git commit -m "Base commit"

		git checkout -b feature
		echo "feature1" >feature1.txt
		git add feature1.txt && git commit -m "Feature commit 1"

		echo "feature2" >feature2.txt
		git add feature2.txt && git commit -m "Feature commit 2"

		git checkout main
		echo "main update" >main.txt
		git add main.txt && git commit -m "Main branch update"

		git checkout feature
	)
}

# Create repo with binary file conflict
create_binary_conflict_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		# Create a binary file (PNG header bytes)
		printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' >image.png
		git add image.png && git commit -m "Initial binary"

		git checkout -b feature
		printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10' >image.png
		git add image.png && git commit -m "Feature binary change"

		git checkout main
		printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x20' >image.png
		git add image.png && git commit -m "Main binary change"

		git checkout feature
	)
}

# Create repo with binary delete/modify conflict (working tree missing file)
create_binary_delete_conflict_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' >image.png
		git add image.png && git commit -m "Initial binary"

		git checkout -b feature
		git rm image.png && git commit -m "Delete binary"

		git checkout main
		printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10' >image.png
		git add image.png && git commit -m "Modify binary main"

		git checkout feature
		# Rebasing feature onto main will create delete/modify conflict with no working-copy file
	)
}

# Create repo with delete-by-us conflict (we deleted, they modified)
create_delete_by_us_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >file.txt
		git add file.txt && git commit -m "Initial"

		git checkout -b feature
		git rm file.txt && git commit -m "Delete file"

		git checkout main
		echo "modified by main" >file.txt
		git add file.txt && git commit -m "Modify file"

		git checkout feature
		# Now rebasing feature onto main will conflict: we deleted, they modified
	)
}

# Create repo with delete-by-them conflict (they deleted, we modified)
create_delete_by_them_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >file.txt
		git add file.txt && git commit -m "Initial"

		git checkout -b feature
		echo "modified by feature" >file.txt
		git add file.txt && git commit -m "Modify file"

		git checkout main
		git rm file.txt && git commit -m "Delete file"

		git checkout feature
		# Now rebasing feature onto main will conflict: they deleted, we modified
	)
}

# Create repo with add/add conflict (both added same filename)
create_add_add_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "base" >base.txt
		git add base.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature version" >newfile.txt
		git add newfile.txt && git commit -m "Add newfile (feature)"

		git checkout main
		echo "main version" >newfile.txt
		git add newfile.txt && git commit -m "Add newfile (main)"

		git checkout feature
		# Both branches added newfile.txt with different content
	)
}

# Create repo with file containing spaces in path
create_spaces_in_path_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		mkdir -p "path with spaces"
		echo "original" >"path with spaces/my file.txt"
		git add . && git commit -m "Initial"

		git checkout -b feature
		echo "feature change" >"path with spaces/my file.txt"
		git add . && git commit -m "Feature change"

		git checkout main
		echo "main change" >"path with spaces/my file.txt"
		git add . && git commit -m "Main change"

		git checkout feature
	)
}

# Create repo with empty file
create_empty_file_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		touch empty.txt
		git add empty.txt && git commit -m "Initial empty file"

		git checkout -b feature
		echo "now has content" >empty.txt
		git add empty.txt && git commit -m "Add content"

		git checkout main
		echo "main added content" >empty.txt
		git add empty.txt && git commit -m "Main add content"

		git checkout feature
	)
}

# Create repo with whitespace-only file
create_whitespace_file_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		printf '   \n\t\n   ' >whitespace.txt
		git add whitespace.txt && git commit -m "Initial whitespace file"

		git checkout -b feature
		printf '   \n\t\n   \nfeature' >whitespace.txt
		git add whitespace.txt && git commit -m "Feature change"

		git checkout main
		printf '   \n\t\n   \nmain' >whitespace.txt
		git add whitespace.txt && git commit -m "Main change"

		git checkout feature
	)
}

# Create repo with untracked files
create_untracked_files_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "tracked" >tracked.txt
		git add tracked.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature" >feature.txt
		git add feature.txt && git commit -m "Feature commit"

		git checkout main
		echo "main" >main.txt
		git add main.txt && git commit -m "Main commit"

		git checkout feature

		# Add untracked files (not staged, not committed)
		echo "untracked content" >untracked.txt
		mkdir untracked_dir
		echo "more untracked" >untracked_dir/file.txt
	)
}

# Create repo with multiple commits for rebase testing
create_multi_commit_scenario() {
	local repo_dir="$1"
	local num_commits="${2:-5}"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "base" >base.txt
		git add base.txt && git commit -m "Base commit"

		git checkout -b feature
		for i in $(seq 1 "${num_commits}"); do
			echo "content ${i}" >"file${i}.txt"
			git add "file${i}.txt"
			git commit -m "Commit ${i}: add file${i}"
		done

		git checkout main
		echo "main update" >main.txt
		git add main.txt && git commit -m "Main update"

		git checkout feature
	)
}

# Create repo with dirty working directory (tracked changes)
create_dirty_repo() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >file.txt
		git add file.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature commit" >feature.txt
		git add feature.txt && git commit -m "Feature commit"

		git checkout main
		echo "main commit" >main.txt
		git add main.txt && git commit -m "Main commit"

		git checkout feature

		# Make working directory dirty (tracked file modified but not staged)
		echo "dirty change" >>file.txt
	)
}

# Create repo with staged but uncommitted changes
create_staged_dirty_repo() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >file.txt
		git add file.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature commit" >feature.txt
		git add feature.txt && git commit -m "Feature commit"

		git checkout main
		echo "main commit" >main.txt
		git add main.txt && git commit -m "Main commit"

		git checkout feature

		# Stage a change but don't commit
		echo "staged change" >>file.txt
		git add file.txt
	)
}

# Create paused rebase scenario
create_paused_rebase_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >conflict.txt
		git add conflict.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature change" >conflict.txt
		git add conflict.txt && git commit -m "Feature change"

		git checkout main
		echo "main change" >conflict.txt
		git add conflict.txt && git commit -m "Main change"

		git checkout feature

		# Start rebase and let it pause on conflict
		git rebase main 2>/dev/null || true
		# Now repo is in paused rebase state with conflict
	)
}

# Create paused cherry-pick scenario
create_paused_cherry_pick_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >conflict.txt
		git add conflict.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature change" >conflict.txt
		git add conflict.txt && git commit -m "Feature change"
		feature_commit="$(git rev-parse HEAD)"

		git checkout main
		echo "main change" >conflict.txt
		git add conflict.txt && git commit -m "Main change"

		# Cherry-pick and let it pause on conflict
		git cherry-pick "${feature_commit}" 2>/dev/null || true
		# Now repo is in paused cherry-pick state with conflict
	)
}

# Create paused merge scenario
create_paused_merge_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >conflict.txt
		git add conflict.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature change" >conflict.txt
		git add conflict.txt && git commit -m "Feature change"

		git checkout main
		echo "main change" >conflict.txt
		git add conflict.txt && git commit -m "Main change"

		# Merge and let it pause on conflict
		git merge feature 2>/dev/null || true
		# Now repo is in paused merge state with conflict
	)
}

# Create repo with a multi-file commit ready for splitting
create_split_commit_scenario() {
	local repo_dir="$1"
	local num_files="${2:-3}"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		# Initial commit
		echo "base" >base.txt
		git add base.txt && git commit -m "Initial commit"

		# Create a commit with multiple files (the one to split)
		for i in $(seq 1 "${num_files}"); do
			echo "content for file ${i}" >"file${i}.txt"
		done
		git add .
		git commit -m "Add ${num_files} files (to be split)"

		# Add another commit after (to test rebase works)
		echo "after split" >after.txt
		git add after.txt && git commit -m "Commit after the one to split"
	)
}

# Create repo with file rename in a commit
create_rename_commit_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		# Initial commit with original file
		echo "original content" >oldname.txt
		git add oldname.txt && git commit -m "Initial with oldname.txt"

		# Rename the file and modify it
		git mv oldname.txt newname.txt
		echo "modified content" >newname.txt
		echo "another file" >another.txt
		git add .
		git commit -m "Rename and add another file"
	)
}

# Create repo with binary file in a commit
create_binary_commit_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		# Initial commit
		echo "base" >base.txt
		git add base.txt && git commit -m "Initial"

		# Commit with binary and text files
		printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' >image.png
		echo "text content" >text.txt
		echo "more text" >more.txt
		git add .
		git commit -m "Add binary and text files"
	)
}

# Create repo where both branches rename the same file differently
create_rename_rename_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >shared.txt
		git add shared.txt && git commit -m "Initial"

		git checkout -b feature
		git mv shared.txt feature-renamed.txt
		echo "feature change" >>feature-renamed.txt
		git add feature-renamed.txt
		git commit -m "Rename in feature"

		git checkout main
		git mv shared.txt main-renamed.txt
		echo "main change" >>main-renamed.txt
		git add main-renamed.txt
		git commit -m "Rename in main"

		git checkout feature
	)
}

# Create repo where one branch renames a file and the other deletes it
create_rename_delete_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >shared.txt
		git add shared.txt && git commit -m "Initial"

		git checkout -b feature
		git mv shared.txt kept.txt
		echo "feature keeps file" >>kept.txt
		git add kept.txt
		git commit -m "Rename and modify"

		git checkout main
		git rm shared.txt
		git commit -m "Delete file"

		git checkout feature
	)
}

# Create repo with a branch containing a commit that is NOT ancestor of HEAD
create_non_ancestor_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "base" >base.txt
		git add base.txt && git commit -m "Base"

		# Create another branch with its own commit
		git checkout -b other
		echo "other branch" >other.txt
		git add other.txt && git commit -m "Other branch commit"

		# Return to main and add more commits so HEAD is ahead of base without merging other
		git checkout main
		echo "main change" >main.txt
		git add main.txt && git commit -m "Main change"

		echo "main change 2" >main2.txt
		git add main2.txt && git commit -m "Main change 2"

		git checkout main
	)
}

# Create repo already in rebase progress (paused on conflict)
create_rebase_in_progress_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "original" >conflict.txt
		git add conflict.txt && git commit -m "Initial"

		git checkout -b feature
		echo "feature change" >conflict.txt
		git add conflict.txt && git commit -m "Feature change"

		git checkout main
		echo "main change" >conflict.txt
		git add conflict.txt && git commit -m "Main change"

		git checkout feature
		git rebase main 2>/dev/null || true
	)
}

# Create repo where splitting a commit will lead to conflict in later commits
create_split_subsequent_conflict_scenario() {
	local repo_dir="$1"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "base" >conflict.txt
		echo "other" >other.txt
		git add conflict.txt other.txt
		git commit -m "Base"

		git checkout -b feature
		# Commit to be split (touches conflict.txt and other.txt)
		echo "feature change" >>conflict.txt
		echo "feature other" >>other.txt
		git add conflict.txt other.txt
		git commit -m "Commit to split"

		# Later commit that will conflict with main's change
		echo "feature followup" >conflict.txt
		git add conflict.txt
		git commit -m "Follow-up on conflict file"

		# Main branch introduces conflicting change after base
		git checkout main
		echo "main conflicting change" >conflict.txt
		git add conflict.txt
		git commit -m "Main conflicting change"

		git checkout feature
	)
}

# Create large history for maxCommits testing
create_large_history_scenario() {
	local repo_dir="$1"
	local total="${2:-40}"

	mkdir -p "${repo_dir}"
	(
		cd "${repo_dir}"
		git init --initial-branch=main
		_configure_test_repo

		echo "base" >base.txt
		git add base.txt && git commit -m "Base"

		git checkout -b feature
		for i in $(seq 1 "${total}"); do
			echo "change ${i}" >"file${i}.txt"
			git add "file${i}.txt"
			git commit -m "Commit ${i}"
		done
		git checkout feature
	)
}
