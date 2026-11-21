#!/usr/bin/env bash

test_description='Test access audit logging'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Audit log records insert and show events' '
	"$PASS" init $KEY1 &&
	echo "secret" | "$PASS" insert -e team/cred1 &&
	"$PASS" show team/cred1 >/dev/null &&
	[[ -f "$PASSWORD_STORE_DIR/.access.log" ]] &&
	grep -P "\tinsert\tteam/cred1$" "$PASSWORD_STORE_DIR/.access.log" &&
	grep -P "\tshow\tteam/cred1$" "$PASSWORD_STORE_DIR/.access.log"
'

test_expect_success 'Audit log records edit, generate and delete events' '
	"$PASS" generate team/cred2 12 &&
	export EDITOR="fake-editor-change-password.sh" PATH="$TEST_HOME:$PATH" FAKE_EDITOR_PASSWORD="rotated" &&
	"$PASS" edit team/cred2 &&
	"$PASS" rm -f team/cred2 &&
	grep -P "\tgenerate\tteam/cred2$" "$PASSWORD_STORE_DIR/.access.log" &&
	grep -P "\tedit\tteam/cred2$" "$PASSWORD_STORE_DIR/.access.log" &&
	grep -P "\tdelete\tteam/cred2$" "$PASSWORD_STORE_DIR/.access.log"
'

test_expect_success 'Audit log records mv and cp events' '
	"$PASS" mv team/cred1 team/cred1moved &&
	"$PASS" cp team/cred1moved team/cred1copy &&
	grep -P "\trename\tteam/cred1 -> team/cred1moved$" "$PASSWORD_STORE_DIR/.access.log" &&
	grep -P "\tcopy\tteam/cred1moved -> team/cred1copy$" "$PASSWORD_STORE_DIR/.access.log"
'

test_expect_success 'Audit log records grep events' '
	"$PASS" grep secret >/dev/null &&
	grep -P "\tgrep\tsecret$" "$PASSWORD_STORE_DIR/.access.log"
'

test_expect_success '"pass log" prints the audit log' '
	"$PASS" log | grep -P "\trename\tteam/cred1 -> team/cred1moved$"
'

test_expect_success '"pass log name" filters by entry and subfolder' '
	"$PASS" show team/cred1moved >/dev/null &&
	"$PASS" log team/cred1moved | grep -P "\tshow\tteam/cred1moved$" &&
	! "$PASS" log team/cred1moved | grep -P "\tinsert\tteam/cred1copy$" &&
	"$PASS" log team | grep -P "\tcopy\tteam/cred1moved -> team/cred1copy$"
'

test_expect_success 'Empty PASSWORD_STORE_AUDIT_LOG disables auditing' '
	local_store="$SHARNESS_TRASH_DIRECTORY/no-audit-store" &&
	PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" init $KEY1 &&
	echo "quiet" | PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" insert -e hidden &&
	PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" show hidden >/dev/null &&
	[[ ! -e "$local_store/.access.log" ]] &&
	test_must_fail env PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" log
'

test_expect_success 'Audit log works without a git repository' '
	local_store="$SHARNESS_TRASH_DIRECTORY/plain-store" &&
	PASSWORD_STORE_DIR="$local_store" "$PASS" init $KEY1 &&
	echo "plain" | PASSWORD_STORE_DIR="$local_store" "$PASS" insert -e entry &&
	[[ ! -d "$local_store/.git" ]] &&
	PASSWORD_STORE_DIR="$local_store" "$PASS" log | grep -P "\tinsert\tentry$"
'

test_done
