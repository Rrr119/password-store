#!/usr/bin/env bash

test_description='Test password rotation reminders'
cd "$(dirname "$0")"
. ./setup.sh

test_expect_success 'Rotation database is updated on password changes' '
	"$PASS" init $KEY1 &&
	echo "first" | "$PASS" insert -e fresh &&
	"$PASS" generate old 10 &&
	[[ -f "$PASSWORD_STORE_DIR/.rotation" ]] &&
	awk -F "\t" "\$1 == \"fresh\" { found = 1 } END { exit !found }" "$PASSWORD_STORE_DIR/.rotation" &&
	awk -F "\t" "\$1 == \"old\" { found = 1 } END { exit !found }" "$PASSWORD_STORE_DIR/.rotation"
'

test_expect_success '"pass audit" reports fresh entries as OK' '
	"$PASS" audit >audit.out &&
	grep -P "^fresh\tOK " audit.out &&
	grep -P "^old\tOK " audit.out
'

test_expect_success 'Stale entries are reported DUE with a non-zero exit' '
	touch -d "100 days ago" "$PASSWORD_STORE_DIR/old.gpg" &&
	stale_epoch="$(date -d "100 days ago" +%s)" &&
	tmp_rotation="$(mktemp)" &&
	awk -F "\t" -v OFS="\t" -v key="old" -v epoch="$stale_epoch" "\$1 == key { \$2 = epoch } { print }" "$PASSWORD_STORE_DIR/.rotation" > "$tmp_rotation" &&
	mv "$tmp_rotation" "$PASSWORD_STORE_DIR/.rotation" &&
	test_must_fail "$PASS" audit 30 >audit-due.out &&
	grep -P "^old\tDUE " audit-due.out &&
	grep -P "^fresh\tOK " audit-due.out
'

test_expect_success 'PASSWORD_STORE_ROTATION_DAYS changes the threshold' '
	PASSWORD_STORE_ROTATION_DAYS=200 "$PASS" audit >audit-relaxed.out &&
	grep -P "^old\tOK " audit-relaxed.out &&
	PASSWORD_STORE_ROTATION_DAYS=10 test_must_fail "$PASS" audit
'

test_expect_success 'show warns on stderr for entries past the rotation period' '
	PASSWORD_STORE_ROTATION_DAYS=30 "$PASS" show old >/dev/null 2>warn.out &&
	grep -F "old is older than 30 days and should be rotated" warn.out
'

test_expect_success 'Rotation reminders can be disabled entirely' '
	PASSWORD_STORE_ROTATION_DAYS=0 "$PASS" audit >audit-off.out &&
	grep -F "Rotation reminders are disabled" audit-off.out &&
	PASSWORD_STORE_ROTATION_DAYS=0 "$PASS" show old >/dev/null 2>no-warn.out &&
	[[ ! -s no-warn.out ]]
'

test_expect_success 'mv, cp and rm keep the rotation database consistent' '
	"$PASS" mv old moved &&
	! grep -q "^old" "$PASSWORD_STORE_DIR/.rotation" &&
	grep -q "^moved" "$PASSWORD_STORE_DIR/.rotation" &&
	"$PASS" cp fresh freshcopy &&
	grep -q "^freshcopy" "$PASSWORD_STORE_DIR/.rotation" &&
	"$PASS" rm -f moved &&
	! grep -q "^moved" "$PASSWORD_STORE_DIR/.rotation"
'

test_expect_success 'Directory mv and rm update all contained rotation entries' '
	"$PASS" generate dir/sub/a 8 &&
	"$PASS" generate dir/sub/b 8 &&
	"$PASS" mv dir renamed-dir &&
	grep -q "^renamed-dir/sub/a" "$PASSWORD_STORE_DIR/.rotation" &&
	grep -q "^renamed-dir/sub/b" "$PASSWORD_STORE_DIR/.rotation" &&
	! grep -q "^dir/" "$PASSWORD_STORE_DIR/.rotation" &&
	"$PASS" rm -rf renamed-dir &&
	! grep -q "^renamed-dir/" "$PASSWORD_STORE_DIR/.rotation"
'

test_expect_success 'Missing rotation entries fall back to the gpg file mtime' '
	grep -v "^freshcopy" "$PASSWORD_STORE_DIR/.rotation" >rotation.tmp &&
	mv rotation.tmp "$PASSWORD_STORE_DIR/.rotation" &&
	touch -d "100 days ago" "$PASSWORD_STORE_DIR/freshcopy.gpg" &&
	test_must_fail "$PASS" audit 30 >audit-mtime.out &&
	grep -P "^freshcopy\tDUE " audit-mtime.out
'

test_expect_success 'Rotation tracking is disabled together with audit logging' '
	local_store="$SHARNESS_TRASH_DIRECTORY/no-audit-rotation" &&
	echo "x" | PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" init $KEY1 &&
	echo "y" | PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" insert -e entry &&
	[[ ! -e "$local_store/.rotation" ]] &&
	PASSWORD_STORE_DIR="$local_store" PASSWORD_STORE_AUDIT_LOG="" "$PASS" audit >audit-noaudit.out &&
	grep -P "^entry\tOK " audit-noaudit.out
'

test_done
