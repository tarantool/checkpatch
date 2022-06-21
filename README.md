# Checkpatch for Tarantool

This repository contains the [checkpatch.pl](checkpatch.pl) script, which is
used for checking patches submitted for the [Tarantool][tarantool] project
against the [Tarantool contributor's guide][tarantool-dev-guide].

The checkpatch.pl script was forked from the [checkpatch.pl][linux-checkpatch]
script used for checking patches submitted for the Linux kernel.

The documentation is [here][checkpatch-doc].

The GitHub action we use to automatically check Tarantool commits when
a pull request is created is [here][checkpatch-action].

If you find any bugs, please don't hesitate to report them to the
[issue tracker][checkpatch-issues].

## Quick start

To check all Git commits on the current branch, run the following command in
your local Tarantool Git directory:
```
git clone git@github.com:tarantool/checkpatch.git
checkpatch/checkpatch.pl -g master..HEAD
```

An error message reported by checkpatch looks like this:
```
ERROR: trailing whitespace
#41: FILE: changelogs/unreleased/gh-7207-backtrace-perf-degrade.md:3:
+* Fixed performance degrade of fiber backtrace collection $
```

To get more detailed error messages, pass the `-v` (`--verbose`) flag. It will
augment each error message with an extract from the
[documentation][checkpatch-doc]:
```
ERROR: trailing whitespace
#41: FILE: changelogs/unreleased/gh-7207-backtrace-perf-degrade.md:3:
+* Fixed performance degrade of fiber backtrace collection $

Trailing whitespace should always be removed.
Some editors highlight the trailing whitespace and cause visual
distractions when editing files.
```

If you don't want to clutter the checkpatch output, you can instead pass the
`--show-types` flag. It will make checkpatch print the type of each reported
error, which you can then use to look up the full error description in the
[documentation][checkpatch-doc]. This is how our
[GitHub action][checkpatch-action] works. For example,
```
ERROR:TRAILING_WHITESPACE: trailing whitespace
#41: FILE: changelogs/unreleased/gh-7207-backtrace-perf-degrade.md:3:
+* Fixed performance degrade of fiber backtrace collection $
```

[checkpatch-action]: .github/actions/checkpatch
[checkpatch-doc]: doc/checkpatch.rst
[checkpatch-issues]: https://github.com/tarantool/checkpatch/issues
[linux-checkpatch]: https://github.com/torvalds/linux/blob/master/scripts/checkpatch.pl
[tarantool]: https://github.com/tarantool/tarantool
[tarantool-dev-guide]: https://www.tarantool.io/en/doc/latest/dev_guide/
