.. SPDX-License-Identifier: GPL-2.0-only

==========
Checkpatch
==========

Checkpatch (checkpatch.pl) is a perl script which checks for trivial
style violations in patches or files.

If an error reported by checkpatch appears to be false positives, please file a
bug at https://github.com/tarantool/checkpatch/issues


Options
=======

This section will describe the options checkpatch can be run with.

Usage::

  ./scripts/checkpatch.pl [OPTION]... [FILE]...

Available options:

 - -q,  --quiet

   Enable quiet mode.

 - -v,  --verbose
   Enable verbose mode.  Additional verbose test descriptions are output
   so as to provide information on why that particular message is shown.

 - --signoff

   Enable the 'Signed-off-by' line check.  The sign-off is a simple line at
   the end of the explanation for the patch, which certifies that you wrote it
   or otherwise have the right to pass it on as an open-source patch.

   Example::

	 Signed-off-by: Random J Developer <random@developer.example.org>

 - --patch

   Treat FILE as a patch.  This is the default option and need not be
   explicitly specified.

 - --emacs

   Set output to emacs compile window format.  This allows emacs users to jump
   from the error in the compile window directly to the offending line in the
   patch.

 - --terse

   Output only one line per report.

 - --showfile

   Show the diffed file position instead of the input file position.

 - -g,  --git

   Treat FILE as a single commit or a git revision range.

   Single commit with:

   - <rev>
   - <rev>^
   - <rev>~n

   Multiple commits with:

   - <rev1>..<rev2>
   - <rev1>...<rev2>
   - <rev>-<count>

 - -f,  --file

   Treat FILE as a regular source file.  This option must be used when running
   checkpatch on source files.

 - --list-types

   Every message emitted by checkpatch has an associated TYPE.  Add this flag
   to display all the types in checkpatch.

   Note that when this flag is active, checkpatch does not read the input FILE,
   and no message is emitted.  Only a list of types in checkpatch is output.

 - --types TYPE(,TYPE2...)

   Only display messages with the given types.

   Example::

     ./scripts/checkpatch.pl mypatch.patch --types EMAIL_SUBJECT,BRACES

 - --ignore TYPE(,TYPE2...)

   Checkpatch will not emit messages for the specified types.

   Example::

     ./scripts/checkpatch.pl mypatch.patch --ignore EMAIL_SUBJECT,BRACES

 - --show-types

   By default checkpatch doesn't display the type associated with the messages.
   Set this flag to show the message type in the output.

 - --max-line-length=n

   Set the max line length (default 80).  If a line exceeds the specified
   length, a LONG_LINE message is emitted.

 - --tab-size=n

   Set the number of spaces for tab (default 8).

 - --no-summary

   Suppress the per file summary.

 - --mailback

   Only produce a report in case of Warnings or Errors.  Milder Checks are
   excluded from this.

 - --summary-file

   Include the filename in summary.

 - --debug KEY=[0|1]

   Turn on/off debugging of KEY, where KEY is one of 'values', 'possible',
   'type', and 'attr' (default is all off).

 - --codespell

   Use the codespell dictionary for checking spelling errors.

 - --codespellfile

   Use the specified codespell file.
   Default is '/usr/share/codespell/dictionary.txt'.

 - --typedefsfile

   Read additional types from this file.

 - --color[=WHEN]

   Use colors 'always', 'never', or only when output is a terminal ('auto').
   Default is 'auto'.

 - -h, --help, --version

   Display the help text.

Type Descriptions
=================

This section contains a description of all the message types in checkpatch.

.. Types in this section are also parsed by checkpatch.
.. The types are grouped into subsections based on use.


Allocation style
----------------

  **ALLOC_ARRAY_ARGS**
    The first argument for calloc should be the number of elements.
    sizeof() as the first argument is generally wrong.

  **ALLOC_SIZEOF_STRUCT**
    The allocation style is bad.  In general for family of
    allocation functions using sizeof() to get memory size,
    constructs like::

      p = alloc(sizeof(struct foo), ...)

    should be::

      p = alloc(sizeof(*p), ...)

  **XMALLOC**
    Normally, malloc function never fails.  In case of memory shortage,
    the OS will likely just kill the application instead of returning NULL.
    So we use xmalloc wrapper instead, which panics in case malloc returns
    NULL.


