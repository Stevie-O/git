# verify that unrecognized options are rejected by 'git bisect run'
#!/bin/sh

# the linter's not smart enough to handle set -e
GIT_TEST_CHAIN_LINT=0

test_description='Tests git bisect run'

exec </dev/null

. ./test-lib.sh

{ test_expect_success 'Setting up repo for "git bisect run" tests.' "$(cat)" ; } <<'SETUP'
(
# I don't know how they managed it, but the git test engine
# somehow ignores the effect of 'set -e'.
set -eu || exit 1
# set -e canary
false
# hopefully, next year, we get -o pipefail!
echo '.DEFAULT: dummy
.PHONY: dummy
dummy:
	true
' > Makefile
make
echo '0' >path0
git update-index --add -- Makefile path0
git commit -q -m 'initial commit'
git tag working0
# make some commits that don't cause problems
for x in `test_seq 1 20`; do
	echo "$x" >path0
	git update-index --replace -- path0
	git commit -q -m "working commit $x"
	git tag "working$x"
done
# break the makefile
sed -i.bak -e 's/true/false/' Makefile
rm -f Makefile.bak
! make
git update-index --replace -- Makefile
git commit -q -m "First broken commit"
git tag broken0
# make some more commits that still FTBFS
echo "exit code was $?; flags are $-"
for x in `test_seq 1 20`; do
	echo "$x" >path0
	git update-index --replace -- path0
	git commit -q -m "broken build $x"
	git tag "broken$x"
done
# repair it
git checkout working0 -- Makefile
make
git update-index --replace -- Makefile
git commit -q -m "First repaired commit"
git tag fixed0
# make some more commits with the bugfix
for x in `test_seq 1 20`; do
	echo "$x" >path0
	git update-index --replace -- path0
	git commit -q -m "fixed build $x"
	git tag "fixed$x"
done
#sh -c 'bash -i <> /dev/tty >&0 2>&1'
)

SETUP

test_expect_success 'setup first bisect' 'git bisect start && git bisect good working0 && git bisect bad broken9'

test_expect_failure() {
	shift
	#echo arguments are "$*"
	test_must_fail "$@"
}

# okay, let's do some negative testing

OLDPATH="$PATH"

PATH="$PATH:."

test_expect_success 'setup this-is-not-a-valid-option' '
 echo "#/bin/sh" > --this-is-not-a-valid-option &&
 chmod a+x -- --this-is-not-a-valid-option &&
 --this-is-not-a-valid-option'

test_expect_failure 'git bisect run: reject unrecognized options' git bisect run --this-is-not-a-valid-option

PATH="$OLDPATH"

test_expect_failure 'git bisect run: reject invalid values for --expect'  git bisect run --expect=invalid make

# okay, all of these settings are mutually exclusive (for sanity's sake, even with themselves)
for a in --expect=bad --expect=good -r --invert; do
	for b in --expect=bad --expect=good -r --invert; do
		test_expect_failure 'git bisect run: reject multiple --expect options'  git bisect run $a $b make
	done
done

# finally, verify that '--' is honored (note that will mess things up and require a bisect reset)
PATH="$PATH:."

test_expect_success 'git bisect run: honor --' 'git bisect run -- --this-is-not-a-valid-option'

PATH="$OLDPATH"

for expect_syntax in '' --expect=good; do

	# now we have to undo the bisect run
	test_expect_success 'restarting bisection' 'git bisect reset && git bisect start && git bisect good working0 && git bisect bad broken9'

	test_expect_success "running bisection ($expect_syntax)" "
git bisect run $expect_syntax make &&
git log --oneline &&
	# we should have determined that broken0 is the first bad version
	test_cmp_rev broken0 refs/bisect/bad &&
	# and that version should be the one checked out
	test_cmp_rev broken0 HEAD
"
done


# NOW, test the reverse:  find when we fixed it again

for expect_syntax in -r --invert --expect=fixed; do

	test_expect_success 'restarting bisection' 'git bisect reset && git bisect start --term-old=broken --term-new=fixed && git bisect broken broken20 && git bisect fixed fixed20'
	test_expect_success "running bisection ($expect_syntax)" "
		git bisect run $expect_syntax make &&
		git log --oneline &&
	test_cmp_rev fixed0 refs/bisect/fixed &&
	test_cmp_rev fixed0 HEAD
	"
done

test_expect_failure 'sanity check error message with custom terms' git bisect run --expect=invalid make


test_done
