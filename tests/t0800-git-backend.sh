#!/usr/bin/env bash

test_description='Test audit and rotation compatibility with the git backend'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'State files are committed to the existing git repository' '
	"$PASS" init $KEY1 &&
	"$PASS" git init &&
	echo "secret" | "$PASS" insert -e team/cred1 &&
	"$PASS" show team/cred1 >/dev/null &&
	git ls-files | grep -Fx ".access.log" &&
	git ls-files | grep -Fx ".rotation" &&
	[[ -z $(git status --porcelain) ]] &&
	git log --oneline | grep -F "Audit insert event for team/cred1." &&
	git log --oneline | grep -F "Record rotation time for team/cred1."
'

test_expect_success 'All mutation commands leave the git tree clean' '
	"$PASS" generate team/cred2 10 &&
	"$PASS" mv team/cred2 team/cred2moved &&
	"$PASS" cp team/cred1 team/cred1copy &&
	"$PASS" rm -f team/cred1copy &&
	[[ -z $(git status --porcelain) ]]
'

test_expect_success 'git init picks up pre-existing audit and rotation files' '
	local_store="$SHARNESS_TRASH_DIRECTORY/late-git-store" &&
	PASSWORD_STORE_DIR="$local_store" "$PASS" init $KEY1 &&
	echo "late" | PASSWORD_STORE_DIR="$local_store" "$PASS" insert -e entry &&
	[[ ! -d "$local_store/.git" ]] &&
	PASSWORD_STORE_DIR="$local_store" "$PASS" git init &&
	git --git-dir="$local_store/.git" --work-tree="$local_store" ls-files | grep -Fx ".access.log" &&
	git --git-dir="$local_store/.git" --work-tree="$local_store" ls-files | grep -Fx ".rotation" &&
	[[ -z $(env -u GIT_DIR -u GIT_WORK_TREE git --git-dir="$local_store/.git" --work-tree="$local_store" status --porcelain) ]]
'

test_expect_success 'Audit and rotation state survive a clone and stay usable there' '
	clone_store="$SHARNESS_TRASH_DIRECTORY/cloned-store" &&
	env -u GIT_DIR -u GIT_WORK_TREE git clone -q "$PASSWORD_STORE_DIR" "$clone_store" &&
	clone_git="$clone_store/.git" &&
	git --git-dir="$clone_git" --work-tree="$clone_store" ls-files | grep -Fx ".access.log" &&
	git --git-dir="$clone_git" --work-tree="$clone_store" ls-files | grep -Fx ".rotation" &&
	env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$clone_store" "$PASS" show team/cred1 >/dev/null &&
	env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$clone_store" "$PASS" log | grep -P "\tshow\tteam/cred1$" &&
	env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$clone_store" "$PASS" audit | grep -P "^team/cred2moved\tOK " &&
	[[ -z $(env -u GIT_DIR -u GIT_WORK_TREE git --git-dir="$clone_git" --work-tree="$clone_store" status --porcelain) ]]
'

test_expect_success 'Audit and rotation keep working without any git repository' '
	local_store="$SHARNESS_TRASH_DIRECTORY/plain-git-store" &&
	env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$local_store" "$PASS" init $KEY1 &&
	echo "plain" | env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$local_store" "$PASS" insert -e entry &&
	env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$local_store" "$PASS" mv entry entry2 &&
	[[ ! -d "$local_store/.git" ]] &&
	env -u GIT_DIR -u GIT_WORK_TREE PASSWORD_STORE_DIR="$local_store" "$PASS" log | grep -P "\trename\tentry -> entry2$" &&
	grep -q "^entry2" "$local_store/.rotation" &&
	! grep -qP "^entry\t" "$local_store/.rotation"
'

test_done