API usage
---------

  **MALFORMED_INCLUDE**
    The #include statement has a malformed path.  This has happened
    because the author has included a double slash "//" in the pathname
    accidentally.


Comments
--------

  **BLOCK_COMMENT_STYLE**
    The comment style is incorrect.  The preferred style for multi-
    line comments is::

      /*
       * This is the preferred style
       * for multi line comments.
       */

  **C99_COMMENTS**
    C99 style single line comments (//) should not be used.
    Prefer the block comment style instead.

  **UNCOMMENTED_DEFINITION**
    Every global variable, function, struct, and struct member should have
    a comment.

Commit message
--------------

  **BAD_SIGN_OFF**
    The signed-off-by line does not fall in line with the standards
    specified by the community.

  **COMMIT_LOG_LONG_LINE**
    Commit log should fit in 75 characters. If you need to insert a longer
    line into the commit log (e.g. an extract from a log or a test output),
    please surround the corresponding section with NO_WRAP, for example::

      Normal text.

      NO_WRAP
      Long line.
      Another long line.
      NO_WRAP

      Normal text.

  **COMMIT_MESSAGE**
    The patch is missing a commit description.  A brief
    description of the changes made by the patch should be added.

  **EMAIL_SUBJECT**
    Naming the tool that found the issue is not very useful in the
    subject line.  A good subject line summarizes the change that
    the patch brings.

  **FROM_SIGN_OFF_MISMATCH**
    The author's email does not match with that in the Signed-off-by:
    line(s). This can be sometimes caused due to an improperly configured
    email client.

    This message is emitted due to any of the following reasons::

      - The email names do not match.
      - The email addresses do not match.
      - The email subaddresses do not match.
      - The email comments do not match.

  **MISSING_SIGN_OFF**
    The patch is missing a Signed-off-by line.  A signed-off-by
    line should be added according to Developer's certificate of
    Origin.

  **NO_AUTHOR_SIGN_OFF**
    The author of the patch has not signed off the patch.  It is
    required that a simple sign off line should be present at the
    end of explanation of the patch to denote that the author has
    written it or otherwise has the rights to pass it on as an open
    source patch.

  **DIFF_IN_COMMIT_MSG**
    Avoid having diff content in commit message.
    This causes problems when one tries to apply a file containing both
    the changelog and the diff because patch(1) tries to apply the diff
    which it found in the changelog.

  **GERRIT_CHANGE_ID**
    To be picked up by gerrit, the footer of the commit message might
    have a Change-Id like::

      Change-Id: Ic8aaa0728a43936cd4c6e1ed590e01ba8f0fbf5b
      Signed-off-by: A. U. Thor <author@example.com>

    The Change-Id line must be removed before submitting.

  **GIT_COMMIT_ID**
    The proper way to reference a commit id is:
    commit <12+ chars of sha1> ("<title line>")

    An example may be::

      Commit e21d2170f36602ae2708 ("video: remove unnecessary
      platform_set_drvdata()") removed the unnecessary
      platform_set_drvdata(), but left the variable "dev" unused,
      delete it.


Comparison style
----------------

  **ASSIGN_IN_IF**
    Do not use assignments in if condition.
    Example::

      if ((foo = bar(...)) < BAZ) {

    should be written as::

      foo = bar(...);
      if (foo < BAZ) {

  **BOOL_COMPARISON**
    Comparisons of A to true and false are better written
    as A and !A.

  **CONSTANT_COMPARISON**
    Comparisons with a constant or upper case identifier on the left
    side of the test should be avoided.


Indentation and Line Breaks
---------------------------

  **CODE_INDENT**
    Code indent should use tabs instead of spaces.  Outside of comments and
    documentation, spaces are never used for indentation.

  **DEEP_INDENTATION**
    Indentation with 6 or more tabs usually indicate overly indented
    code.

    It is suggested to refactor excessive indentation of
    if/else/for/do/while/switch statements.

  **SWITCH_CASE_INDENT_LEVEL**
    switch should be at the same indent as case.
    Example::

      switch (suffix) {
      case 'G':
      case 'g':
              mem <<= 30;
              break;
      case 'M':
      case 'm':
              mem <<= 20;
              break;
      case 'K':
      case 'k':
              mem <<= 10;
              fallthrough;
      default:
              break;
      }

  **LONG_LINE**
    The line has exceeded the specified maximum length.
    To use a different maximum line length, the --max-line-length=n option
    may be added while invoking checkpatch.

  **LONG_LINE_STRING**
    A string starts before but extends beyond the maximum line length.
    To use a different maximum line length, the --max-line-length=n option
    may be added while invoking checkpatch.

  **LONG_LINE_COMMENT**
    A comment starts before but extends beyond the maximum line length.
    To use a different maximum line length, the --max-line-length=n option
    may be added while invoking checkpatch.

  **MULTILINE_DEREFERENCE**
    A single dereferencing identifier spanned on multiple lines like::

      struct_identifier->member[index].
      member = <foo>;

    is generally hard to follow. It can easily lead to typos and so makes
    the code vulnerable to bugs.

    If fixing the multiple line dereferencing leads to an 80 column
    violation, then either rewrite the code in a more simple way or if the
    starting part of the dereferencing identifier is the same and used at
    multiple places then store it in a temporary variable, and use that
    temporary variable only at all the places. For example, if there are
    two dereferencing identifiers::

      member1->member2->member3.foo1;
      member1->member2->member3.foo2;

    then store the member1->member2->member3 part in a temporary variable.
    It not only helps to avoid the 80 column violation but also reduces
    the program size by removing the unnecessary dereferences.

    But if none of the above methods work then ignore the 80 column
    violation because it is much easier to read a dereferencing identifier
    on a single line.

  **TRAILING_STATEMENTS**
    Trailing statements (for example after any conditional) should be
    on the next line.
    Statements, such as::

      if (x == y) break;

    should be::

      if (x == y)
              break;


Macros, Attributes and Symbols
------------------------------

  **ARRAY_SIZE**
    The lengthof(foo) macro should be preferred over sizeof(foo)/sizeof(foo[0])
    for finding number of elements in an array.

    The macro is defined as::

      #define lengthof(x) (sizeof(x) / sizeof((x)[0]))

  **AVOID_EXTERNS**
    Function prototypes don't need to be declared extern in .h
    files.  It's assumed by the compiler and is unnecessary.

  **DATE_TIME**
    It is generally desirable that building the same source code with
    the same set of tools is reproducible, i.e. the output is always
    exactly the same.

    We don't use the ``__DATE__`` and ``__TIME__`` macros,
    and enable warnings if they are used as they can lead to
    non-deterministic builds.

  **DO_WHILE_MACRO_WITH_TRAILING_SEMICOLON**
    do {} while(0) macros should not have a trailing semicolon.

  **INCLUDE_GUARD**
    In new header files ``#pragma once`` should be used instead of
    include guard macros.

  **INLINE_LOCATION**
    The inline keyword should sit between storage class and type.

    For example, the following segment::

      inline static int example_function(void)
      {
              ...
      }

    should be::

      static inline int example_function(void)
      {
              ...
      }

  **MULTISTATEMENT_MACRO_USE_DO_WHILE**
    Macros with multiple statements should be enclosed in a
    do - while block.  Same should also be the case for macros
    starting with `if` to avoid logic defects::

      #define macrofun(a, b, c)                 \
        do {                                    \
                if (a == 5)                     \
                        do_this(b, c);          \
        } while (0)

  **PREFER_FALLTHROUGH**
    Use the `FALLTHROUGH;` pseudo keyword instead of
    `/* fallthrough */` like comments.

  **TRAILING_SEMICOLON**
    Macro definition should not end with a semicolon. The macro
    invocation style should be consistent with function calls.
    This can prevent any unexpected code paths::

      #define MAC do_something;

    If this macro is used within a if else statement, like::

      if (some_condition)
              MAC;

      else
              do_something;

    Then there would be a compilation error, because when the macro is
    expanded there are two trailing semicolons, so the else branch gets
    orphaned.

  **SINGLE_STATEMENT_DO_WHILE_MACRO**
    For the multi-statement macros, it is necessary to use the do-while
    loop to avoid unpredictable code paths. The do-while loop helps to
    group the multiple statements into a single one so that a
    function-like macro can be used as a function only.

    But for the single statement macros, it is unnecessary to use the
    do-while loop. Although the code is syntactically correct but using
    the do-while loop is redundant. So remove the do-while loop for single
    statement macros.

  **WEAK_DECLARATION**
    Using weak declarations like __attribute__((weak)) or __weak
    can have unintended link defects.  Avoid using them.


Functions and Variables
-----------------------

  **CONST_CONST**
    Using `const <type> const *` is generally meant to be
    written `const <type> * const`.

  **EMBEDDED_FUNCTION_NAME**
    Embedded function names are less appropriate to use as
    refactoring can cause function renaming.  Prefer the use of
    "%s", __func__ to embedded function names.

    Note that this does not work with -f (--file) checkpatch option
    as it depends on patch context providing the function name.

  **FUNCTION_ARGUMENTS**
    This error is emitted due to any of the following reasons:

      1. Arguments for the function declaration do not follow
         the identifier name.  Example::

           void foo
           (int bar, int baz)

         This should be corrected to::

           void foo(int bar, int baz)

      2. Some arguments for the function definition do not
         have an identifier name.  Example::

           void foo(int)

         All arguments should have identifier names.

  **FUNCTION_NAME_NO_NEWLINE**
    Function name and return value type should be placed on
    different lines::

      int foo(int bar)

    should be::

      int
      foo(int bar)

  **FUNCTION_WITHOUT_ARGS**
    Function declarations without arguments like::

      int foo()

    should be::

      int foo(void)

  **MULTIPLE_ASSIGNMENTS**
    Multiple assignments on a single line makes the code unnecessarily
    complicated. So on a single line assign value to a single variable
    only, this makes the code more readable and helps avoid typos.

  **RETURN_PARENTHESES**
    return is not a function and as such doesn't need parentheses::

      return (bar);

    can simply be::

      return bar;


Permissions
-----------

  **EXECUTE_PERMISSIONS**
    There is no reason for source files to be executable.  The executable
    bit can be removed safely.  The only exception is a script that has a
    hashbang sign (#!) - it must be executable.

  **NON_OCTAL_PERMISSIONS**
    Permission bits should use 4 digit octal permissions (like 0700 or 0444).
    Avoid using any other base like decimal.


Spacing and Brackets
--------------------

  **ASSIGNMENT_CONTINUATIONS**
    Assignment operators should not be written at the start of a
    line but should follow the operand at the previous line.

  **BRACES**
    The placement of braces is stylistically incorrect.
    The preferred way is to put the opening brace last on the line,
    and put the closing brace first::

      if (x is true) {
              we do y
      }

    This applies for all non-functional blocks.
    However, there is one special case, namely functions: they have the
    opening brace at the beginning of the next line, thus::

      int function(int x)
      {
              body of function
      }

  **BRACKET_SPACE**
    Whitespace before opening bracket '[' is prohibited.
    There are some exceptions:

    1. With a type on the left::

        int [] a;

    2. At the beginning of a line for slice initialisers::

        [0...10] = 5,

    3. Inside a curly brace::

        = { [0...10] = 5 }

  **CONCATENATED_STRING**
    Concatenated elements should have a space in between.
    Example::

      printk(KERN_INFO"bar");

    should be::

      printk(KERN_INFO "bar");

  **ELSE_AFTER_BRACE**
    `else {` should follow the closing block `}` on the same line.

  **LINE_SPACING**
    Vertical space is wasted given the limited number of lines an
    editor window can display when multiple blank lines are used.

  **OPEN_BRACE**
    The opening brace should be following the function definitions on the
    next line.  For any non-functional block it should be on the same line
    as the last construct.

  **POINTER_LOCATION**
    When using pointer data or a function that returns a pointer type,
    the preferred use of * is adjacent to the data name or function name
    and not adjacent to the type name.
    Examples::

      char *linux_banner;
      unsigned long long memparse(char *ptr, char **retptr);
      char *match_strdup(substring_t *s);

  **REFERENCE_LOCATION**
    When using reference data or a function that returns a reference type,
    the preferred use of & is adjacent to the data name or function name
    and not adjacent to the type name.
    Examples::

      int &foo;
      U &bar(T &&x);

  **TRAILING_WHITESPACE**
    Trailing whitespace should always be removed.
    Some editors highlight the trailing whitespace and cause visual
    distractions when editing files.

  **TYPEDEF_NEWLINE**
    A type should be separated from 'typedef' by a space, not a new line::

      typedef int my_int;
      typedef int
      (*my_func)(void);

  **UNNECESSARY_PARENTHESES**
    Parentheses are not required in the following cases:

      1. Function pointer uses::

          (foo->bar)();

        could be::

          foo->bar();

      2. addressof/dereference single Lvalues::

          &(foo->bar)
          *(foo->bar)

        could be::

          &foo->bar
          *foo->bar

  **WHILE_AFTER_BRACE**
    while should follow the closing bracket on the same line::

      do {
              ...
      } while(something);


Others
------

  **CORRUPTED_PATCH**
    The patch seems to be corrupted or lines are wrapped.
    Please regenerate the patch file before sending it to the maintainer.

  **DEFAULT_NO_BREAK**
    switch default case is sometimes written as "default:;".  This can
    cause new cases added below default to be defective.

    A "break;" should be added after empty default statement to avoid
    unwanted fallthrough.

  **DOS_LINE_ENDINGS**
    For DOS-formatted patches, there are extra ^M symbols at the end of
    the line.  These should be removed.

  **MEMSET**
    The memset use appears to be incorrect.  This may be caused due to
    badly ordered parameters.  Please recheck the usage.

  **NO_CHANGELOG**
    The patch lacks a changelog.  Please add a new changelog entry to the
    changelog/unreleased directory.  If the patch doesn't need a changelog
    (e.g. it fixes a flaky test), please add NO_CHANGELOG=<reason> to the
    commit log.

  **NO_DOC**
    The patch lacks a documentation request.  Please add::

      @TarantoolBot document
      Title: <title>
      <description>

    to the commit log.  If the patch doesn't need a documentation request
    (e.g. it's a bug fix), please add NO_DOC=<reason> to the commit log.

  **NO_TEST**
    The patch lacks a test.  Please add a new test to the test/ directory.
    If the patch doesn't need a test (e.g. it fixes a CI issue), please add
    NO_TEST=<reason> to the commit log.

  **NOT_UNIFIED_DIFF**
    The patch file does not appear to be in unified-diff format.  Please
    regenerate the patch file before sending it to the maintainer.

  **PRINTF_0XDECIMAL**
    Prefixing 0x with decimal output is defective and should be corrected.

  **TEST_RESULT_FILE**
    For regression tests, there are .result files. Tests with .result files
    should be avoided. It is recommended to use Luatest or TAP for Tarantool
    regression tests.

  **TYPO_SPELLING**
    Some words may have been misspelled.  Consider reviewing them.

  **UNSAFE_FUNCTION**
    Some standard C functions are deprecated, because they are unsafe.
    For example, one should use 'snprintf' instead of 'sprintf', because
    the latter may write beyond the provided buffer.
