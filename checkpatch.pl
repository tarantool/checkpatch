#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0
#
# (c) 2001, Dave Jones. (the file handling bit)
# (c) 2005, Joel Schopp <jschopp@austin.ibm.com> (the ugly bit)
# (c) 2007,2008, Andy Whitcroft <apw@uk.ibm.com> (new conditions, test suite)
# (c) 2008-2010 Andy Whitcroft <apw@canonical.com>
# (c) 2010-2018 Joe Perches <joe@perches.com>

use strict;
use warnings;
use utf8;
use POSIX;
use File::Basename;
use Cwd 'abs_path';
use Term::ANSIColor qw(:constants);
use Encode qw(decode encode);

my $P = $0;
my $D = dirname(abs_path($P));

my $V = '0.32';

use Getopt::Long qw(:config no_auto_abbrev);

my $quiet = 0;
my $verbose = 0;
my %verbose_messages = ();
my %verbose_emitted = ();
my $chk_signoff = 0;
my $chk_patch = 1;
my $tst_only;
my $emacs = 0;
my $terse = 0;
my $showfile = 0;
my $file = 0;
my $git = 0;
my %git_commits = ();
my $summary = 1;
my $mailback = 0;
my $summary_file = 0;
my $show_types = 0;
my $list_types = 0;
my $gitroot = $ENV{'GIT_DIR'};
$gitroot = ".git" if !defined($gitroot);
my %debug;
my %use_type = ();
my @use = ();
my %ignore_type = ();
my @ignore = ();
my $help = 0;
my $configuration_file = ".checkpatch.conf";
my $max_line_length = 80;
my $minimum_perl_version = 5.10.0;
my $spelling_file = "$D/spelling.txt";
my $codespell = 0;
my $codespellfile = "/usr/share/codespell/dictionary.txt";
my $user_codespellfile = "";
my $docsfile = "$D/doc/checkpatch.rst";
my $typedefsfile;
my $color = "auto";
# git output parsing needs US English output, so first set backtick child process LANGUAGE
my $git_command ='export LANGUAGE=en_US.UTF-8; git';
my $tabsize = 8;

sub help {
	my ($exitcode) = @_;

	print << "EOM";
Usage: $P [OPTION]... [FILE]...
Version: $V

Options:
  -q, --quiet                quiet
  -v, --verbose              verbose mode
  --signoff                  check for 'Signed-off-by' line
  --patch                    treat FILE as patchfile (default)
  --emacs                    emacs compile window format
  --terse                    one line per report
  --showfile                 emit diffed file position, not input file position
  -g, --git                  treat FILE as a single commit or git revision range
                             single git commit with:
                               <rev>
                               <rev>^
                               <rev>~n
                             multiple git commits with:
                               <rev1>..<rev2>
                               <rev1>...<rev2>
                               <rev>-<count>
                             git merges are ignored
  -f, --file                 treat FILE as regular source file
  --list-types               list the possible message types
  --types TYPE(,TYPE2...)    show only these comma separated message types
  --ignore TYPE(,TYPE2...)   ignore various comma separated message types
  --show-types               show the specific message type in the output
  --max-line-length=n        set the maximum line length, (default $max_line_length)
  --tab-size=n               set the number of spaces for tab (default $tabsize)
  --no-summary               suppress the per-file summary
  --mailback                 only produce a report in case of errors
  --summary-file             include the filename in summary
  --debug KEY=[0|1]          turn on/off debugging of KEY, where KEY is one of
                             'values', 'possible', 'type', and 'attr' (default
                             is all off)
  --test-only=WORD           report only errors containing WORD
                             literally
  --codespell                Use the codespell dictionary for spelling/typos
                             (default:$codespellfile)
  --codespellfile            Use this codespell dictionary
  --typedefsfile             Read additional types from this file
  --color[=WHEN]             Use colors 'always', 'never', or only when output
                             is a terminal ('auto'). Default is 'auto'.
  -h, --help, --version      display this help and exit

When FILE is - read standard input.
EOM

	exit($exitcode);
}

sub uniq {
	my %seen;
	return grep { !$seen{$_}++ } @_;
}

sub list_types {
	my ($exitcode) = @_;

	my $count = 0;

	local $/ = undef;

	open(my $script, '<', abs_path($P)) or
	    die "$P: Can't read '$P' $!\n";

	my $text = <$script>;
	close($script);

	my %types = ();
	# Also catch when type is passed through a variable
	while ($text =~ /(?:\bERROR\s*\(|\$msg_type\s*=)\s*"([^"]+)"/g) {
		$types{$1} = 1;
	}

	print("#\tMessage type\n");
	foreach my $type (sort keys %types) {
		my $orig_type = $type;
		if ($color) {
			$type = RED . $type . RESET;
		}
		print(++$count . "\t" . $type . "\n");
		if ($verbose && exists($verbose_messages{$orig_type})) {
			my $message = $verbose_messages{$orig_type};
			$message =~ s/\n/\n\t/g;
			print("\t" . $message . "\n\n");
		}
	}

	exit($exitcode);
}

my $conf = which_conf($configuration_file);
if (-f $conf) {
	my @conf_args;
	open(my $conffile, '<', "$conf")
	    or warn "$P: Can't find a readable $configuration_file file $!\n";

	while (<$conffile>) {
		my $line = $_;

		$line =~ s/\s*\n?$//g;
		$line =~ s/^\s*//g;
		$line =~ s/\s+/ /g;

		next if ($line =~ m/^\s*#/);
		next if ($line =~ m/^\s*$/);

		my @words = split(" ", $line);
		foreach my $word (@words) {
			last if ($word =~ m/^#/);
			push (@conf_args, $word);
		}
	}
	close($conffile);
	unshift(@ARGV, @conf_args) if @conf_args;
}

sub load_docs {
	open(my $docs, '<', "$docsfile")
	    or warn "$P: Can't read the documentation file $docsfile $!\n";

	my $type = '';
	my $desc = '';
	my $in_desc = 0;

	while (<$docs>) {
		chomp;
		my $line = $_;
		$line =~ s/\s+$//;

		if ($line =~ /^\s*\*\*(.+)\*\*$/) {
			if ($desc ne '') {
				$verbose_messages{$type} = trim($desc);
			}
			$type = $1;
			$desc = '';
			$in_desc = 1;
		} elsif ($in_desc) {
			if ($line =~ /^(?:\s{4,}|$)/) {
				$line =~ s/^\s{4}//;
				$desc .= $line;
				$desc .= "\n";
			} else {
				$verbose_messages{$type} = trim($desc);
				$type = '';
				$desc = '';
				$in_desc = 0;
			}
		}
	}

	if ($desc ne '') {
		$verbose_messages{$type} = trim($desc);
	}
	close($docs);
}

# Perl's Getopt::Long allows options to take optional arguments after a space.
# Prevent --color by itself from consuming other arguments
foreach (@ARGV) {
	if ($_ eq "--color" || $_ eq "-color") {
		$_ = "--color=$color";
	}
}

GetOptions(
	'q|quiet+'	=> \$quiet,
	'v|verbose!'	=> \$verbose,
	'signoff!'	=> \$chk_signoff,
	'patch!'	=> \$chk_patch,
	'emacs!'	=> \$emacs,
	'terse!'	=> \$terse,
	'showfile!'	=> \$showfile,
	'f|file!'	=> \$file,
	'g|git!'	=> \$git,
	'ignore=s'	=> \@ignore,
	'types=s'	=> \@use,
	'show-types!'	=> \$show_types,
	'list-types!'	=> \$list_types,
	'max-line-length=i' => \$max_line_length,
	'tab-size=i'	=> \$tabsize,
	'summary!'	=> \$summary,
	'mailback!'	=> \$mailback,
	'summary-file!'	=> \$summary_file,
	'debug=s'	=> \%debug,
	'test-only=s'	=> \$tst_only,
	'codespell!'	=> \$codespell,
	'codespellfile=s'	=> \$user_codespellfile,
	'typedefsfile=s'	=> \$typedefsfile,
	'color=s'	=> \$color,
	'no-color'	=> \$color,	#keep old behaviors of -nocolor
	'nocolor'	=> \$color,	#keep old behaviors of -nocolor
	'h|help'	=> \$help,
	'version'	=> \$help
) or $help = 2;

if ($user_codespellfile) {
	# Use the user provided codespell file unconditionally
	$codespellfile = $user_codespellfile;
} elsif (!(-f $codespellfile)) {
	# If /usr/share/codespell/dictionary.txt is not present, try to find it
	# under codespell's install directory: <codespell_root>/data/dictionary.txt
	if (($codespell || $help) && which("codespell") ne "" && which("python") ne "") {
		my $python_codespell_dict = << "EOF";

import os.path as op
import codespell_lib
codespell_dir = op.dirname(codespell_lib.__file__)
codespell_file = op.join(codespell_dir, 'data', 'dictionary.txt')
print(codespell_file, end='')
EOF

		my $codespell_dict = `python -c "$python_codespell_dict" 2> /dev/null`;
		$codespellfile = $codespell_dict if (-f $codespell_dict);
	}
}

# $help is 1 if either -h, --help or --version is passed as option - exitcode: 0
# $help is 2 if invalid option is passed - exitcode: 1
help($help - 1) if ($help);

die "$P: --git cannot be used with --file\n" if ($git && $file);
die "$P: --verbose cannot be used with --terse\n" if ($verbose && $terse);

if ($color =~ /^[01]$/) {
	$color = !$color;
} elsif ($color =~ /^always$/i) {
	$color = 1;
} elsif ($color =~ /^never$/i) {
	$color = 0;
} elsif ($color =~ /^auto$/i) {
	$color = (-t STDOUT);
} else {
	die "$P: Invalid color mode: $color\n";
}

load_docs() if ($verbose);
list_types(0) if ($list_types);

my $exit = 0;

if ($^V && $^V lt $minimum_perl_version) {
	printf "$P: requires at least perl version %vd\n", $minimum_perl_version;
	exit(1)
}

#if no filenames are given, push '-' to read patch from stdin
if ($#ARGV < 0) {
	push(@ARGV, '-');
}

# skip TAB size 1 to avoid additional checks on $tabsize - 1
die "$P: Invalid TAB size: $tabsize\n" if ($tabsize < 2);

sub hash_save_array_words {
	my ($hashRef, $arrayRef) = @_;

	my @array = split(/,/, join(',', @$arrayRef));
	foreach my $word (@array) {
		$word =~ s/\s*\n?$//g;
		$word =~ s/^\s*//g;
		$word =~ s/\s+/ /g;
		$word =~ tr/[a-z]/[A-Z]/;

		next if ($word =~ m/^\s*#/);
		next if ($word =~ m/^\s*$/);

		$hashRef->{$word}++;
	}
}

sub hash_show_words {
	my ($hashRef, $prefix) = @_;

	if (keys %$hashRef) {
		print "\nNOTE: $prefix message types:";
		foreach my $word (sort keys %$hashRef) {
			print " $word";
		}
		print "\n";
	}
}

hash_save_array_words(\%ignore_type, \@ignore);
hash_save_array_words(\%use_type, \@use);

my $dbg_values = 0;
my $dbg_possible = 0;
my $dbg_type = 0;
my $dbg_attr = 0;
for my $key (keys %debug) {
	## no critic
	eval "\${dbg_$key} = '$debug{$key}';";
	die "$@" if ($@);
}

if ($terse) {
	$emacs = 1;
	$quiet++;
}

my $emitted_corrupt = 0;

our $Ident	= qr{
			(?:::)?(?:[A-Za-z_][A-Za-z\d_]*::)*
			[A-Za-z_][A-Za-z\d_]*
			(?:\s*\#\#\s*[A-Za-z_][A-Za-z\d_]*)*
		}x;
our $Storage	= qr{extern|static};
our $Attribute	= qr{
			typename|
			const|
			volatile|
			alignas|
			API_EXPORT|
			CFORMAT|
			DEPREACTED|
			FALLTHROUGH|
			MAYBE_UNUSED|
			NODISCARD|
			NORETURN|
			PACKED
		  }x;
our $Modifier;
our $Inline	= qr{inline|NOINLINE};
our $Member	= qr{->$Ident|\.$Ident|\[[^]]*\]};
our $Lval	= qr{$Ident(?:$Member)*};

our $Int_type	= qr{(?i)llu|ull|ll|lu|ul|l|u};
our $Binary	= qr{(?i)0b[01]+$Int_type?};
our $Hex	= qr{(?i)0x[0-9a-f]+$Int_type?};
our $Int	= qr{[0-9]+$Int_type?};
our $Octal	= qr{0[0-7]+$Int_type?};
our $String	= qr{(?:\b[Lu])?"[X\t]*"};
our $Float_hex	= qr{(?i)0x[0-9a-f]+p-?[0-9]+[fl]?};
our $Float_dec	= qr{(?i)(?:[0-9]+\.[0-9]*|[0-9]*\.[0-9]+)(?:e-?[0-9]+)?[fl]?};
our $Float_int	= qr{(?i)[0-9]+e-?[0-9]+[fl]?};
our $Float	= qr{$Float_hex|$Float_dec|$Float_int};
our $Constant	= qr{$Float|$Binary|$Octal|$Hex|$Int};
our $Assignment	= qr{\*\=|/=|%=|\+=|-=|<<=|>>=|&=|\^=|\|=|=};
our $Compare    = qr{<=|>=|==|!=|<|(?<!-)>};
our $Arithmetic = qr{\+|-|\*|\/|%};
our $Operators	= qr{
			<=|>=|==|!=|
			=>|->|<<|>>|<|>|!|~|
			&&|\|\||,|\^|\+\+|--|&|\||$Arithmetic
		  }x;

our $c90_Keywords = qr{do|for|while|if|else|return|goto|continue|switch|default|case|break}x;

our $BasicType;
our $NonptrType;
our $NonptrTypeMisordered;
our $Type;
our $TypeMisordered;
our $Declare;
our $DeclareMisordered;

our $NON_ASCII_UTF8	= qr{
	[\xC2-\xDF][\x80-\xBF]               # non-overlong 2-byte
	|  \xE0[\xA0-\xBF][\x80-\xBF]        # excluding overlongs
	| [\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}  # straight 3-byte
	|  \xED[\x80-\x9F][\x80-\xBF]        # excluding surrogates
	|  \xF0[\x90-\xBF][\x80-\xBF]{2}     # planes 1-3
	| [\xF1-\xF3][\x80-\xBF]{3}          # planes 4-15
	|  \xF4[\x80-\x8F][\x80-\xBF]{2}     # plane 16
}x;

our $UTF8	= qr{
	[\x09\x0A\x0D\x20-\x7E]              # ASCII
	| $NON_ASCII_UTF8
}x;

# Skip all checks for the following paths.
our $skipPaths = qr{(?x:
	test\/static\/corpus\/
)};

# Skip C/C++ source code checks for the following paths.
our $skipSrcPaths = qr{(?x:
	src\/lib\/tzcode\/
)};

our $typeMacros = qr{(?x:
	LIGHT
)};

our $typeTypedefs = qr{(?x:
	(?:__)?(?:[us]_?)?int_?(?:8|16|32|64)_t|
	u_(?:char|short|int|long)|
	ev_loop|
	lua_State
)};

our $logFunctions = qr{(?x:
	say_file_line|
	(?:log_)?say(?:_error|_crit|_warn|_info|_verbose|_debug|_syserror|)(?:_ratelimited)?|
	panic(?:|_status|_syserror|)
)};

our $allocFunctions = qr{(?x:
	(?:x)?(?:c|re|m)alloc|
	(?:i|o)buf_(?:alloc|reserve)|
	(?:ls)?region_(?:aligned_)?(?:alloc|reserve)|
	region_join|
	smalloc|
	mempool_alloc
)};

our $signature_tags = qr{(?xi:
	Signed-off-by:|
	Co-authored-by:|
	Co-developed-by:|
	Acked-by:|
	Tested-by:|
	Reviewed-by:|
	Reported-by:|
	Suggested-by:|
	To:|
	Cc:
)};

our $custom_tags = qr{(?x:
	NO_DOC|
	NO_TEST|
	NO_CHANGELOG
)};

sub edit_distance_min {
	my (@arr) = @_;
	my $len = scalar @arr;
	if ((scalar @arr) < 1) {
		# if underflow, return
		return;
	}
	my $min = $arr[0];
	for my $i (0 .. ($len-1)) {
		if ($arr[$i] < $min) {
			$min = $arr[$i];
		}
	}
	return $min;
}

sub get_edit_distance {
	my ($str1, $str2) = @_;
	$str1 = lc($str1);
	$str2 = lc($str2);
	$str1 =~ s/-//g;
	$str2 =~ s/-//g;
	my $len1 = length($str1);
	my $len2 = length($str2);
	# two dimensional array storing minimum edit distance
	my @distance;
	for my $i (0 .. $len1) {
		for my $j (0 .. $len2) {
			if ($i == 0) {
				$distance[$i][$j] = $j;
			} elsif ($j == 0) {
				$distance[$i][$j] = $i;
			} elsif (substr($str1, $i-1, 1) eq substr($str2, $j-1, 1)) {
				$distance[$i][$j] = $distance[$i - 1][$j - 1];
			} else {
				my $dist1 = $distance[$i][$j - 1]; #insert distance
				my $dist2 = $distance[$i - 1][$j]; # remove
				my $dist3 = $distance[$i - 1][$j - 1]; #replace
				$distance[$i][$j] = 1 + edit_distance_min($dist1, $dist2, $dist3);
			}
		}
	}
	return $distance[$len1][$len2];
}

sub find_standard_signature {
	my ($sign_off) = @_;
	my @standard_signature_tags = (
		'Signed-off-by:', 'Co-developed-by:', 'Acked-by:', 'Tested-by:',
		'Reviewed-by:', 'Reported-by:', 'Suggested-by:'
	);
	foreach my $signature (@standard_signature_tags) {
		return $signature if (get_edit_distance($sign_off, $signature) <= 2);
	}

	return "";
}

our @typeListMisordered = (
	qr{char\s+(?:un)?signed},
	qr{int\s+(?:(?:un)?signed\s+)?short\s},
	qr{int\s+short(?:\s+(?:un)?signed)},
	qr{short\s+int(?:\s+(?:un)?signed)},
	qr{(?:un)?signed\s+int\s+short},
	qr{short\s+(?:un)?signed},
	qr{long\s+int\s+(?:un)?signed},
	qr{int\s+long\s+(?:un)?signed},
	qr{long\s+(?:un)?signed\s+int},
	qr{int\s+(?:un)?signed\s+long},
	qr{int\s+(?:un)?signed},
	qr{int\s+long\s+long\s+(?:un)?signed},
	qr{long\s+long\s+int\s+(?:un)?signed},
	qr{long\s+long\s+(?:un)?signed\s+int},
	qr{long\s+long\s+(?:un)?signed},
	qr{long\s+(?:un)?signed},
);

our @typeList = (
	qr{void},
	qr{(?:(?:un)?signed\s+)?char},
	qr{(?:(?:un)?signed\s+)?short\s+int},
	qr{(?:(?:un)?signed\s+)?short},
	qr{(?:(?:un)?signed\s+)?int},
	qr{(?:(?:un)?signed\s+)?long\s+int},
	qr{(?:(?:un)?signed\s+)?long\s+long\s+int},
	qr{(?:(?:un)?signed\s+)?long\s+long},
	qr{(?:(?:un)?signed\s+)?long},
	qr{(?:un)?signed},
	qr{float},
	qr{double},
	qr{bool},
	qr{struct\s+$Ident},
	qr{union\s+$Ident},
	qr{enum\s+$Ident},
	qr{${Ident}_t},
	qr{${Ident}_f},
	qr{${Ident}_fn},
	qr{${Ident}_cb},
	@typeListMisordered,
);

our $C90_int_types = qr{(?x:
	long\s+long\s+int\s+(?:un)?signed|
	long\s+long\s+(?:un)?signed\s+int|
	long\s+long\s+(?:un)?signed|
	(?:(?:un)?signed\s+)?long\s+long\s+int|
	(?:(?:un)?signed\s+)?long\s+long|
	int\s+long\s+long\s+(?:un)?signed|
	int\s+(?:(?:un)?signed\s+)?long\s+long|

	long\s+int\s+(?:un)?signed|
	long\s+(?:un)?signed\s+int|
	long\s+(?:un)?signed|
	(?:(?:un)?signed\s+)?long\s+int|
	(?:(?:un)?signed\s+)?long|
	int\s+long\s+(?:un)?signed|
	int\s+(?:(?:un)?signed\s+)?long|

	int\s+(?:un)?signed|
	(?:(?:un)?signed\s+)?int
)};

our $CXX_cast_operators = qr{(?x:
	(?:const|dynamic|reinterpret|static)_cast
)};

our @typeListFile = ();

# We don't have any predefined modifiers yet, but the modifier list can't be
# empty so we add an unmatchable expression to it.
our @modifierList = (
	qr{\b\B},
);
our @modifierListFile = ();

our @mode_permission_funcs = (
	["creat", 2],
	["open", 3],
	["openat", 4],
	["mkdir", 2],
	["mkdirat", 3],
	["chmod", 2],
	["fchmod", 2],
	["fchmodat", 3],
	["coio_file_open", 3],
	["coio_mkdir", 2],
	["coio_chmod", 2],
);

my $word_pattern = '\b[A-Z]?[a-z]{2,}\b';

#Create a search pattern for all these functions to speed up a loop below
our $mode_perms_search = "";
foreach my $entry (@mode_permission_funcs) {
	$mode_perms_search .= '|' if ($mode_perms_search ne "");
	$mode_perms_search .= $entry->[0];
}
$mode_perms_search = "(?:${mode_perms_search})";

# Load common spelling mistakes and build regular expression list.
my $misspellings;
my %spelling_fix;

if (open(my $spelling, '<', $spelling_file)) {
	while (<$spelling>) {
		my $line = $_;

		$line =~ s/\s*\n?$//g;
		$line =~ s/^\s*//g;

		next if ($line =~ m/^\s*#/);
		next if ($line =~ m/^\s*$/);

		my ($suspect, $fix) = split(/\|\|/, $line);

		$spelling_fix{$suspect} = $fix;
	}
	close($spelling);
} else {
	warn "No typos will be found - file '$spelling_file': $!\n";
}

if ($codespell) {
	if (open(my $spelling, '<', $codespellfile)) {
		while (<$spelling>) {
			my $line = $_;

			$line =~ s/\s*\n?$//g;
			$line =~ s/^\s*//g;

			next if ($line =~ m/^\s*#/);
			next if ($line =~ m/^\s*$/);
			next if ($line =~ m/, disabled/i);

			$line =~ s/,.*$//;

			my ($suspect, $fix) = split(/->/, $line);

			$spelling_fix{$suspect} = $fix;
		}
		close($spelling);
	} else {
		warn "No codespell typos will be found - file '$codespellfile': $!\n";
	}
}

$misspellings = join("|", sort keys %spelling_fix) if keys %spelling_fix;

sub read_words {
	my ($wordsRef, $file) = @_;

	if (open(my $words, '<', $file)) {
		while (<$words>) {
			my $line = $_;

			$line =~ s/\s*\n?$//g;
			$line =~ s/^\s*//g;

			next if ($line =~ m/^\s*#/);
			next if ($line =~ m/^\s*$/);
			if ($line =~ /\s/) {
				print("$file: '$line' invalid - ignored\n");
				next;
			}

			$$wordsRef .= '|' if (defined $$wordsRef);
			$$wordsRef .= $line;
		}
		close($file);
		return 1;
	}

	return 0;
}

if (defined($typedefsfile)) {
	my $typeOtherTypedefs;
	read_words(\$typeOtherTypedefs, $typedefsfile)
	    or warn "No additional types will be considered - file '$typedefsfile': $!\n";
	$typeTypedefs .= '|' . $typeOtherTypedefs if (defined $typeOtherTypedefs);
}

sub build_types {
	my $mods = "(?x:  \n" . join("|\n  ", (@modifierList, @modifierListFile)) . "\n)";
	my $all = "(?x:  \n" . join("|\n  ", (@typeList, @typeListFile)) . "\n)";
	my $Misordered = "(?x:  \n" . join("|\n  ", @typeListMisordered) . "\n)";
	$Modifier	= qr{(?:$Attribute|$mods)};
	$BasicType	= qr{
				(?:$typeTypedefs\b)|
				(?:${all}\b)
		}x;
	$NonptrType	= qr{
			(?:$Modifier\s+|const\s+)*
			(?:
				(?:typeof|__typeof__|(?:struct\s+)?$typeMacros)\s*\([^\)]*\)|
				(?:$typeTypedefs\b)|
				(?:${all}\b)
			)
			(?:\s+$Modifier|\s+const)*
		  }x;
	$NonptrTypeMisordered	= qr{
			(?:$Modifier\s+|const\s+)*
			(?:
				(?:${Misordered}\b)
			)
			(?:\s+$Modifier|\s+const)*
		  }x;
	$Type	= qr{
			$NonptrType
			(?:(?:\s|[\*\&]|\[\])+\s*const|(?:\s|[\*\&]\s*(?:const\s*)?|\[\])+|(?:\s*\[\s*\])+){0,4}
			(?:\s+$Inline|\s+$Modifier)*
		  }x;
	$TypeMisordered	= qr{
			$NonptrTypeMisordered
			(?:(?:\s|[\*\&]|\[\])+\s*const|(?:\s|[\*\&]\s*(?:const\s*)?|\[\])+|(?:\s*\[\s*\])+){0,4}
			(?:\s+$Inline|\s+$Modifier)*
		  }x;
	$Declare	= qr{(?:$Storage\s+(?:$Inline\s+)?)?$Type};
	$DeclareMisordered	= qr{(?:$Storage\s+(?:$Inline\s+)?)?$TypeMisordered};
}
build_types();

our $Typecast	= qr{\s*(\(\s*$NonptrType\s*\)){0,1}\s*};

# Using $balanced_parens, $LvalOrFunc, or $FuncArg
# requires at least perl version v5.10.0
# Any use must be runtime checked with $^V

our $balanced_parens = qr/(\((?:[^\(\)]++|(?-1))*\))/;
our $LvalOrFunc	= qr{((?:[\&\*]\s*)?$Lval)\s*($balanced_parens{0,1})\s*};
our $FuncArg = qr{$Typecast{0,1}($LvalOrFunc|$Constant|$String)};

our %allow_repeated_words = (
	add => '',
	added => '',
	bad => '',
	be => '',
);

sub deparenthesize {
	my ($string) = @_;
	return "" if (!defined($string));

	while ($string =~ /^\s*\(.*\)\s*$/) {
		$string =~ s@^\s*\(\s*@@;
		$string =~ s@\s*\)\s*$@@;
	}

	$string =~ s@\s+@ @g;

	return $string;
}

sub git_is_single_file {
	my ($filename) = @_;

	return 0 if ((which("git") eq "") || !(-e "$gitroot"));

	my $output = `${git_command} ls-files -- $filename 2>/dev/null`;
	my $count = $output =~ tr/\n//;
	return $count eq 1 && $output =~ m{^${filename}$};
}

sub git_commit_info {
	my ($commit, $id, $desc) = @_;

	return ($id, $desc) if ((which("git") eq "") || !(-e "$gitroot"));

	my $output = `${git_command} log --no-color --format='%H %s' -1 $commit 2>&1`;
	$output =~ s/^\s*//gm;
	my @lines = split("\n", $output);

	return ($id, $desc) if ($#lines < 0);

	if ($lines[0] =~ /^error: short SHA1 $commit is ambiguous/) {
# Maybe one day convert this block of bash into something that returns
# all matching commit ids, but it's very slow...
#
#		echo "checking commits $1..."
#		git rev-list --remotes | grep -i "^$1" |
#		while read line ; do
#		    git log --format='%H %s' -1 $line |
#		    echo "commit $(cut -c 1-12,41-)"
#		done
	} elsif ($lines[0] =~ /^fatal: ambiguous argument '$commit': unknown revision or path not in the working tree\./ ||
		 $lines[0] =~ /^fatal: bad object $commit/) {
		$id = undef;
	} else {
		$id = substr($lines[0], 0, 12);
		$desc = substr($lines[0], 41);
	}

	return ($id, $desc);
}

$chk_signoff = 0 if ($file);

my @rawlines = ();
my @lines = ();

# If input is git commits, extract all commits from the commit expressions.
# For example, HEAD-3 means we need check 'HEAD, HEAD~1, HEAD~2'.
die "$P: No git repository found\n" if ($git && !-e "$gitroot");

if ($git) {
	my @commits = ();
	foreach my $commit_expr (@ARGV) {
		my $git_range;
		if ($commit_expr =~ m/^(.*)-(\d+)$/) {
			$git_range = "-$2 $1";
		} elsif ($commit_expr =~ m/\.\./) {
			$git_range = "$commit_expr";
		} else {
			$git_range = "-1 $commit_expr";
		}
		my $lines = `${git_command} log --no-color --no-merges --pretty=format:'%H %s' $git_range`;
		foreach my $line (split(/\n/, $lines)) {
			$line =~ /^([0-9a-fA-F]{40,40}) (.*)$/;
			next if (!defined($1) || !defined($2));
			my $sha1 = $1;
			my $subject = $2;
			unshift(@commits, $sha1);
			$git_commits{$sha1} = $subject;
		}
	}
	die "$P: no git commits after extraction!\n" if (@commits == 0);
	@ARGV = @commits;
}

my $vname;
for my $filename (@ARGV) {
	my $FILE;
	my $is_git_file = git_is_single_file($filename);
	my $oldfile = $file;
	$file = 1 if ($is_git_file);
	if ($git) {
		open($FILE, '-|', "git format-patch --no-stat -M --stdout -1 $filename") ||
			die "$P: $filename: git format-patch failed - $!\n";
	} elsif ($file) {
		open($FILE, '-|', "diff -u /dev/null $filename") ||
			die "$P: $filename: diff failed - $!\n";
	} elsif ($filename eq '-') {
		open($FILE, '<&STDIN');
	} else {
		open($FILE, '<', "$filename") ||
			die "$P: $filename: open failed - $!\n";
	}
	if ($filename eq '-') {
		$vname = 'Your patch';
	} elsif ($git) {
		$vname = "Commit " . substr($filename, 0, 12) . ' ("' . $git_commits{$filename} . '")';
	} else {
		$vname = $filename;
	}
	while (<$FILE>) {
		chomp;
		push(@rawlines, $_);
		$vname = qq("$1") if ($filename eq '-' && $_ =~ m/^Subject:\s+(.+)/i);
	}
	close($FILE);

	if ($#ARGV > 0 && $quiet == 0) {
		print '-' x length($vname) . "\n";
		print "$vname\n";
		print '-' x length($vname) . "\n";
	}

	if (!process($filename)) {
		$exit = 1;
	}
	@rawlines = ();
	@lines = ();
	@modifierListFile = ();
	@typeListFile = ();
	build_types();
	$file = $oldfile if ($is_git_file);
}

if (!$quiet) {
	hash_show_words(\%use_type, "Used");
	hash_show_words(\%ignore_type, "Ignored");

	if ($exit) {
		print << "EOM"

NOTE: If any of the errors are false positives, please file a bug at
      https://github.com/tarantool/checkpatch/issues
EOM
	}
}

exit($exit);

sub parse_email {
	my ($formatted_email) = @_;

	my $name = "";
	my $quoted = "";
	my $name_comment = "";
	my $address = "";
	my $comment = "";

	if ($formatted_email =~ /^(.*)<(\S+\@\S+)>(.*)$/) {
		$name = $1;
		$address = $2;
		$comment = $3 if defined $3;
	} elsif ($formatted_email =~ /^\s*<(\S+\@\S+)>(.*)$/) {
		$address = $1;
		$comment = $2 if defined $2;
	} elsif ($formatted_email =~ /(\S+\@\S+)(.*)$/) {
		$address = $1;
		$comment = $2 if defined $2;
		$formatted_email =~ s/\Q$address\E.*$//;
		$name = $formatted_email;
		$name = trim($name);
		$name =~ s/^\"|\"$//g;
		# If there's a name left after stripping spaces and
		# leading quotes, and the address doesn't have both
		# leading and trailing angle brackets, the address
		# is invalid. ie:
		#   "joe smith joe@smith.com" bad
		#   "joe smith <joe@smith.com" bad
		if ($name ne "" && $address !~ /^<[^>]+>$/) {
			$name = "";
			$address = "";
			$comment = "";
		}
	}

	# Extract comments from names excluding quoted parts
	# "John D. (Doe)" - Do not extract
	if ($name =~ s/\"(.+)\"//) {
		$quoted = $1;
	}
	while ($name =~ s/\s*($balanced_parens)\s*/ /) {
		$name_comment .= trim($1);
	}
	$name =~ s/^[ \"]+|[ \"]+$//g;
	$name = trim("$quoted $name");

	$address = trim($address);
	$address =~ s/^\<|\>$//g;
	$comment = trim($comment);

	if ($name =~ /[^\w \-]/i) { ##has "must quote" chars
		$name =~ s/(?<!\\)"/\\"/g; ##escape quotes
		$name = "\"$name\"";
	}

	return ($name, $name_comment, $address, $comment);
}

sub format_email {
	my ($name, $name_comment, $address, $comment) = @_;

	my $formatted_email;

	$name =~ s/^[ \"]+|[ \"]+$//g;
	$address = trim($address);
	$address =~ s/(?:\.|\,|\")+$//; ##trailing commas, dots or quotes

	if ($name =~ /[^\w \-]/i) { ##has "must quote" chars
		$name =~ s/(?<!\\)"/\\"/g; ##escape quotes
		$name = "\"$name\"";
	}

	$name_comment = trim($name_comment);
	$name_comment = " $name_comment" if ($name_comment ne "");
	$comment = trim($comment);
	$comment = " $comment" if ($comment ne "");

	if ("$name" eq "") {
		$formatted_email = "$address";
	} else {
		$formatted_email = "$name$name_comment <$address>";
	}
	$formatted_email .= "$comment";
	return $formatted_email;
}

sub reformat_email {
	my ($email) = @_;

	my ($email_name, $name_comment, $email_address, $comment) = parse_email($email);
	return format_email($email_name, $name_comment, $email_address, $comment);
}

sub same_email_addresses {
	my ($email1, $email2) = @_;

	my ($email1_name, $name1_comment, $email1_address, $comment1) = parse_email($email1);
	my ($email2_name, $name2_comment, $email2_address, $comment2) = parse_email($email2);

	return $email1_name eq $email2_name &&
	       $email1_address eq $email2_address &&
	       $name1_comment eq $name2_comment &&
	       $comment1 eq $comment2;
}

sub which {
	my ($bin) = @_;

	foreach my $path (split(/:/, $ENV{PATH})) {
		if (-e "$path/$bin") {
			return "$path/$bin";
		}
	}

	return "";
}

sub which_conf {
	my ($conf) = @_;

	foreach my $path (split(/:/, ".:$ENV{HOME}:.scripts")) {
		if (-e "$path/$conf") {
			return "$path/$conf";
		}
	}

	return "";
}

sub expand_tabs {
	my ($str) = @_;

	my $res = '';
	my $n = 0;
	for my $c (split(//, $str)) {
		if ($c eq "\t") {
			$res .= ' ';
			$n++;
			for (; ($n % $tabsize) != 0; $n++) {
				$res .= ' ';
			}
			next;
		}
		$res .= $c;
		$n++;
	}

	return $res;
}
sub copy_spacing {
	(my $res = shift) =~ tr/\t/ /c;
	return $res;
}

sub line_stats {
	my ($line) = @_;
	utf8::decode($line);

	# Drop the diff line leader and expand tabs
	$line =~ s/^.//;
	$line = expand_tabs($line);

	# Pick the indent from the front of the line.
	my ($white) = ($line =~ /^(\s*)/);

	return (length($line), length($white));
}

my $sanitise_quote = '';

sub sanitise_line_reset {
	my ($in_comment) = @_;

	if ($in_comment) {
		$sanitise_quote = '*/';
	} else {
		$sanitise_quote = '';
	}
}
sub sanitise_line {
	my ($line) = @_;

	my $res = '';
	my $l = '';

	my $qlen = 0;
	my $off = 0;
	my $c;

	# Always copy over the diff marker.
	$res = substr($line, 0, 1);

	for ($off = 1; $off < length($line); $off++) {
		$c = substr($line, $off, 1);

		# Comments we are whacking completely including the begin
		# and end, all to $;.
		if ($sanitise_quote eq '' && substr($line, $off, 2) eq '/*') {
			$sanitise_quote = '*/';

			substr($res, $off, 2, "$;$;");
			$off++;
			next;
		}
		if ($sanitise_quote eq '*/' && substr($line, $off, 2) eq '*/') {
			$sanitise_quote = '';
			substr($res, $off, 2, "$;$;");
			$off++;
			next;
		}
		if ($sanitise_quote eq '' && substr($line, $off, 2) eq '//') {
			$sanitise_quote = '//';

			substr($res, $off, 2, $sanitise_quote);
			$off++;
			next;
		}

		# A \ in a string means ignore the next character.
		if (($sanitise_quote eq "'" || $sanitise_quote eq '"') &&
		    $c eq "\\") {
			substr($res, $off, 2, 'XX');
			$off++;
			next;
		}
		# Regular quotes.
		if ($c eq "'" || $c eq '"') {
			if ($sanitise_quote eq '') {
				$sanitise_quote = $c;

				substr($res, $off, 1, $c);
				next;
			} elsif ($sanitise_quote eq $c) {
				$sanitise_quote = '';
			}
		}

		#print "c<$c> SQ<$sanitise_quote>\n";
		if ($off != 0 && $sanitise_quote eq '*/') {
			substr($res, $off, 1, $;);
		} elsif ($off != 0 && $sanitise_quote eq '//') {
			substr($res, $off, 1, $;);
		} elsif ($off != 0 && $sanitise_quote) {
			substr($res, $off, 1, 'X');
		} else {
			substr($res, $off, 1, $c);
		}
	}

	if ($sanitise_quote eq '//') {
		$sanitise_quote = '';
	}

	# The pathname on a #include may be surrounded by '<' and '>'.
	if ($res =~ /^.\s*\#\s*include\s+\<(.*)\>/) {
		my $clean = 'X' x length($1);
		$res =~ s@\<.*\>@<$clean>@;

	# The whole of a #error is a string.
	} elsif ($res =~ /^.\s*\#\s*(?:error|warning)\s+(.*)\b/) {
		my $clean = 'X' x length($1);
		$res =~ s@(\#\s*(?:error|warning)\s+).*@$1$clean@;
	}

	return $res;
}

sub get_quoted_string {
	my ($line, $rawline) = @_;

	return "" if (!defined($line) || !defined($rawline));
	return "" if ($line !~ m/($String)/g);
	return substr($rawline, $-[0], $+[0] - $-[0]);
}

sub ctx_statement_block {
	my ($linenr, $remain, $off) = @_;
	my $line = $linenr - 1;
	my $blk = '';
	my $soff = $off;
	my $coff = $off - 1;
	my $coff_set = 0;

	my $loff = 0;

	my $type = '';
	my $level = 0;
	my @stack = ();
	my $p;
	my $c;
	my $len = 0;

	my $remainder;
	while (1) {
		@stack = (['', 0]) if ($#stack == -1);

		#warn "CSB: blk<$blk> remain<$remain>\n";
		# If we are about to drop off the end, pull in more
		# context.
		if ($off >= $len) {
			for (; $remain > 0; $line++) {
				last if (!defined $lines[$line]);
				next if ($lines[$line] =~ /^-/);
				$remain--;
				$loff = $len;
				$blk .= $lines[$line] . "\n";
				$len = length($blk);
				$line++;
				last;
			}
			# Bail if there is no further context.
			#warn "CSB: blk<$blk> off<$off> len<$len>\n";
			if ($off >= $len) {
				last;
			}
			if ($level == 0 && substr($blk, $off) =~ /^.\s*#\s*define/) {
				$level++;
				$type = '#';
			}
		}
		$p = $c;
		$c = substr($blk, $off, 1);
		$remainder = substr($blk, $off);

		#warn "CSB: c<$c> type<$type> level<$level> remainder<$remainder> coff_set<$coff_set>\n";

		# Handle nested #if/#else.
		if ($remainder =~ /^#\s*(?:ifndef|ifdef|if)\s/) {
			push(@stack, [ $type, $level ]);
		} elsif ($remainder =~ /^#\s*(?:else|elif)\b/) {
			($type, $level) = @{$stack[$#stack - 1]};
		} elsif ($remainder =~ /^#\s*endif\b/) {
			($type, $level) = @{pop(@stack)};
		}

		# Statement ends at the ';' or a close '}' at the
		# outermost level.
		if ($level == 0 && $c eq ';') {
			last;
		}

		# An else is really a conditional as long as its not else if
		if ($level == 0 && $coff_set == 0 &&
				(!defined($p) || $p =~ /(?:\s|\}|\+)/) &&
				$remainder =~ /^(else)(?:\s|{)/ &&
				$remainder !~ /^else\s+if\b/) {
			$coff = $off + length($1) - 1;
			$coff_set = 1;
			#warn "CSB: mark coff<$coff> soff<$soff> 1<$1>\n";
			#warn "[" . substr($blk, $soff, $coff - $soff + 1) . "]\n";
		}

		if (($type eq '' || $type eq '(') && $c eq '(') {
			$level++;
			$type = '(';
		}
		if ($type eq '(' && $c eq ')') {
			$level--;
			$type = ($level != 0)? '(' : '';

			if ($level == 0 && $coff < $soff) {
				$coff = $off;
				$coff_set = 1;
				#warn "CSB: mark coff<$coff>\n";
			}
		}
		if (($type eq '' || $type eq '{') && $c eq '{') {
			$level++;
			$type = '{';
		}
		if ($type eq '{' && $c eq '}') {
			$level--;
			$type = ($level != 0)? '{' : '';

			if ($level == 0) {
				if (substr($blk, $off + 1, 1) eq ';') {
					$off++;
				}
				last;
			}
		}
		# Preprocessor commands end at the newline unless escaped.
		if ($type eq '#' && $c eq "\n" && $p ne "\\") {
			$level--;
			$type = '';
			$off++;
			last;
		}
		$off++;
	}
	# We are truly at the end, so shuffle to the next line.
	if ($off == $len) {
		$loff = $len + 1;
		$line++;
		$remain--;
	}

	my $statement = substr($blk, $soff, $off - $soff + 1);
	my $condition = substr($blk, $soff, $coff - $soff + 1);

	#warn "STATEMENT<$statement>\n";
	#warn "CONDITION<$condition>\n";

	#print "coff<$coff> soff<$off> loff<$loff>\n";

	return ($statement, $condition,
			$line, $remain + 1, $off - $loff + 1, $level);
}

sub statement_lines {
	my ($stmt) = @_;

	# Strip the diff line prefixes and rip blank lines at start and end.
	$stmt =~ s/(^|\n)./$1/g;
	$stmt =~ s/^\s*//;
	$stmt =~ s/\s*$//;

	my @stmt_lines = ($stmt =~ /\n/g);

	return $#stmt_lines + 2;
}

sub statement_rawlines {
	my ($stmt) = @_;

	my @stmt_lines = ($stmt =~ /\n/g);

	return $#stmt_lines + 2;
}

sub statement_block_size {
	my ($stmt) = @_;

	$stmt =~ s/(^|\n)./$1/g;
	$stmt =~ s/^\s*{//;
	$stmt =~ s/}\s*$//;
	$stmt =~ s/^\s*//;
	$stmt =~ s/\s*$//;

	my @stmt_lines = ($stmt =~ /\n/g);
	my @stmt_statements = ($stmt =~ /;/g);

	my $stmt_lines = $#stmt_lines + 2;
	my $stmt_statements = $#stmt_statements + 1;

	if ($stmt_lines > $stmt_statements) {
		return $stmt_lines;
	} else {
		return $stmt_statements;
	}
}

sub ctx_statement_full {
	my ($linenr, $remain, $off) = @_;
	my ($statement, $condition, $level);

	my (@chunks);

	# Grab the first conditional/block pair.
	($statement, $condition, $linenr, $remain, $off, $level) =
				ctx_statement_block($linenr, $remain, $off);
	#print "F: c<$condition> s<$statement> remain<$remain>\n";
	push(@chunks, [ $condition, $statement ]);
	if (!($remain > 0 && $condition =~ /^\s*(?:\n[+-])?\s*(?:if|else|do)\b/s)) {
		return ($level, $linenr, @chunks);
	}

	# Pull in the following conditional/block pairs and see if they
	# could continue the statement.
	for (;;) {
		($statement, $condition, $linenr, $remain, $off, $level) =
				ctx_statement_block($linenr, $remain, $off);
		#print "C: c<$condition> s<$statement> remain<$remain>\n";
		last if (!($remain > 0 && $condition =~ /^(?:\s*\n[+-])*\s*(?:else|do)\b/s));
		#print "C: push\n";
		push(@chunks, [ $condition, $statement ]);
	}

	return ($level, $linenr, @chunks);
}

sub ctx_block_get {
	my ($linenr, $remain, $outer, $open, $close, $off) = @_;
	my $line;
	my $start = $linenr - 1;
	my $blk = '';
	my @o;
	my @c;
	my @res = ();

	my $level = 0;
	my @stack = ($level);
	for ($line = $start; $remain > 0; $line++) {
		next if ($rawlines[$line] =~ /^-/);
		$remain--;

		$blk .= $rawlines[$line];

		# Handle nested #if/#else.
		if ($lines[$line] =~ /^.\s*#\s*(?:ifndef|ifdef|if)\s/) {
			push(@stack, $level);
		} elsif ($lines[$line] =~ /^.\s*#\s*(?:else|elif)\b/) {
			$level = $stack[$#stack - 1];
		} elsif ($lines[$line] =~ /^.\s*#\s*endif\b/) {
			$level = pop(@stack);
		}

		foreach my $c (split(//, $lines[$line])) {
			##print "C<$c>L<$level><$open$close>O<$off>\n";
			if ($off > 0) {
				$off--;
				next;
			}

			if ($c eq $close && $level > 0) {
				$level--;
				last if ($level == 0);
			} elsif ($c eq $open) {
				$level++;
			}
		}

		if (!$outer || $level <= 1) {
			push(@res, $rawlines[$line]);
		}

		last if ($level == 0);
	}

	return ($level, @res);
}
sub ctx_block_outer {
	my ($linenr, $remain) = @_;

	my ($level, @r) = ctx_block_get($linenr, $remain, 1, '{', '}', 0);
	return @r;
}
sub ctx_block {
	my ($linenr, $remain) = @_;

	my ($level, @r) = ctx_block_get($linenr, $remain, 0, '{', '}', 0);
	return @r;
}
sub ctx_statement {
	my ($linenr, $remain, $off) = @_;

	my ($level, @r) = ctx_block_get($linenr, $remain, 0, '(', ')', $off);
	return @r;
}
sub ctx_block_level {
	my ($linenr, $remain) = @_;

	return ctx_block_get($linenr, $remain, 0, '{', '}', 0);
}
sub ctx_statement_level {
	my ($linenr, $remain, $off) = @_;

	return ctx_block_get($linenr, $remain, 0, '(', ')', $off);
}

sub ctx_locate_comment {
	my ($first_line, $end_line) = @_;

	# If c99 comment on the current line, or the line before or after
	my ($current_comment) = ($rawlines[$end_line - 1] =~ m@^\+.*(//.*$)@);
	return $current_comment if (defined $current_comment);
	($current_comment) = ($rawlines[$end_line - 2] =~ m@^[\+ ].*(//.*$)@);
	return $current_comment if (defined $current_comment);
	($current_comment) = ($rawlines[$end_line] =~ m@^[\+ ].*(//.*$)@);
	return $current_comment if (defined $current_comment);

	# Catch a comment on the end of the line itself.
	($current_comment) = ($rawlines[$end_line - 1] =~ m@.*(/\*.*\*/)\s*(?:\\\s*)?$@);
	return $current_comment if (defined $current_comment);

	# Look through the context and try and figure out if there is a
	# comment.
	my $in_comment = 0;
	$current_comment = '';
	for (my $linenr = $first_line; $linenr < $end_line; $linenr++) {
		my $line = $rawlines[$linenr - 1];
		# ignore deleted lines
		next if ($line =~ /^-/);
		#warn "           $line\n";
		if ($linenr == $first_line and $line =~ m@^.\s*\*@) {
			$in_comment = 1;
		}
		if ($line =~ m@/\*@) {
			$in_comment = 1;
		}
		if (!$in_comment && $current_comment ne '') {
			$current_comment = '';
		}
		$current_comment .= $line . "\n" if ($in_comment);
		if ($line =~ m@\*/@) {
			$in_comment = 0;
		}
	}

	chomp($current_comment);
	return($current_comment);
}
sub ctx_has_comment {
	my ($first_line, $end_line) = @_;
	my $cmt = ctx_locate_comment($first_line, $end_line);

	##print "LINE: $rawlines[$end_line - 1 ]\n";
	##print "CMMT: $cmt\n";

	return ($cmt ne '');
}

sub raw_line {
	my ($linenr, $cnt) = @_;

	my $offset = $linenr - 1;
	$cnt++;

	my $line;
	while ($cnt) {
		$line = $rawlines[$offset++];
		next if (defined($line) && $line =~ /^-/);
		$cnt--;
	}

	return $line;
}

sub get_stat_real {
	my ($linenr, $lc) = @_;

	my $stat_real = raw_line($linenr, 0);
	for (my $count = $linenr + 1; $count <= $lc; $count++) {
		$stat_real = $stat_real . "\n" . raw_line($count, 0);
	}

	return $stat_real;
}

sub get_stat_here {
	my ($linenr, $cnt, $here) = @_;

	my $herectx = $here . "\n";
	for (my $n = 0; $n < $cnt; $n++) {
		$herectx .= raw_line($linenr, $n) . "\n";
	}

	return $herectx;
}

sub cat_vet {
	my ($vet) = @_;
	my ($res, $coded);

	$res = '';
	while ($vet =~ /([^[:cntrl:]]*)([[:cntrl:]]|$)/g) {
		$res .= $1;
		if ($2 ne '') {
			$coded = sprintf("^%c", unpack('C', $2) + 64);
			$res .= $coded;
		}
	}
	$res =~ s/$/\$/;

	return $res;
}

my $av_preprocessor = 0;
my $av_pending;
my @av_paren_type;
my $av_pend_colon;

sub annotate_reset {
	$av_preprocessor = 0;
	$av_pending = '_';
	@av_paren_type = ('E');
	$av_pend_colon = 'O';
}

sub annotate_values {
	my ($stream, $type) = @_;

	my $res;
	my $var = '_' x length($stream);
	my $cur = $stream;

	print "$stream\n" if ($dbg_values > 1);

	while (length($cur)) {
		@av_paren_type = ('E') if ($#av_paren_type < 0);
		print " <" . join('', @av_paren_type) .
				"> <$type> <$av_pending>" if ($dbg_values > 1);
		if ($cur =~ /^(\s+)/o) {
			print "WS($1)\n" if ($dbg_values > 1);
			if ($1 =~ /\n/ && $av_preprocessor) {
				$type = pop(@av_paren_type);
				$av_preprocessor = 0;
			}

		} elsif (($cur =~ /^(\(\s*$Type\s*)\)/ ||
			  $cur =~ /^($CXX_cast_operators\s*<\s*$Type\s*)>/ ) && $av_pending eq '_') {
			print "CAST($1)\n" if ($dbg_values > 1);
			push(@av_paren_type, $type);
			$type = 'c';

		} elsif ($cur =~ /^($Type)\s*(?:$Ident|,|\)|\(|\s*$)/) {
			print "DECLARE($1)\n" if ($dbg_values > 1);
			$type = 'T';

		} elsif ($cur =~ /^($Modifier)\s*/) {
			print "MODIFIER($1)\n" if ($dbg_values > 1);
			$type = 'T';

		} elsif ($cur =~ /^(\#\s*define\s*$Ident)(\(?)/o) {
			print "DEFINE($1,$2)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;
			push(@av_paren_type, $type);
			if ($2 ne '') {
				$av_pending = 'N';
			}
			$type = 'E';

		} elsif ($cur =~ /^(\#\s*(?:undef\s*$Ident|include\b))/o) {
			print "UNDEF($1)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;
			push(@av_paren_type, $type);

		} elsif ($cur =~ /^(\#\s*(?:ifdef|ifndef|if))/o) {
			print "PRE_START($1)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;

			push(@av_paren_type, $type);
			push(@av_paren_type, $type);
			$type = 'E';

		} elsif ($cur =~ /^(\#\s*(?:else|elif))/o) {
			print "PRE_RESTART($1)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;

			push(@av_paren_type, $av_paren_type[$#av_paren_type]);

			$type = 'E';

		} elsif ($cur =~ /^(\#\s*(?:endif))/o) {
			print "PRE_END($1)\n" if ($dbg_values > 1);

			$av_preprocessor = 1;

			# Assume all arms of the conditional end as this
			# one does, and continue as if the #endif was not here.
			pop(@av_paren_type);
			push(@av_paren_type, $type);
			$type = 'E';

		} elsif ($cur =~ /^(\\\n)/o) {
			print "PRECONT($1)\n" if ($dbg_values > 1);

		} elsif ($cur =~ /^(__attribute__)\s*\(?/o) {
			print "ATTR($1)\n" if ($dbg_values > 1);
			$av_pending = $type;
			$type = 'N';

		} elsif ($cur =~ /^(sizeof)\s*(\()?/o) {
			print "SIZEOF($1)\n" if ($dbg_values > 1);
			if (defined $2) {
				$av_pending = 'V';
			}
			$type = 'N';

		} elsif ($cur =~ /^(if|while|for)\b/o) {
			print "COND($1)\n" if ($dbg_values > 1);
			$av_pending = 'E';
			$type = 'N';

		} elsif ($cur =~/^(case)/o) {
			print "CASE($1)\n" if ($dbg_values > 1);
			$av_pend_colon = 'C';
			$type = 'N';

		} elsif ($cur =~/^(return|else|goto|typeof|__typeof__)\b/o) {
			print "KEYWORD($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~ /^(\()/o) {
			print "PAREN('$1')\n" if ($dbg_values > 1);
			push(@av_paren_type, $av_pending);
			$av_pending = '_';
			$type = 'N';

		} elsif ($cur =~ /^(\))/o) {
			my $new_type = pop(@av_paren_type);
			if ($new_type ne '_') {
				$type = $new_type;
				print "PAREN('$1') -> $type\n"
							if ($dbg_values > 1);
			} else {
				print "PAREN('$1')\n" if ($dbg_values > 1);
			}

		} elsif ($cur =~ /^($Ident)\s*\(/o) {
			print "FUNC($1)\n" if ($dbg_values > 1);
			$type = 'V';
			$av_pending = 'V';

		} elsif ($cur =~ /^($Ident\s*):(?:\s*\d+\s*(,|=|;))?/) {
			if (defined $2 && $type eq 'C' || $type eq 'T') {
				$av_pend_colon = 'B';
			} elsif ($type eq 'E') {
				$av_pend_colon = 'L';
			}
			print "IDENT_COLON($1,$type>$av_pend_colon)\n" if ($dbg_values > 1);
			$type = 'V';

		} elsif ($cur =~ /^($Ident|$Constant)/o) {
			print "IDENT($1)\n" if ($dbg_values > 1);
			$type = 'V';

		} elsif ($cur =~ /^($Assignment)/o) {
			print "ASSIGN($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~/^(;|{|})/) {
			print "END($1)\n" if ($dbg_values > 1);
			$type = 'E';
			$av_pend_colon = 'O';

		} elsif ($cur =~/^(,)/) {
			print "COMMA($1)\n" if ($dbg_values > 1);
			$type = 'C';

		} elsif ($cur =~ /^(\?)/o) {
			print "QUESTION($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~ /^(:)/o) {
			print "COLON($1,$av_pend_colon)\n" if ($dbg_values > 1);

			substr($var, length($res), 1, $av_pend_colon);
			if ($av_pend_colon eq 'C' || $av_pend_colon eq 'L') {
				$type = 'E';
			} else {
				$type = 'N';
			}
			$av_pend_colon = 'O';

		} elsif ($cur =~ /^(\[)/o) {
			print "CLOSE($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~ /^(-(?![->])|\+(?!\+)|\*|\&\&|\&)/o) {
			my $variant;

			print "OPV($1)\n" if ($dbg_values > 1);
			if ($type eq 'V') {
				$variant = 'B';
			} else {
				$variant = 'U';
			}

			substr($var, length($res), 1, $variant);
			$type = 'N';

		} elsif ($cur =~ /^($Operators)/o) {
			print "OP($1)\n" if ($dbg_values > 1);
			if ($1 ne '++' && $1 ne '--') {
				$type = 'N';
			}

		} elsif ($cur =~ /(^.)/o) {
			print "C($1)\n" if ($dbg_values > 1);
		}
		if (defined $1) {
			$cur = substr($cur, length($1));
			$res .= $type x length($1);
		}
	}

	return ($res, $var);
}

sub possible {
	my ($possible, $line) = @_;
	my $notPermitted = qr{(?:
		^(?:
			$Modifier|
			$Storage|
			$Type|
		)$|
		^(?:
			goto|
			return|
			case|
			else|
			asm|__asm__|
			do|
			\#|
			\#\#|
		)(?:\s|$)|
		^(?:typedef|struct|enum)\b
	    )}x;
	warn "CHECK<$possible> ($line)\n" if ($dbg_possible > 2);
	if ($possible !~ $notPermitted) {
		# Check for modifiers.
		$possible =~ s/\s*$Storage\s*//g;
		if ($possible =~ /^\s*$/) {

		} elsif ($possible =~ /\s/) {
			$possible =~ s/\s*$Type\s*//g;
			for my $modifier (split(' ', $possible)) {
				if ($modifier !~ $notPermitted) {
					warn "MODIFIER: $modifier ($possible) ($line)\n" if ($dbg_possible);
					push(@modifierListFile, $modifier);
				}
			}

		} else {
			warn "POSSIBLE: $possible ($line)\n" if ($dbg_possible);
			push(@typeListFile, $possible);
		}
		build_types();
	} else {
		warn "NOTPOSS: $possible ($line)\n" if ($dbg_possible > 1);
	}
}

my $prefix = '';

sub show_type {
	my ($type) = @_;

	$type =~ tr/[a-z]/[A-Z]/;

	return defined $use_type{$type} if (scalar keys %use_type > 0);

	return !defined $ignore_type{$type};
}

sub ERROR {
	my ($type, $msg) = @_;

	if (!show_type($type) ||
	    (defined $tst_only && $msg !~ /\Q$tst_only\E/)) {
		return 0;
	}
	my $output = '';
	if ($color) {
		$output .= RED;
	}
	$output .= $prefix . 'ERROR:';
	if ($show_types) {
		$output .= BLUE if ($color);
		$output .= "$type:";
	}
	$output .= RESET if ($color);
	$output .= ' ' . $msg . "\n";

	if ($showfile) {
		my @lines = split("\n", $output, -1);
		splice(@lines, 1, 1);
		$output = join("\n", @lines);
	}

	if ($terse) {
		$output = (split('\n', $output))[0] . "\n";
	}

	if ($verbose && exists($verbose_messages{$type}) &&
	    !exists($verbose_emitted{$type})) {
		$output .= $verbose_messages{$type} . "\n\n";
		$verbose_emitted{$type} = 1;
	}

	push(our @report, $output);
	our $clean = 0;
	our $cnt_error++;
	return 1;
}

sub report_dump {
	our @report;
}

sub trim {
	my ($string) = @_;

	$string =~ s/^\s+|\s+$//g;

	return $string;
}

sub ltrim {
	my ($string) = @_;

	$string =~ s/^\s+//;

	return $string;
}

sub rtrim {
	my ($string) = @_;

	$string =~ s/\s+$//;

	return $string;
}

sub string_find_replace {
	my ($string, $find, $replace) = @_;

	$string =~ s/$find/$replace/g;

	return $string;
}

sub tabify {
	my ($leading) = @_;

	my $source_indent = $tabsize;
	my $max_spaces_before_tab = $source_indent - 1;
	my $spaces_to_tab = " " x $source_indent;

	#convert leading spaces to tabs
	1 while $leading =~ s@^([\t]*)$spaces_to_tab@$1\t@g;
	#Remove spaces before a tab
	1 while $leading =~ s@^([\t]*)( {1,$max_spaces_before_tab})\t@$1\t@g;

	return "$leading";
}

sub pos_last_openparen {
	my ($line) = @_;

	my $pos = 0;

	my $opens = $line =~ tr/\(/\(/;
	my $closes = $line =~ tr/\)/\)/;

	my $last_openparen = 0;

	if (($opens == 0) || ($closes >= $opens)) {
		return -1;
	}

	my $len = length($line);

	for ($pos = 0; $pos < $len; $pos++) {
		my $string = substr($line, $pos);
		if ($string =~ /^($FuncArg|$balanced_parens)/) {
			$pos += length($1) - 1;
		} elsif (substr($line, $pos, 1) eq '(') {
			$last_openparen = $pos;
		} elsif (index($string, '(') == -1) {
			last;
		}
	}

	return length(expand_tabs(substr($line, 0, $last_openparen))) + 1;
}

sub get_raw_comment {
	my ($line, $rawline) = @_;
	my $comment = '';

	for my $i (0 .. (length($line) - 1)) {
		if (substr($line, $i, 1) eq "$;") {
			$comment .= substr($rawline, $i, 1);
		}
	}

	return $comment;
}

sub process {
	my $filename = shift;

	my $linenr=0;
	my $prevline="";
	my $prevrawline="";
	my $stashline="";
	my $stashrawline="";

	my $length;
	my $indent;
	my $previndent=0;
	my $stashindent=0;

	our $clean = 1;
	my $signoff = 0;
	my $author = '';
	my $authorsignoff = 0;
	my $author_sob = '';
	my $is_patch = 0;
	my $in_header_lines = $file ? 0 : 1;
	my $in_commit_log = 0;		#Scanning lines before patch
	my $has_patch_separator = 0;	#Found a --- line
	my $has_commit_log = 0;		#Encountered lines before patch
	my $commit_log_lines = 0;	#Number of commit log lines
	my $commit_log_long_line = 0;
	my $commit_log_no_wrap = 0;
	my $commit_log_has_diff = 0;
	my $non_utf8_charset = 0;
	my $has_exec_perm = 0;		#Current file has exec permissions
	my $is_symlink = 0;

	my $last_git_commit_id_linenr = -1;

	my $last_blank_line = 0;
	my $last_coalesced_string_linenr = -1;

	our @report = ();
	our $cnt_lines = 0;
	our $cnt_error = 0;

	# Trace the real file/line as we go.
	my $realfile = '';
	my $realline = 0;
	my $realcnt = 0;
	my $here = '';
	my $context_function;		#undef'd unless there's a known function
	my $context_struct;		#undef'd unless there's a known struct
	my $in_comment = 0;
	my $first_line = 0;
	my %check_comment_ignore = ();

	my $prev_values = 'E';

	# suppression flags
	my %suppress_whiletrailers;
	my $suppress_statement = 0;

	my %signatures = ();

	my %commit_log_tags = ();
	my $has_changelog = 0;
	my $warned_about_test_result_file = 0;
	my $new_file = 0;
	my $has_doc = 0;
	my $has_test = 0;
	my $is_test = 0;

	# Pre-scan the patch sanitizing the lines.

	sanitise_line_reset();
	my $line;
	foreach my $rawline (@rawlines) {
		$linenr++;
		$line = $rawline;
		utf8::decode($line);

		if ($rawline =~ /^\@\@ -\d+(?:,\d+)? \+(\d+)(,(\d+))? \@\@/) {
			$realline=$1-1;
			if (defined $2) {
				$realcnt=$3+1;
			} else {
				$realcnt=1+1;
			}
			$in_comment = 0;

			# Guestimate if this is a continuing comment.  Run
			# the context looking for a comment "edge".  If this
			# edge is a close comment then we must be in a comment
			# at context start.
			my $edge;
			my $cnt = $realcnt;
			for (my $ln = $linenr + 1; $cnt > 0; $ln++) {
				next if (defined $rawlines[$ln - 1] &&
					 $rawlines[$ln - 1] =~ /^-/);
				$cnt--;
				#print "RAW<$rawlines[$ln - 1]>\n";
				last if (!defined $rawlines[$ln - 1]);
				if ($rawlines[$ln - 1] =~ m@(/\*|\*/)@ &&
				    $rawlines[$ln - 1] !~ m@"[^"]*(?:/\*|\*/)[^"]*"@) {
					($edge) = $1;
					last;
				}
			}
			if (defined $edge && $edge eq '*/') {
				$in_comment = 1;
			}

			# Guestimate if this is a continuing comment.  If this
			# is the start of a diff block and this line starts
			# ' *' then it is very likely a comment.
			if (!defined $edge &&
			    $rawlines[$linenr] =~ m@^.\s*(?:\*\*+| \*)(?:\s|$)@)
			{
				$in_comment = 1;
			}

			##print "COMMENT:$in_comment edge<$edge> $rawline\n";
			sanitise_line_reset($in_comment);

		} elsif ($realcnt && $rawline =~ /^(?:\+| |$)/) {
			# Standardise the strings and chars within the input to
			# simplify matching -- only bother with positive lines.
			$line = sanitise_line($rawline);
		}
		push(@lines, $line);

		if ($realcnt > 1) {
			$realcnt-- if ($line =~ /^(?:\+| |$)/);
		} else {
			$realcnt = 0;
		}

		#print "==>$rawline\n";
		#print "-->$line\n";
	}

	$prefix = '';

	$realcnt = 0;
	$linenr = 0;
	foreach my $line (@lines) {
		$linenr++;
		my $sline = $line;	#copy of $line
		$sline =~ s/$;/ /g;	#with comments as spaces

		my $rawline = $rawlines[$linenr - 1];
		my $raw_comment = get_raw_comment($line, $rawline);

# check if it's a mode change, rename or start of a patch
		if (!$in_commit_log &&
		    ($line =~ /^ mode change [0-7]+ => [0-7]+ \S+\s*$/ ||
		    ($line =~ /^rename (?:from|to) \S+\s*$/ ||
		     $line =~ /^diff --git a\/[\w\/\.\_\-]+ b\/\S+\s*$/))) {
			$is_patch = 1;
		}

#extract the line range in the file after the patch is applied
		if (!$in_commit_log &&
		    $line =~ /^\@\@ -\d+(?:,\d+)? \+(\d+)(,(\d+))? \@\@(.*)/) {
			my $context = $4;
			$is_patch = 1;
			$first_line = $linenr + 1;
			$realline=$1-1;
			if (defined $2) {
				$realcnt=$3+1;
			} else {
				$realcnt=1+1;
			}
			annotate_reset();
			$prev_values = 'E';

			%suppress_whiletrailers = ();
			$suppress_statement = 0;
			if ($context =~ /\b(\w+)\s*\(/) {
				$context_function = $1;
			} else {
				undef $context_function;
			}
			if ($context =~ /\bstruct\s+(?:\w+\s+)*(\w+)\s*{/) {
				$context_struct = $1;
			} else {
				undef $context_struct;
			}
			next;

# track the line number as we move through the hunk, note that
# new versions of GNU diff omit the leading space on completely
# blank context lines so we need to count that too.
		} elsif ($line =~ /^( |\+|$)/) {
			$realline++;
			$realcnt-- if ($realcnt != 0);

			# Measure the line length and indent.
			($length, $indent) = line_stats($rawline);

			# Track the previous line.
			($prevline, $stashline) = ($stashline, $line);
			($previndent, $stashindent) = ($stashindent, $indent);
			($prevrawline, $stashrawline) = ($stashrawline, $rawline);

			#warn "line<$line>\n";

		} elsif ($realcnt == 1) {
			$realcnt--;
		}

		my $hunk_line = ($realcnt != 0);

		$here = "#$linenr: " if (!$file);
		$here = "#$realline: " if ($file);

		# extract the filename as it passes
		if ($line =~ /^diff --git.*?(\S+)$/ ||
		    $line =~ /^\+\+\+\s+(\S+)/) {
			my $newrealfile = $1;
			$newrealfile =~ s@^([^/]*)/@@ if (!$file);
			if ($realfile ne $newrealfile) {
				$realfile = $newrealfile;
				$has_exec_perm = 0;
				$is_symlink = 0;
				%check_comment_ignore = ();
			}
			$in_commit_log = 0;
			next
		}

		if ($line =~ /^---\s(\S+)$/) {
			$new_file = $1 eq "/dev/null"
		}

		if ($line =~ /^new (file )?mode 0?120/ ||
		    $line =~ /^index [0-9a-f]+..[0-9a-f]+ 0?120/) {
			$is_symlink = 1;
		}

# Check for incorrect file permissions
		if ($line =~ /^new (file )?mode.*[7531]\d{0,2}$/) {
			$has_exec_perm = 1
		}
		if ($realline == 1 and ($line =~ /^\+#!/) != $has_exec_perm) {
			my $permhere = $here . "FILE: $realfile\n";
			my $msg = ($has_exec_perm ?
				   "Executable file must have hashbang (#!)" :
				   "Hashbang (#!) without execute permissions is useless");
			ERROR("EXECUTE_PERMISSIONS", "$msg\n" . $permhere);
		}

#make up the handle for any error we report on this line
		if ($showfile) {
			$prefix = "$realfile:$realline: "
		} elsif ($emacs) {
			if ($file) {
				$prefix = "$filename:$realline: ";
			} else {
				$prefix = "$filename:$linenr: ";
			}
		}

		$here .= "FILE: $realfile:$realline:" if ($realcnt != 0);

		my $hereline = "$here\n$rawline\n";
		my $herecurr = "$here\n$rawline\n";
		my $hereprev = "$here\n$prevrawline\n$rawline\n";

		$cnt_lines++ if ($realcnt != 0);

# Verify the existence of a commit log if appropriate
# 2 is used because a $signature is counted in $commit_log_lines
		if ($in_commit_log) {
			if ($line !~ /^\s*$/) {
				$commit_log_lines++;	#could be a $signature
			}
		} elsif ($has_commit_log && $commit_log_lines < 2) {
			ERROR("COMMIT_MESSAGE",
			      "Missing commit description - Add an appropriate one\n");
			$commit_log_lines = 2;	#warn only once
		}

# Check if the commit log has what seems like a diff which can confuse patch
		if ($in_commit_log && !$commit_log_has_diff &&
		    (($line =~ m@^\s+diff\b.*a/([\w/]+)@ &&
		      $line =~ m@^\s+diff\b.*a/[\w/]+\s+b/$1\b@) ||
		     $line =~ m@^\s*(?:\-\-\-\s+a/|\+\+\+\s+b/)@ ||
		     $line =~ m/^\s*\@\@ \-\d+,\d+ \+\d+,\d+ \@\@/)) {
			ERROR("DIFF_IN_COMMIT_MSG",
			      "Avoid using diff content in the commit message - patch(1) might not work\n" . $herecurr);
			$commit_log_has_diff = 1;
		}

# Check the patch for a From:
		if (decode("MIME-Header", $line) =~ /^From:\s*(.*)/) {
			$author = $1;
			my $curline = $linenr;
			while(defined($rawlines[$curline]) && ($rawlines[$curline++] =~ /^[ \t]\s*(.*)/)) {
				$author .= $1;
			}
			$author = encode("utf8", $author) if ($line =~ /=\?utf-8\?/i);
			$author =~ s/"//g;
			$author = reformat_email($author);
		}

# Check the patch for a signoff:
		if ($line =~ /^\s*signed-off-by:\s*(.*)/i) {
			$signoff++;
			$in_commit_log = 0;
			if ($author ne ''  && $authorsignoff != 1) {
				if (same_email_addresses($1, $author)) {
					$authorsignoff = 1;
				} else {
					my $ctx = $1;
					my ($email_name, $email_comment, $email_address, $comment1) = parse_email($ctx);
					my ($author_name, $author_comment, $author_address, $comment2) = parse_email($author);

					if (lc $email_address eq lc $author_address && $email_name eq $author_name) {
						$author_sob = $ctx;
						$authorsignoff = 2;
					} elsif (lc $email_address eq lc $author_address) {
						$author_sob = $ctx;
						$authorsignoff = 3;
					} elsif ($email_name eq $author_name) {
						$author_sob = $ctx;
						$authorsignoff = 4;

						my $address1 = $email_address;
						my $address2 = $author_address;

						if ($address1 =~ /(\S+)\+\S+(\@.*)/) {
							$address1 = "$1$2";
						}
						if ($address2 =~ /(\S+)\+\S+(\@.*)/) {
							$address2 = "$1$2";
						}
						if ($address1 eq $address2) {
							$authorsignoff = 5;
						}
					}
				}
			}
		}

# Check for patch separator
#
# Ignore in the git mode, because we format patches with --no-stat.
# This is needed so as not to skip the rest of the commit log message
# when it contains a line with three dashes (e.g. YaML code).
		if (!$git && $line =~ /^---$/) {
			$has_patch_separator = 1;
			$in_commit_log = 0;
		}

# Check signature styles
		if ($in_commit_log &&
		    $line =~ /^(\s*)([a-z0-9_-]+by:|$signature_tags)(\s*)(.*)/i) {
			my $space_before = $1;
			my $sign_off = $2;
			my $space_after = $3;
			my $email = $4;
			my $ucfirst_sign_off = ucfirst(lc($sign_off));

			if ($sign_off !~ /$signature_tags/) {
				my $suggested_signature = find_standard_signature($sign_off);
				if ($suggested_signature eq "") {
					ERROR("BAD_SIGN_OFF",
					      "Non-standard signature: $sign_off\n" . $herecurr);
				} else {
					ERROR("BAD_SIGN_OFF",
					      "Non-standard signature: '$sign_off' - perhaps '$suggested_signature'?\n" . $herecurr);
				}
			}
			if (defined $space_before && $space_before ne "") {
				ERROR("BAD_SIGN_OFF",
				      "Do not use whitespace before $ucfirst_sign_off\n" . $herecurr);
			}
			if ($sign_off =~ /-by:$/i && $sign_off ne $ucfirst_sign_off) {
				ERROR("BAD_SIGN_OFF",
				      "'$ucfirst_sign_off' is the preferred signature form\n" . $herecurr);
			}
			if (!defined $space_after || $space_after ne " ") {
				ERROR("BAD_SIGN_OFF",
				      "Use a single space after $ucfirst_sign_off\n" . $herecurr);
			}

			my ($email_name, $name_comment, $email_address, $comment) = parse_email($email);
			my $suggested_email = format_email(($email_name, $name_comment, $email_address, $comment));
			if ($suggested_email eq "") {
				ERROR("BAD_SIGN_OFF",
				      "Unrecognized email address: '$email'\n" . $herecurr);
			} else {
				my $dequoted = $suggested_email;
				$dequoted =~ s/^"//;
				$dequoted =~ s/" </ </;
				# Don't force email to have quotes
				# Allow just an angle bracketed address
				if (!same_email_addresses($email, $suggested_email)) {
					ERROR("BAD_SIGN_OFF",
					      "email address '$email' might be better as '$suggested_email'\n" . $herecurr);
				}

				# Address part shouldn't have comments
				my $stripped_address = $email_address;
				$stripped_address =~ s/\([^\(\)]*\)//g;
				if ($email_address ne $stripped_address) {
					ERROR("BAD_SIGN_OFF",
					      "address part of email should not have comments: '$email_address'\n" . $herecurr);
				}

				# Only one name comment should be allowed
				my $comment_count = () = $name_comment =~ /\([^\)]+\)/g;
				if ($comment_count > 1) {
					ERROR("BAD_SIGN_OFF",
					      "Use a single name comment in email: '$email'\n" . $herecurr);
				}

				if ($comment ne "" && $comment !~ /^(?:#.+|\(.+\))$/) {
					my $new_comment = $comment;

					# Extract comment text from within brackets or
					# c89 style /*...*/ comments
					$new_comment =~ s/^\[(.*)\]$/$1/;
					$new_comment =~ s/^\/\*(.*)\*\/$/$1/;

					$new_comment = trim($new_comment);
					$new_comment =~ s/^[^\w]$//; # Single lettered comment with non word character is usually a typo
					$new_comment = "($new_comment)" if ($new_comment ne "");
					my $new_email = format_email($email_name, $name_comment, $email_address, $new_comment);

					ERROR("BAD_SIGN_OFF",
					      "Unexpected content after email: '$email', should be: '$new_email'\n" . $herecurr);
				}
			}

# Check for duplicate signatures
			my $sig_nospace = $line;
			$sig_nospace =~ s/\s//g;
			$sig_nospace = lc($sig_nospace);
			if (defined $signatures{$sig_nospace}) {
				ERROR("BAD_SIGN_OFF",
				      "Duplicate signature\n" . $herecurr);
			} else {
				$signatures{$sig_nospace} = 1;
			}

# Check Co-developed-by: immediately followed by Signed-off-by: with same name and email
			if ($sign_off =~ /^co-developed-by:$/i) {
				if ($email eq $author) {
					ERROR("BAD_SIGN_OFF",
					      "Co-developed-by: should not be used to attribute nominal patch author '$author'\n" . "$here\n" . $rawline);
				}
				if (!defined $lines[$linenr]) {
					ERROR("BAD_SIGN_OFF",
					      "Co-developed-by: must be immediately followed by Signed-off-by:\n" . "$here\n" . $rawline);
				} elsif ($rawlines[$linenr] !~ /^\s*signed-off-by:\s*(.*)/i) {
					ERROR("BAD_SIGN_OFF",
					      "Co-developed-by: must be immediately followed by Signed-off-by:\n" . "$here\n" . $rawline . "\n" .$rawlines[$linenr]);
				} elsif ($1 ne $email) {
					ERROR("BAD_SIGN_OFF",
					      "Co-developed-by and Signed-off-by: name/email do not match \n" . "$here\n" . $rawline . "\n" .$rawlines[$linenr]);
				}
			}
		}

# Check for Gerrit Change-Ids not in any patch context
		if ($realfile eq '' && !$has_patch_separator && $line =~ /^\s*change-id:/i) {
			ERROR("GERRIT_CHANGE_ID",
			      "Remove Gerrit Change-Id's before submitting upstream\n" . $herecurr);
		}

		if ($in_commit_log && $line =~ /^NO_WRAP$/) {
			$commit_log_no_wrap = !$commit_log_no_wrap;
		}

# Check for line lengths > 75 in commit log, warn once
		if ($in_commit_log && !$commit_log_no_wrap && !$commit_log_long_line &&
		    length($line) > 75 &&
		    !($line =~ /^\s*[a-zA-Z0-9_\/\.]+\s+\|\s+\d+/ ||
					# file delta changes
		      $line =~ /^\s*(?:[\w\.\-\+]*\/)++[\w\.\-\+]+:/ ||
					# filename then :
		      $line =~ /\b[a-z][\w\.\+\-]*:\/\/\S+$/i ||
					# URL
		      $line =~ /^\s*(?:Fixes:|Link:|$signature_tags)/i)) {
					# A Fixes: or Link: line or signature tag line
			ERROR("COMMIT_LOG_LONG_LINE",
			      "Unwrapped commit description (should be <= 75 chars per line). Surround unwrapped text with NO_WRAP to suppress this error.\n" . $herecurr);
			$commit_log_long_line = 1;
		}

# Check for git id commit length and improperly formed commit descriptions
# A correctly formed commit description is:
#    commit <SHA-1 hash length 12+ chars> ("Complete commit subject")
# with the commit subject '("' prefix and '")' suffix
# This is a fairly compilicated block as it tests for what appears to be
# bare SHA-1 hash with  minimum length of 5.  It also avoids several types of
# possible SHA-1 matches.
# A commit match can span multiple lines so this block attempts to find a
# complete typical commit on a maximum of 3 lines
		if ($in_commit_log &&
		    $line !~ /^\s*(?:Link|Patchwork|http|https|BugLink|base-commit):/i &&
		    $line !~ /^This reverts commit [0-9a-f]{7,40}/ &&
		    (($line =~ /\bcommit\s+[0-9a-f]{5,}\b/i ||
		      ($line =~ /\bcommit\s*$/i && defined($rawlines[$linenr]) && $rawlines[$linenr] =~ /^\s*[0-9a-f]{5,}\b/i)) ||
		     ($line =~ /(?:\s|^)[0-9a-f]{12,40}(?:[\s"'\(\[]|$)/i &&
		      $line !~ /[\<\[][0-9a-f]{12,40}[\>\]]/i &&
		      $line !~ /\bfixes:\s*[0-9a-f]{12,40}/i))) {
			my $init_char = "c";
			my $orig_commit = "";
			my $short = 1;
			my $long = 0;
			my $case = 1;
			my $space = 1;
			my $id = '0123456789ab';
			my $orig_desc = "commit description";
			my $description = "";
			my $herectx = $herecurr;
			my $has_parens = 0;
			my $has_quotes = 0;

			my $input = $line;
			if ($line =~ /(?:\bcommit\s+[0-9a-f]{5,}|\bcommit\s*$)/i) {
				for (my $n = 0; $n < 2; $n++) {
					if ($input =~ /\bcommit\s+[0-9a-f]{5,}\s*($balanced_parens)/i) {
						$orig_desc = $1;
						$has_parens = 1;
						# Always strip leading/trailing parens then double quotes if existing
						$orig_desc = substr($orig_desc, 1, -1);
						if ($orig_desc =~ /^".*"$/) {
							$orig_desc = substr($orig_desc, 1, -1);
							$has_quotes = 1;
						}
						last;
					}
					last if ($#lines < $linenr + $n);
					$input .= " " . trim($rawlines[$linenr + $n]);
					$herectx .= "$rawlines[$linenr + $n]\n";
				}
				$herectx = $herecurr if (!$has_parens);
			}

			if ($input =~ /\b(c)ommit\s+([0-9a-f]{5,})\b/i) {
				$init_char = $1;
				$orig_commit = lc($2);
				$short = 0 if ($input =~ /\bcommit\s+[0-9a-f]{12,40}/i);
				$long = 1 if ($input =~ /\bcommit\s+[0-9a-f]{41,}/i);
				$space = 0 if ($input =~ /\bcommit [0-9a-f]/i);
				$case = 0 if ($input =~ /\b[Cc]ommit\s+[0-9a-f]{5,40}[^A-F]/);
			} elsif ($input =~ /\b([0-9a-f]{12,40})\b/i) {
				$orig_commit = lc($1);
			}

			($id, $description) = git_commit_info($orig_commit,
							      $id, $orig_desc);

			if (defined($id) && $line !~ /^\(cherry picked from commit [0-9a-f]+\)$/ &&
			    ($short || $long || $space || $case || ($orig_desc ne $description) || !$has_quotes) &&
			    $last_git_commit_id_linenr != $linenr - 1) {
				ERROR("GIT_COMMIT_ID",
				      "Please use git commit description style 'commit <12+ chars of sha1> (\"<title line>\")' - ie: '${init_char}ommit $id (\"$description\")'\n" . $herectx);
			}
			#don't report the next line if this line ends in commit and the sha1 hash is the next line
			$last_git_commit_id_linenr = $linenr if ($line =~ /\bcommit\s*$/i);
		}

# Check for wrappage within a valid hunk of the file
		if ($realcnt != 0 && $line !~ m{^(?:\+|-| |\\ No newline|$)}) {
			ERROR("CORRUPTED_PATCH",
			      "patch seems to be corrupt (line wrapped?)\n" .
				$herecurr) if (!$emitted_corrupt++);
		}

		next if !$file and $realfile =~ /^$skipPaths/;

# UTF-8 regex found at http://www.w3.org/International/questions/qa-forms-utf-8.en.php
		if (($realfile =~ /^$/ || $line =~ /^\+/) &&
		    $rawline !~ m/^$UTF8*$/) {
			my ($utf8_prefix) = ($rawline =~ /^($UTF8*)/);

			my $blank = copy_spacing($rawline);
			my $ptr = substr($blank, 0, length($utf8_prefix)) . "^";
			my $hereptr = "$hereline$ptr\n";

			ERROR("INVALID_UTF8",
			      "Invalid UTF-8, patch and commit message should be encoded in UTF-8\n" . $hereptr);
		}

# Check if it's the start of a commit log
# (not a header line and we haven't seen the patch filename)
		if ($in_header_lines && $realfile =~ /^$/ &&
		    !($rawline =~ /^\s+(?:\S|$)/ ||
		      $rawline =~ /^(?:commit\b|from\b|[\w-]+:)/i)) {
			$in_header_lines = 0;
			$in_commit_log = 1;
			$has_commit_log = 1;
		}

# Check if there is UTF-8 in a commit log when a mail header has explicitly
# declined it, i.e defined some charset where it is missing.
		if ($in_header_lines &&
		    $rawline =~ /^Content-Type:.+charset="(.+)".*$/ &&
		    $1 !~ /utf-8/i) {
			$non_utf8_charset = 1;
		}

		if ($in_commit_log && $non_utf8_charset && $realfile =~ /^$/ &&
		    $rawline =~ /$NON_ASCII_UTF8/) {
			ERROR("UTF8_BEFORE_PATCH",
			      "8-bit UTF-8 used in possible commit log\n" . $herecurr);
		}

# Check for various typo / spelling mistakes
		if (defined($misspellings) &&
		    ($in_commit_log || $line =~ /^(?:\+|Subject:)/i)) {
			while ($rawline =~ /(^|[^\w\-'`])($misspellings)(?:[^\w\-'`]|$)/gi) {
				my $prev = $1;
				my $typo = $2;
				# Ignore if this is a patch file and the line is removed or unchanged.
				next if $realfile =~ /\.patch$/ && $rawline !~ /^\+\+/;
				# Ignore anything that looks like regular expression or file path.
				next if $prev =~ /[.|\/]/;
				# Ignore ALL UPPER CASE words as it may be an abbreviation,
				# e.g. TAHT - Tahiti Time
				next if ($typo eq uc($typo));
				my $blank = copy_spacing($rawline);
				my $ptr = substr($blank, 0, $-[1]) . "^" x length($typo);
				my $hereptr = "$hereline$ptr\n";
				my $typo_fix = $spelling_fix{lc($typo)};
				$typo_fix = ucfirst($typo_fix) if ($typo =~ /^[A-Z]/);
				# Ignore CamelCase.
				my $typo_fix_camel_case = $typo_fix;
				$typo_fix_camel_case =~ s/ (\w)/\U$1/g;
				next if ($typo eq $typo_fix_camel_case);
				$typo_fix = uc($typo_fix) if ($typo =~ /^[A-Z]+$/);
				# Ignore the case when we drop a character to use a misspelled word as function name, e.g. isnt().
				next if ($realfile =~ /\.h|c|cc|lua$/ && $typo_fix =~ /[^a-zA-Z_]/ && $line =~ /\b$typo\s*\(/);
				ERROR("TYPO_SPELLING",
				      "'$typo' may be misspelled - perhaps '$typo_fix'?\n" . $hereptr);
			}
		}

# check for invalid commit id
		if ($in_commit_log && $line =~ /(^fixes:|\bcommit)\s+([0-9a-f]{6,40})\b/i) {
			my $id;
			my $description;
			($id, $description) = git_commit_info($2, undef, undef);
			if (!defined($id)) {
				ERROR("UNKNOWN_COMMIT_ID",
				      "Unknown commit id '$2', maybe rebased or not pulled?\n" . $herecurr);
			}
		}

		if ($in_commit_log && $line =~ /^($custom_tags)=/) {
			$commit_log_tags{$1} = 1;
		}
		if ($in_commit_log && $line =~ /^\@TarantoolBot document$/) {
			$has_doc = 1;
		}
		if ($realfile =~ /^changelogs\/unreleased/) {
			$has_changelog = 1;
		}
		if ($realfile =~ /^(?:static-build\/)?test\/.*\//) {
			$has_test = 1;
		}

# check for repeated words separated by a single space
# avoid false positive from list command eg, '-rw-r--r-- 1 root root'
		if (($rawline =~ /^\+/ || $in_commit_log) &&
		    $rawline !~ /[bcCdDlMnpPs\?-][rwxsStT-]{9}/) {
			pos($rawline) = 1 if (!$in_commit_log);
			while ($rawline =~ /\b($word_pattern) (?=($word_pattern))/g) {

				my $first = $1;
				my $second = $2;
				my $start_pos = $-[1];
				my $end_pos = $+[2];
				if ($first =~ /(?:class|struct|union|enum)/) {
					pos($rawline) += length($first) + length($second) + 1;
					next;
				}

				next if (lc($first) ne lc($second));
				next if ($first eq 'long');

				# Ignore Doxygen-style comments like
				# @param request Request to process
				next if $rawline =~ /^\+\s\*\s+[\@\\]param(?:\[[a-z,]*\])*\s+$first $second/;

				# Ignore variable declarations.
				next if $realfile =~ /.h|c|cc|proto$/ &&
					$rawline =~ /^\+\s*(?:(?:$Storage|$Modifier|optional|required|repeated)\s+)*$first\s+$second\s*[=;]/;

				# Ignore 'not not' in Lua.
				next if $realfile =~ /\.lua$/ && $first eq 'not';

				# check for character before and after the word matches
				my $start_char = '';
				my $end_char = '';
				$start_char = substr($rawline, $start_pos - 1, 1) if ($start_pos > ($in_commit_log ? 0 : 1));
				$end_char = substr($rawline, $end_pos, 1) if ($end_pos < length($rawline));

				next if ($start_char =~ /^\S$/);
				next if (index(" \t.,;?!", $end_char) == -1);

				# avoid repeating hex occurrences like 'ff ff fe 09 ...'
				if ($first =~ /\b[0-9a-f]{2,}\b/i) {
					next if (!exists($allow_repeated_words{lc($first)}));
				}

				ERROR("REPEATED_WORD",
				      "Possible repeated word: '$first'\n" . $herecurr);
			}

			# if it's a repeated word on consecutive lines in a comment block
			if ($prevline =~ /$;+\s*$/ &&
			    $prevrawline =~ /($word_pattern)\s*$/) {
				my $last_word = $1;
				if ($rawline =~ /^\+\s*\*\s*$last_word /) {
					ERROR("REPEATED_WORD",
					      "Possible repeated word: '$last_word'\n" . $hereprev);
				}
			}
		}

# ignore non-hunk lines and lines being removed
		next if (!$hunk_line || $line =~ /^-/);

#trailing whitespace
		if ($line =~ /^\+.*\015/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("DOS_LINE_ENDINGS",
			      "DOS line endings\n" . $herevet);
		} elsif ($realfile !~ /\.(?:patch|result)$/ && ($rawline =~ /^\+.*\S\s+$/ || $rawline =~ /^\+\s+$/)) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("TRAILING_WHITESPACE",
			      "trailing whitespace\n" . $herevet);
		}

		if ($line =~ /^\+\s*$/ && (!defined($lines[$linenr]) || $lines[$linenr] =~ /^(?:diff --git|-- $)/)) {
			ERROR("TRAILING_NEWLINE",
			      "trailing newline\n" . $hereprev);
		}

# check for adding lines without a newline.
		if (!$is_symlink && $line =~ /^\+/ && defined $lines[$linenr] && $lines[$linenr] =~ /^\\ No newline at end of file/) {
			ERROR("MISSING_EOF_NEWLINE",
			      "adding a line without newline at end of file\n" . $herecurr);
		}

# Ban non-ASCII characters in text files
		if ($rawline =~ /^\+.*($NON_ASCII_UTF8)/) {
			my $blank = copy_spacing($rawline);
			my $ptr = substr($blank, 0, $-[1]) . "^";
			my $hereptr = "$hereline$ptr\n";
			ERROR("NON_ASCII_CHAR",
			      "please, don't use non-ASCII characters\n" . $hereptr);
		}

# check for space before tabs.
		if ($realfile !~ /\.patch$/ && $rawline =~ /^\+/ && $rawline =~ / \t/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("SPACE_BEFORE_TAB",
			      "please, no space before tabs\n" . $herevet);
		}

# Check for tabs in files where we use only spaces
		if ($realfile !~ /(?:Makefile|rules|\.(h|c|cc|cpp|h\.cmake|h\.proto|rl|y|mk|make|patch|result|gitmodules))$/ && $rawline =~ /^\+.*\t/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("TABSTOP",
			      "please, use spaces instead of tabs\n" . $herevet);
		}

		if (!$warned_about_test_result_file &&
		     $realfile =~ /^test\/.*\.result$/ &&
		     $new_file) {
			$warned_about_test_result_file = 1;
			ERROR("TEST_RESULT_FILE",
			      "Please avoid new tests with .result files\n");
		}

# check we are in a valid source file if not then ignore this hunk
		next if ($realfile !~ /\.(h|c|cc|lua)$/ || $realfile =~ /\.test\.lua$/);

# ignore source files outside the source and test directories when checking patches
		next if !$file and ($realfile !~ /^(?:src|test|perf)\// || $realfile =~ /^$skipSrcPaths/);

		$is_test = ($realfile =~ /^(?:test|perf)\//);

# line length limit (with some exclusions)
#
# There are a few types of lines that may extend beyond $max_line_length:
#	logging functions like say_info that end in a string
#	lines with a single string
#	#defines that are a single string
#	array initilizers
#	lines with an RFC3986 like URL
#	multiline macros, that can use 81th backslash symbol
#
# There are 3 different line length message types:
# LONG_LINE_COMMENT	a comment starts before but extends beyond $max_line_length
# LONG_LINE_STRING	a string starts before but extends beyond $max_line_length
# LONG_LINE		all other lines longer than $max_line_length
#
# if LONG_LINE is ignored, the other 2 types are also ignored
#

		if ($line =~ /^\+/ && $length > $max_line_length) {
			my $msg_type = "LONG_LINE";

			# Check the allowed long line types first

			# logging functions that end in a string that starts
			# before $max_line_length
			if ($line =~ /^\+\s*$logFunctions\s*\(\s*($String\s*(?:|,|\)\s*;)\s*)$/ &&
			    length(expand_tabs(substr($line, 1, length($line) - length($1) - 1))) <= $max_line_length) {
				$msg_type = "";

			# lines with only strings (w/ possible termination)
			# #defines with only strings
			} elsif ($line =~ /^\+\s*$String\s*(?:\s*|,|\)\s*;)\s*$/ ||
				 $line =~ /^\+\s*#\s*define\s+\w+\s+$String$/) {
				$msg_type = "";

			# Array initializers
			# { bar, baz },
			# foo, bar, baz,
			# FOO(bar, baz),
			# FOO(bar, baz) \
			} elsif ($line =~ /^\+[$;\s]*(?:\{.*\}|([0-9a-z_]+\s*,\s*)+|[a-z_]+\s*\(.*\))\s*,?[$;\s]*\\?\s*$/i) {
				$msg_type = "";

			# URL ($rawline is used in case the URL is in a comment)
			} elsif ($rawline =~ /^\+.*\b[a-z][\w\.\+\-]*:\/\/\S+/i) {
				$msg_type = "";
			# Multiline macros often use '\' as the last, 81st symbol
			} elsif ($line =~ /^\+.*\\$/ && $length == $max_line_length + 1) {
				$msg_type = "";
			# Comment which is used as a header in array initializer
			# /* FOO  BAR  BAZ */
			} elsif ($rawline =~ /^.\s*\/\*[a-zA-Z_\s]+\*\/\s*$/) {
				$msg_type = "";

			# Otherwise set the alternate message types

			# a comment starts before $max_line_length
			} elsif ($line =~ /($;[\s$;]*)$/ &&
				 length(expand_tabs(substr($line, 1, length($line) - length($1) - 1))) <= $max_line_length) {
				$msg_type = "LONG_LINE_COMMENT"

			# a quoted string starts before $max_line_length
			} elsif ($sline =~ /\s*($String(?:\s*(?:\\|,\s*|\)\s*;\s*))?)$/ &&
				 length(expand_tabs(substr($line, 1, length($line) - length($1) - 1))) <= $max_line_length) {
				$msg_type = "LONG_LINE_STRING"
			}

			if ($msg_type ne "") {
				ERROR($msg_type,
				      "line length of $length exceeds $max_line_length columns\n" . $herecurr);
			}
		}

# check we are in a valid C source file if not then ignore this hunk
		next if ($realfile !~ /\.(h|c|cc)$/);

# require pragma instead of include guards
		if ($line =~ /^\+\s*#\s*ifndef\s+[A-Z0-9_]+(?:_H|_INCLUDED)\s*$/) {
			ERROR("INCLUDE_GUARD",
			      "Please use '#pragma once' instead of include guard macro\n" . $herecurr);
		}

# at the beginning of a line any tabs must come first and anything
# more than $tabsize must use tabs.
		if ($rawline =~ /^\+\s* \t\s*\S/ ||
		    $rawline =~ /^\+\s*        \s*/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("CODE_INDENT",
			      "code indent should use tabs where possible\n" . $herevet);
		}

# after a line that ends with assignment or open parenthesis, only tabs may be used for indentation
		if ($rawline =~ /^\+\t* / && $prevline =~ /(?:([\(\{\[])|^\+\s*$Declare\s*$Ident\s*=|^\+\s*$Lval\s*$Assignment)\s*$/) {
			my $herevet = "$here\n$prevrawline\n" . cat_vet($rawline) . "\n";
			my $what = defined($1) ? "'$1'" : 'assignment';
			ERROR("CODE_INDENT",
			      "code indent shouldn't use spaces if the previous line ends with $what\n" . $herevet);
		}

# alignment should match the comment on the previous line unless it's the end of a function or struct
		if ($prevrawline =~ /^.(\s*)(?:\/\*.*| )\*\/\s*$/) {
			my $ident = length($1);
			if ($rawline =~ /^\+(\s*)[^\}]/ && length($1) != $ident) {
				ERROR("CODE_IDENT",
				      "code indent should match comment\n" . $hereprev);
			}
		}

# check for assignments on the start of a line
		if ($sline =~ /^\+\s+($Assignment)[^=]/) {
			ERROR("ASSIGNMENT_CONTINUATIONS",
			      "Assignment operator '$1' should be on the previous line\n" . $hereprev);
		}

# check for && or || at the start of a line
		if ($rawline =~ /^\+\s*(?:&&|\|\|)/) {
			ERROR("LOGICAL_CONTINUATIONS",
			      "Logical continuations should be on the previous line\n" . $hereprev);
		}

# check indentation starts on a tab stop
		if ($sline =~ /^\+\t+( +)(?:$c90_Keywords\b|\{\s*$|\}\s*(?:else\b|while\b|\s*$)|$Declare\s*$Ident\s*[;=])/) {
			my $indent = length($1);
			if ($indent % $tabsize) {
				ERROR("TABSTOP",
				      "Statements should start on a tabstop\n" . $herecurr);
			}
		}

# check multi-line statement indentation matches previous line
		if ($prevline =~ /^\+([ \t]*)((?:$c90_Keywords(?:\s+if)\s*)|(?:$Declare\s*)?(?:$Ident|\(\s*\*\s*$Ident\s*\))\s*|(?:(?:\*\s*)*$Lval|$Declare\s*$Ident)\s*=\s*$Ident\s*)\(.*(\&\&|\|\||,|")\s*$/) {
			$prevline =~ /^\+(\t*)(.*)$/;
			my $oldindent = $1;
			my $rest = $2;

			my $pos = pos_last_openparen($rest);
			if ($pos >= 0) {
				$line =~ /^(\+| )([ \t]*)/;
				my $newindent = $2;

				my $goodtabindent = $oldindent .
					"\t" x ($pos / $tabsize) .
					" "  x ($pos % $tabsize);
				my $goodspaceindent = $oldindent . " "  x $pos;

				if ($newindent ne $goodtabindent &&
				    $newindent ne $goodspaceindent) {

					ERROR("PARENTHESIS_ALIGNMENT",
					      "Alignment should match open parenthesis\n" . $hereprev);
				}
			}
		}

# check for multiple spaces
# allow spaces used for alignment before line-terminating '\'
		if ($line =~ /^\+.*\S\s{2,}(.*)/ && $1 !~ '\\\s*$') {
			my $s = $line;
			# remove trailing spaces
			$s =~ s/\s*$//;
			# remove spaces used for indentation
			$s =~ s/^(\+\s*)//;
			# remove spaces before the line-terminating comment along with the comment
			$s =~ s/\s*$;+$//;
			my $off = $+[1];
			my $pos = 0;
			my $ok = 1;

# allow spaces used for alignment in macro definitions

			if ($s =~ '^#') {
				$s =~ s/^(#\s*)//;
				$off += $+[1];
				if ($s =~ /^define(\s+)\w+\s*$balanced_parens?\s*(.+)$/) {
					my $s1 = $1;
					my $pos1 = $-[1];
					my $s2 = $2;
					my $pos2 = $-[2];
					$s = $3;
					$pos = $-[3];
					if ($s1 =~ /(\s\s)/) {
						$pos = $pos1 + $-[1];
						$ok = 0;
					} elsif (defined($s2) && $s2 =~ /(\s\s)/) {
						$pos = $pos2 + $-[1];
						$ok = 0;
					}
				}
				if ($ok && $s =~ /(\s\s)/) {
					$pos += $-[1];
					$ok = 0;
				}

# allow spaces used for alignement before '=' in struct/enum initializers

			} elsif ($s =~ /^(?:\[\s*$Ident\s*\]|\.?$Ident)\s*=(.*),$/) {
				$s = $1;
				$off += $-[1];
				if ($s =~ /(\s\s)/) {
					$pos = $-[1];
					$ok = 0;
				}

# allow spaces used for alignment after '{', ',' and before '}' in array initializers

			} elsif ($s =~ /^(?:.*,.*)+\s*,$/) {
				if ($s =~ /[^,\{\s](\s{2,})(.)/) {
					$pos = $-[1];
					$ok = 0 if $2 ne '}';
				}
			} elsif ($s =~ /\S(\s\s)/) {
				$pos = $-[1];
				$ok = 0;
			}

			if (!$ok) {
				my $blank = copy_spacing($rawline);
				my $ptr = substr($blank, 0, $off + $pos) . "^";
				ERROR("SPACING",
				      "Please don't use multiple spaces\n" . $herecurr . $ptr);
			}
		}

# check for space after cast like "(int) foo" or "(struct foo) bar"
# avoid checking a few false positives:
#   "sizeof(<type>)" or "__alignof__(<type>)"
#   function pointer declarations like "(*foo)(int) = bar;"
#   structure definitions like "(struct foo) { 0 };"
#   multiline macros that define functions
#   known attributes or the __attribute__ keyword
		if ($line =~ /^\+(.*)\(\s*$Type\s*\)([ \t]++)((?![={]|\\$|$Attribute|__attribute__))/ &&
		    (!defined($1) || $1 !~ /\b(?:sizeof|__alignof__)\s*$/)) {
			ERROR("SPACING",
			      "No space is necessary after a cast\n" . $herecurr);
		}

# Block comment styles
# Block comments use * on subsequent lines
		if ($prevline =~ /$;[ \t]*$/ &&			#ends in comment
		    $prevrawline =~ /^\+.*?\/\*/ &&		#starting /*
		    $prevrawline !~ /\*\/[ \t]*$/ &&		#no trailing */
		    $rawline =~ /^\+/ &&			#line is new
		    $rawline !~ /^\+[ \t]*\*/) {		#no leading *
			ERROR("BLOCK_COMMENT_STYLE",
			      "Block comments use * on subsequent lines\n" . $hereprev);
		}

# Block comments use */ on trailing lines
		if ($rawline !~ m@^\+[ \t]*\*/[ \t]*$@ &&	#trailing */
		    $rawline !~ m@^\+.*/\*.*\*/[ \t]*$@ &&	#inline /*...*/
		    $rawline !~ m@^\+.*\*{2,}/[ \t]*$@ &&	#trailing **/
		    $rawline =~ m@^\+[ \t]*.+\*\/[ \t]*$@) {	#non blank */
			ERROR("BLOCK_COMMENT_STYLE",
			      "Block comments use a trailing */ on a separate line\n" . $herecurr);
		}

# Block comment * alignment
		if ($prevline =~ /$;[ \t]*$/ &&			#ends in comment
		    $line =~ /^\+[ \t]*$;/ &&			#leading comment
		    $rawline =~ /^\+[ \t]*\*/ &&		#leading *
		    (($prevrawline =~ /^\+.*?\/\*/ &&		#leading /*
		      $prevrawline !~ /\*\/[ \t]*$/) ||		#no trailing */
		     $prevrawline =~ /^\+[ \t]*\*/)) {		#leading *
			my $oldindent;
			$prevrawline =~ m@^\+([ \t]*/?)\*@;
			if (defined($1)) {
				$oldindent = expand_tabs($1);
			} else {
				$prevrawline =~ m@^\+(.*/?)\*@;
				$oldindent = expand_tabs($1);
			}
			$rawline =~ m@^\+([ \t]*)\*@;
			my $newindent = $1;
			$newindent = expand_tabs($newindent);
			if (length($oldindent) ne length($newindent)) {
				ERROR("BLOCK_COMMENT_STYLE",
				      "Block comments should align the * on each line\n" . $hereprev);
			}
		}

# check for missing blank lines after struct/union declarations
# with exceptions for various attributes and macros
		if ($prevline =~ /^[\+ ]};?\s*$/ &&
		    $line =~ /^\+/ &&
		    !($line =~ /^\+\s*$/ ||
		      $line =~ /^\+\s*\#\s*(?:end|elif|else)/)) {
			ERROR("LINE_SPACING",
			      "Please use a blank line after function/struct/union/enum declarations\n" . $hereprev);
		}

# check for multiple consecutive blank lines
		if ($prevline =~ /^[\+ ]\s*$/ &&
		    $line =~ /^\+\s*$/ &&
		    $last_blank_line != ($linenr - 1)) {
			ERROR("LINE_SPACING",
			      "Please don't use multiple blank lines\n" . $hereprev);

			$last_blank_line = $linenr;
		}

# check if this appears to be the start function declaration, save the name
		if ($sline =~ /^.\{\s*$/) {
			# skip possible argument continuation
			my $n = $linenr - 2;
			while (defined($lines[$n]) && $lines[$n] =~ /[,\)]\s*$/) {
				if ($lines[$n] =~ /^.(?:(?:(?:$Storage|$Inline)\s*)*\s*$Type\s*)?($Ident)\(/) {
					$context_function = $1;
					last;
				}
				$n -= 1;
			}
		}

# check if this appears to be the end of function declaration
		if ($sline =~ /^.\}\s*$/) {
			undef $context_function;
		}

# check if this appears to be the start of struct declaration, save the name
		if ($line =~ /^\+struct\s+(?:$Modifier\s+)*($Ident)\s*{/) {
			$context_struct = $1;
		}

# check if this appears to be the end of struct declaration
		if ($sline =~ /^[\+\s]\}\s*;\s*$/) {
			undef $context_struct;
		}

# check indentation of a line with a break;
# if the previous line is a goto, return or break
# and is indented the same # of tabs
		if ($sline =~ /^\+([\t]+)break\s*;\s*$/) {
			my $tabs = $1;
			if ($prevline =~ /^\+$tabs(goto|return|break)\b/) {
				ERROR("UNNECESSARY_BREAK",
				      "break is not useful after a $1\n" . $hereprev);
			}
		}

# Check for potential 'bare' types
		my ($stat, $cond, $line_nr_next, $remain_next, $off_next,
		    $realline_next);
#print "LINE<$line>\n";
		if ($linenr > $suppress_statement &&
		    $realcnt && $sline =~ /.\s*\S/ && $sline !~ /.\s*#/) {
			($stat, $cond, $line_nr_next, $remain_next, $off_next) =
				ctx_statement_block($linenr, $realcnt, 0);
			$stat =~ s/\n./\n /g;
			$cond =~ s/\n./\n /g;

#print "linenr<$linenr> <$stat>\n";
			# If this statement has no statement boundaries within
			# it there is no point in retrying a statement scan
			# until we hit end of it.
			my $frag = $stat; $frag =~ s/;+\s*$//;
			if ($frag !~ /(?:{|;)/) {
#print "skip<$line_nr_next>\n";
				$suppress_statement = $line_nr_next;
			}

			# Find the real next line.
			$realline_next = $line_nr_next;
			if (defined $realline_next &&
			    (!defined $lines[$realline_next - 1] ||
			     substr($lines[$realline_next - 1], $off_next) =~ /^\s*$/)) {
				$realline_next++;
			}

			my $s = $stat;
			$s =~ s/{.*$//s;
			$s =~ s/^.*}//s;

			# Ignore goto labels and C++ access specifiers.
			$s =~ s/^.$Ident://m;

			# defintion in for() loop and catch() block
			if ($s =~ /^.\s*(?:for|\}?\s*catch)\s*\(\s*(?:const\s+)?($Ident)(?:\s*\bconst\b\s*|\s*\*\s*)*$Ident\b/) {
				possible($1, "A:" . $s);

			# Ignore functions being called
			} elsif ($s =~ /^.\s*$Ident\s*\(/s) {

			} elsif ($s =~ /^.\s*else\b/s) {

			# Ignore 'foo * bar;' at the end of a multi-line macro, because it may be a return value
			} elsif ($s =~ /^.\s*$Ident\s*\*\s*$Ident\s*;\s*$/ && defined($lines[$realline_next]) && $lines[$realline_next] =~ /\}\)/) {

			# declarations always start with types
			} elsif ($prev_values eq 'E' && $s =~ /^.\s*(?:$Storage\s+)?(?:$Inline\s+)?(?:const\s+)?((?:\s*$Ident)+?)\b\s*[\*&]*\s*(?:$Ident|operator\s*(?:$Operators|$Assignment)|\(\*[^\)]*\))(?:\s*$Modifier)?\s*(?:;|=|,|\()/s) {
				my $type = $1;
				$type =~ s/\s+/ /g;
				possible($type, "B:" . $s);

			# definitions in global scope can only start with types
			} elsif ($s =~ /^.(?:$Storage\s+)?(?:$Inline\s+)?(?:const\s+)?($Ident)\b\s*(?!:)/s) {
				possible($1, "C:" . $s);
			}

			# any (foo ... *) is a pointer cast, and foo is a type
			while ($s =~ /\(($Ident)[\s\*]+\s*\)/sg) {
				possible($1, "D:" . $s);
			}

			# C++ type cast
			while ($s =~ /\b$CXX_cast_operators\s*<\s*($Ident)[\s\*]+\s*>/sg) {
				possible($1, "E:" . $s);
			}

			# Check for any sort of function declaration.
			# int foo(something bar, other baz);
			# void (*store_gdt)(x86_descr_ptr *);
			#
			# Detect C++ constructors as well.
			# Foo(const Foo& other);
			#
			# We have to be careful here, because a constructor declaration looks like a function call
			# so we check that we are not in a function context.
			if ($prev_values eq 'E' &&
			    $s =~ /^(.(?:\s*template\b.*>)?\s*(?:($Ident)|(?:typedef\s*)?(?:(?:$Storage|$Inline)\s*)*\s*$Type\s*(?:\b$Ident|\([\*\&]\s*$Ident\)|operator\s*(?:$Operators|$Assignment)))\s*)\(/s &&
			    (!defined $2 || !defined $context_function || $2 eq $context_function)) {
				my ($name_len) = length($1);

				my $ctx = $s;
				substr($ctx, 0, $name_len + 1, '');
				$ctx =~ s/\)[^\)]*$//;

				for my $arg (split(/\s*,\s*/, $ctx)) {
					if ($arg =~ /^(?:const\s+)?($Ident)\s*[\*\&]*\s*(:?\b$Ident)?$/s || $arg =~ /^($Ident)$/s) {

						possible($1, "F:" . $s);
					}
				}
			}

		}

#
# Checks which may be anchored in the context.
#

# Check for switch () and associated case and default
# statements should be at the same indent.
		if ($line=~/\bswitch\s*\(.*\)/) {
			my $err = '';
			my $sep = '';
			my @ctx = ctx_block_outer($linenr, $realcnt);
			shift(@ctx);
			for my $ctx (@ctx) {
				my ($clen, $cindent) = line_stats($ctx);
				if ($ctx =~ /^\+\s*(case\s+|default:)/ &&
							$indent != $cindent) {
					$err .= "$sep$ctx\n";
					$sep = '';
				} else {
					$sep = "[...]\n";
				}
			}
			if ($err ne '') {
				ERROR("SWITCH_CASE_INDENT_LEVEL",
				      "switch and case should be at the same indent\n$hereline$err");
			}
		}

# if/while/etc brace do not go on next line, unless defining a do while loop,
# or if that brace on the next line is for something else
		if ($line =~ /^.\s*$Declare\b/ || $prevline =~ /^.\s*$Declare\s*$/) {
			# ignore function definitions with foreach in the name
		} elsif ($line =~ /(.*)\b((?:if|while|for|switch|[a-z_]*foreach[a-z_]*)\s*\(|do\b|else\b)/ && $line !~ /^.\s*\#/) {
			my $pre_ctx = "$1$2";

			my ($level, @ctx) = ctx_statement_level($linenr, $realcnt, 0);

			if ($line =~ /^\+\t{6,}/) {
				ERROR("DEEP_INDENTATION",
				      "Too many leading tabs - consider code refactoring\n" . $herecurr);
			}

			my $ctx_cnt = $realcnt - $#ctx - 1;
			my $ctx = join("\n", @ctx);

			my $ctx_ln = $linenr;
			my $ctx_skip = $realcnt;

			while ($ctx_skip > $ctx_cnt || ($ctx_skip == $ctx_cnt &&
					defined $lines[$ctx_ln - 1] &&
					$lines[$ctx_ln - 1] =~ /^-/)) {
				##print "SKIP<$ctx_skip> CNT<$ctx_cnt>\n";
				$ctx_skip-- if (!defined $lines[$ctx_ln - 1] || $lines[$ctx_ln - 1] !~ /^-/);
				$ctx_ln++;
			}

			#print "realcnt<$realcnt> ctx_cnt<$ctx_cnt>\n";
			#print "pre<$pre_ctx>\nline<$line>\nctx<$ctx>\nnext<$lines[$ctx_ln - 1]>\n";

			if ($ctx !~ /{\s*/ && defined($lines[$ctx_ln - 1]) && $lines[$ctx_ln - 1] =~ /^\+\s*{/) {
				ERROR("OPEN_BRACE",
				      "that open brace { should be on the previous line\n" .
					"$here\n$ctx\n$rawlines[$ctx_ln - 1]\n");
			}
			if ($level == 0 && $pre_ctx !~ /}\s*while\s*\($/ &&
			    $ctx =~ /\)\s*\;\s*$/ &&
			    defined $lines[$ctx_ln - 1])
			{
				my ($nlength, $nindent) = line_stats($lines[$ctx_ln - 1]);
				if ($nindent > $indent) {
					ERROR("TRAILING_SEMICOLON",
					      "trailing semicolon indicates no statements, indent implies otherwise\n" .
						"$here\n$ctx\n$rawlines[$ctx_ln - 1]\n");
				}
			}
		}

# Check relative indent for conditionals and blocks.
		if ($line =~ /\b(?:(?:if|while|for|[a-z_]*foreach[a-z_]*)\s*\(|(?:do|else)\b)/ && $line !~ /^.\s*#/ && $line !~ /\}\s*while\s*/) {
			($stat, $cond, $line_nr_next, $remain_next, $off_next) =
				ctx_statement_block($linenr, $realcnt, 0)
					if (!defined $stat);
			my ($s, $c) = ($stat, $cond);

			substr($s, 0, length($c), '');

			# remove inline comments
			$s =~ s/$;/ /g;
			$c =~ s/$;/ /g;

			# Find out how long the conditional actually is.
			my @newlines = ($c =~ /\n/gs);
			my $cond_lines = 1 + $#newlines;

			# Make sure we remove the line prefixes as we have
			# none on the first line, and are going to readd them
			# where necessary.
			$s =~ s/\n./\n/gs;
			while ($s =~ /\n\s+\\\n/) {
				$cond_lines += $s =~ s/\n\s+\\\n/\n/g;
			}

			# We want to check the first line inside the block
			# starting at the end of the conditional, so remove:
			#  1) any blank line termination
			#  2) any opening brace { on end of the line
			#  3) any do (...) {
			my $continuation = 0;
			my $check = 0;
			$s =~ s/^.*\bdo\b//;
			$s =~ s/^\s*{//;
			if ($s =~ s/^\s*\\//) {
				$continuation = 1;
			}
			if ($s =~ s/^\s*?\n//) {
				$check = 1;
				$cond_lines++;
			}

			# Also ignore a loop construct at the end of a
			# preprocessor statement.
			if (($prevline =~ /^.\s*#\s*define\s/ ||
			    $prevline =~ /\\\s*$/) && $continuation == 0) {
				$check = 0;
			}

			my $cond_ptr = -1;
			$continuation = 0;
			while ($cond_ptr != $cond_lines) {
				$cond_ptr = $cond_lines;

				# If we see an #else/#elif then the code
				# is not linear.
				if ($s =~ /^\s*\#\s*(?:else|elif)/) {
					$check = 0;
				}

				# Ignore:
				#  1) blank lines, they should be at 0,
				#  2) preprocessor lines, and
				#  3) labels.
				if ($continuation ||
				    $s =~ /^\s*?\n/ ||
				    $s =~ /^\s*#\s*?/ ||
				    $s =~ /^\s*$Ident\s*:/) {
					$continuation = ($s =~ /^.*?\\\n/) ? 1 : 0;
					if ($s =~ s/^.*?\n//) {
						$cond_lines++;
					}
				}
			}

			my (undef, $sindent) = line_stats("+" . $s);
			my $stat_real = raw_line($linenr, $cond_lines);

			# Check if either of these lines are modified, else
			# this is not this patch's fault.
			if (!defined($stat_real) ||
			    $stat !~ /^\+/ && $stat_real !~ /^\+/) {
				$check = 0;
			}
			if (defined($stat_real) && $cond_lines > 1) {
				$stat_real = "[...]\n$stat_real";
			}

			#print "line<$line> prevline<$prevline> indent<$indent> sindent<$sindent> check<$check> continuation<$continuation> s<$s> cond_lines<$cond_lines> stat_real<$stat_real> stat<$stat>\n";

			if ($check && $s ne '' &&
			    (($sindent % $tabsize) != 0 ||
			     ($sindent < $indent) ||
			     ($sindent == $indent &&
			      ($s !~ /^\s*(?:\}|\{|else\b)/)) ||
			     ($sindent > $indent + $tabsize))) {
				ERROR("SUSPECT_CODE_INDENT",
				      "suspect code indent for conditional statements ($indent, $sindent)\n" . $herecurr . "$stat_real\n");
			}
		}

		# Track the 'values' across context and added lines.
		my $opline = $line; $opline =~ s/^./ /;
		my ($curr_values, $curr_vars) =
				annotate_values($opline . "\n", $prev_values);
		$curr_values = $prev_values . $curr_values;
		if ($dbg_values) {
			my $outline = $opline; $outline =~ s/\t/ /g;
			print "$linenr > .$outline\n";
			print "$linenr > $curr_values\n";
			print "$linenr >  $curr_vars\n";
		}
		$prev_values = substr($curr_values, -1);

#ignore lines not being added
		next if ($line =~ /^[^\+]/);

# check for self assignments used to avoid compiler warnings
# e.g.:	int foo = foo, *bar = NULL;
#	struct foo bar = *(&(bar));
		if ($line =~ /^\+\s*(?:$Declare)?([A-Za-z_][A-Za-z\d_]*)\s*=/) {
			my $var = $1;
			if ($line =~ /^\+\s*(?:$Declare)?$var\s*=\s*(?:$var|\*\s*\(?\s*&\s*\(?\s*$var\s*\)?\s*\)?)\s*[;,]/) {
				ERROR("SELF_ASSIGNMENT",
				      "Do not use self-assignments to avoid compiler warnings\n" . $herecurr);
			}
		}

# check for dereferences that span multiple lines
		if ($prevline =~ /^\+.*$Lval\s*(?:\.|->)\s*$/ &&
		    $line =~ /^\+\s*(?!\#\s*(?!define\s+|if))\s*$Lval/) {
			$prevline =~ /($Lval\s*(?:\.|->))\s*$/;
			my $ref = $1;
			$line =~ /^.\s*($Lval)/;
			$ref .= $1;
			$ref =~ s/\s//g;
			ERROR("MULTILINE_DEREFERENCE",
			      "Avoid multiple line dereference - prefer '$ref'\n" . $hereprev);
		}

# TEST: allow direct testing of the type matcher.
		if ($dbg_type) {
			if ($line =~ /^.\s*$Declare\s*$/) {
				ERROR("TEST_TYPE",
				      "TEST: is type\n" . $herecurr);
			} elsif ($dbg_type > 1 && $line =~ /^.+($Declare)/) {
				ERROR("TEST_NOT_TYPE",
				      "TEST: is not type ($1 is)\n". $herecurr);
			}
			next;
		}
# TEST: allow direct testing of the attribute matcher.
		if ($dbg_attr) {
			if ($line =~ /^.\s*$Modifier\s*$/) {
				ERROR("TEST_ATTR",
				      "TEST: is attr\n" . $herecurr);
			} elsif ($dbg_attr > 1 && $line =~ /^.+($Modifier)/) {
				ERROR("TEST_NOT_ATTR",
				      "TEST: is not attr ($1 is)\n". $herecurr);
			}
			next;
		}

# check for initialisation to aggregates open brace on the next line
		if ($line =~ /^.\s*{/ && $line !~ /}\s*;\s*$/ &&
		    $prevline =~ /(?:^|[^=])=\s*$/) {
			ERROR("OPEN_BRACE",
			      "that open brace { should be on the previous line\n" . $hereprev);
		}

#
# Checks which are anchored on the added line.
#

# check for malformed paths in #include statements (uses RAW line)
		if ($rawline =~ m{^.\s*\#\s*include\s+[<"](.*)[">]}) {
			my $path = $1;
			if ($path =~ m{//}) {
				ERROR("MALFORMED_INCLUDE",
				      "malformed #include filename\n" . $herecurr);
			}
		}

# no C99 // comments
		if ($line =~ m{//}) {
			ERROR("C99_COMMENTS",
			      "do not use C99 // comments\n" . $herecurr);
		}
		# Remove C99 comments.
		$line =~ s@//.*@@;
		$opline =~ s@//.*@@;

# check for misordered declarations of char/short/int/long with signed/unsigned
		while ($sline =~ m{(\b$TypeMisordered\b)}g) {
			my $tmp = trim($1);
			ERROR("MISORDERED_TYPE",
			      "type '$tmp' should be specified in [[un]signed] [short|int|long|long long] order\n" . $herecurr);
		}

# check for unnecessary <signed> int declarations of short/long/long long
		while ($sline =~ m{\b($TypeMisordered(\s*\*)*|$C90_int_types)\b}g) {
			my $type = trim($1);
			next if ($type !~ /\bint\b/);
			next if ($type !~ /\b(?:short|long\s+long|long)\b/);
			my $new_type = $type;
			$new_type =~ s/\b\s*int\s*\b/ /;
			$new_type =~ s/\b\s*(?:un)?signed\b\s*/ /;
			$new_type =~ s/^const\s+//;
			$new_type = "unsigned $new_type" if ($type =~ /\bunsigned\b/);
			$new_type = "const $new_type" if ($type =~ /^const\b/);
			$new_type =~ s/\s+/ /g;
			$new_type = trim($new_type);
			ERROR("UNNECESSARY_INT",
			      "Prefer '$new_type' over '$type' as the int is unnecessary\n" . $herecurr);
		}

# check for static const char * arrays.
		if ($line =~ /\bstatic\s+const\s+char\s*\*\s*(\w+)\s*\[\s*\]\s*=\s*/) {
			ERROR("STATIC_CONST_CHAR_ARRAY",
			      "static const char * array should probably be static const char * const\n" .
				$herecurr);
		}

# check for initialized const char arrays that should be static const
		if ($line =~ /^\+\s*const\s+(char|unsigned\s+char|_*u8|(?:[us]_)?int8_t)\s+\w+\s*\[\s*(?:\w+\s*)?\]\s*=\s*"/) {
			ERROR("STATIC_CONST_CHAR_ARRAY",
			      "const array should probably be static const\n" . $herecurr);
		}

# check for static char foo[] = "bar" declarations.
		if ($line =~ /\bstatic\s+char\s+(\w+)\s*\[\s*\]\s*=\s*"/) {
			ERROR("STATIC_CONST_CHAR_ARRAY",
			      "static char array declaration should probably be static const char\n" .
				$herecurr);
		}

# check for const <foo> const where <foo> is not a pointer or array type
		if ($sline =~ /\bconst\s+($BasicType)\s+const\b/) {
			my $found = $1;
			if ($sline =~ /\bconst\s+\Q$found\E\s+const\b\s*\*/) {
				ERROR("CONST_CONST",
				      "'const $found const *' should probably be 'const $found * const'\n" . $herecurr);
			} elsif ($sline !~ /\bconst\s+\Q$found\E\s+const\s+\w+\s*\[/) {
				ERROR("CONST_CONST",
				      "'const $found const' should probably be 'const $found'\n" . $herecurr);
			}
		}

# check for const static or static <non ptr type> const declarations
# prefer 'static const <foo>' over 'const static <foo>' and 'static <foo> const'
		if ($sline =~ /^\+\s*const\s+static\s+($Type)\b/ ||
		    $sline =~ /^\+\s*static\s+($BasicType)\s+const\b/) {
			ERROR("STATIC_CONST",
			      "Move const after static - use 'static const $1'\n" . $herecurr);
		}

# check for non-global char *foo[] = {"bar", ...} declarations.
		if (!$is_test && $line =~ /^.\s+(?:static\s+|const\s+)?char\s+\*\s*\w+\s*\[\s*\]\s*=\s*\{/) {
			ERROR("STATIC_CONST_CHAR_ARRAY",
			      "char * array declaration might be better as static const\n" . $herecurr);
		}

# check for sizeof(foo)/sizeof(foo[0]) that could be lengthof(foo)
		if ($line =~ m@\bsizeof\s*\(\s*($Lval)\s*\)@) {
			my $array = $1;
			if ($line =~ m@\b(sizeof\s*\(\s*\Q$array\E\s*\)\s*/\s*sizeof\s*\(\s*\Q$array\E\s*\[\s*0\s*\]\s*\))@) {
				my $array_div = $1;
				ERROR("ARRAY_SIZE",
				      "Prefer lengthof($array)\n" . $herecurr);
			}
		}

# check for function declarations without arguments like "int foo()" or "int (*foo)()"
		if ($realfile =~ /\.c$/ &&
		    ($line =~ /^\+(?:typedef\s+)?$Declare\s*((?:$Ident|\(\s*\*\s*$Ident\s*\)))\s*\(\s*\)/ ||
		     ($prevline =~ /^\+(?:typedef\s+)?$Declare\s*$/ && $line =~ /^\+\s*((?:$Ident|\(\s*\*\s*$Ident\s*\)))\s*\(\s*\)/))) {
			ERROR("FUNCTION_WITHOUT_ARGS",
			      "Bad function definition - $1() should probably be $1(void)\n" . $herecurr);
		}

# check that function name and return value type are placed on different lines
		if ($line =~ /^\+\s*$Declare\s*(?:box_set_|generic_)/) {
			# ignore box_set_XXX and generic_XXX
		} elsif ($line =~ /^\+(?:typedef\s+)?$Declare\s*(?:$Ident|\(\s*\*\s*$Ident\s*\))\s*\(/) {
			ERROR("FUNCTION_NAME_NO_NEWLINE",
			      "Function name and return value type should be placed on different lines\n" . $herecurr)
		}

# check that there's no new line after typedef
		if ($line =~ /^\+\s*typedef\s*$/) {
			ERROR("TYPEDEF_NEWLINE",
			      "Redundant new line after typedef\n" . $herecurr);
		}

# check for new typedefs, only function parameters and sparse annotations
# make sense.
		if ($line =~ /\btypedef\s/ &&
		    $line !~ /\btypedef\s+$Type$/ &&
		    $line !~ /\btypedef\s+$Type\s*\(\s*\*?$Ident\s*\)\s*\(/ &&
		    $line !~ /\btypedef\s+$Type\s+$Ident\s*\(/ &&
# allow new typedefs ending with double underscore - we may use them internally to tweak the compiler
# typedefs that start with `box_` or `tt_` is a part of the internal API so they are allowed, as well
		    $line !~ /(?:__|\b(?:box|tt)_$Ident\_t)\s*;/ &&
		    $line !~ /\b$typeTypedefs\b/) {
			ERROR("NEW_TYPEDEFS",
			      "do not add new typedefs\n" . $herecurr);
		}

# * goes on variable not on type
		# (char*[ const])
		while ($line =~ m{(\($NonptrType(\s*(?:$Modifier\b\s*|\*\s*)+)\))}g) {
			#print "AA<$1>\n";
			my ($ident, $from, $to) = ($1, $2, $2);

			# Should start with a space.
			$to =~ s/^(\S)/ $1/;
			# Should not end with a space.
			$to =~ s/\s+$//;
			# '*'s should not have spaces between.
			while ($to =~ s/\*\s+\*/\*\*/) {
			}

##			print "1: from<$from> to<$to> ident<$ident>\n";
			if ($from ne $to) {
				ERROR("POINTER_LOCATION",
				      "\"(foo$from)\" should be \"(foo$to)\"\n" .  $herecurr);
			}
		}
		while ($line =~ m{(\b$NonptrType(\s*(?:$Modifier\b\s*|\*\s*)+)($Ident))}g) {
			#print "BB<$1>\n";
			my ($match, $from, $to, $ident) = ($1, $2, $2, $3);

			# Should start with a space.
			$to =~ s/^(\S)/ $1/;
			# Should not end with a space.
			$to =~ s/\s+$//;
			# '*'s should not have spaces between.
			while ($to =~ s/\*\s+\*/\*\*/) {
			}
			# Modifiers should have spaces.
			$to =~ s/(\b$Modifier$)/$1 /;

##			print "2: from<$from> to<$to> ident<$ident>\n";
			if ($from ne $to && $ident !~ /^$Modifier$/) {
				ERROR("POINTER_LOCATION",
				      "\"foo${from}bar\" should be \"foo${to}bar\"\n" .  $herecurr);
			}
		}

# & goes on type not on variable
		while ($line =~ m{\b$NonptrType(\s*\&{1,2}\s*)$Ident}g) {
			my ($from, $to) = ($1, $1);
			# Should start with a space.
			$to =~ s/^(\S)/ $1/;
			# Should not end with a space.
			$to =~ s/\s+$//;
			if ($from ne $to) {
				ERROR("REFERENCE_LOCATION",
				      "\"foo${from}bar\" should be \"foo${to}bar\"\n" .  $herecurr);
			}
		}

# open braces for enum, union and struct go on the same line.
		if ($line =~ /^.\s*{/ &&
		    $prevline =~ /^.\s*(?:typedef\s+)?(enum|union|struct)(?:\s+$Ident)?\s*$/) {
			ERROR("OPEN_BRACE",
			      "open brace '{' following $1 go on the same line\n" . $hereprev);
		}

# missing space after union, struct or enum definition
		if ($line =~ /^.\s*(?:typedef\s+)?(enum|union|struct)(?:\s+$Ident){1,2}[=\{]/) {
			ERROR("SPACING",
			      "missing space after $1 definition\n" . $herecurr);
		}

# check for spacing round square brackets; allowed:
#  1. with a type on the left -- int [] a;
#  2. at the beginning of a line for slice initialisers -- [0...10] = 5,
#  3. inside a curly brace -- = { [0...10] = 5 }
#  4. after = for lamda expressions -- = [](int a, int b) { return a + b; }
		while ($line =~ /(.*?\s)\[/g) {
			my ($where, $prefix) = ($-[1], $1);
			if ($prefix !~ /$Type\s+$/ &&
			    ($where != 0 || $prefix !~ /^.\s+$/) &&
			    $prefix !~ /[{,:=]\s+$/) {
				ERROR("BRACKET_SPACE",
				      "space prohibited before open square bracket '['\n" . $herecurr);
			}
		}

# check for spaces between functions and their parentheses.
		while ($line =~ /($Ident)\s+\(/g) {
			my $name = $1;
			my $ctx_before = substr($line, 0, $-[1]);
			my $ctx = "$ctx_before$name";

			# Ignore those directives where spaces _are_ permitted.
			if ($name =~ /^(?:
				if|for|while|switch|return|case|catch|
				volatile|__volatile__|
				__attribute__|format|__extension__|
				asm|__asm__)$/x)
			{
			# cpp #define statements have non-optional spaces, ie
			# if there is a space between the name and the open
			# parenthesis it is simply not a parameter group.
			} elsif ($ctx_before =~ /^.\s*\#\s*define\s*$/) {

			# cpp #elif statement condition may start with a (
			} elsif ($ctx =~ /^.\s*\#\s*elif\s*$/) {

			# If this whole things ends with a type its most
			# likely a typedef for a function.
			} elsif ($ctx =~ /$Type$/) {

			} else {
				ERROR("SPACING",
				      "space prohibited between function name and open parenthesis '('\n" . $herecurr);
			}
		}

# Check operator spacing.
		if (!($line=~/\#\s*include/)) {
			my $ops = qr{
				<<=|>>=|<=|>=|==|!=|
				\+=|-=|\*=|\/=|%=|\^=|\|=|&=|
				=>|->|<<|>>|<|>|=|!|~|
				&&|\|\||,|\^|\+\+|--|&|\||\+|-|\*|\/|%|
				\?:|\?|::|:
			}x;
			my @elements = split(/($ops|;)/, $opline);

##			print("element count: <" . $#elements . ">\n");
##			foreach my $el (@elements) {
##				print("el: <$el>\n");
##			}

			my $off = 0;
			my $blank = copy_spacing($opline);

			for (my $n = 0; $n < $#elements; $n += 2) {

				$off += length($elements[$n]);

				# Pick up the preceding and succeeding characters.
				my $ca = substr($opline, 0, $off);
				my $cc = '';
				if (length($opline) >= ($off + length($elements[$n + 1]))) {
					$cc = substr($opline, $off + length($elements[$n + 1]));
				}
				my $cb = "$ca$;$cc";

				my $a = '';
				$a = 'V' if ($elements[$n] ne '');
				$a = 'W' if ($elements[$n] =~ /\s$/);
				$a = 'C' if ($elements[$n] =~ /$;$/);
				$a = 'B' if ($elements[$n] =~ /(\[|\()$/);
				$a = 'O' if ($elements[$n] eq '');
				$a = 'E' if ($ca =~ /^\s*$/);

				my $op = $elements[$n + 1];

				my $c = '';
				if (defined $elements[$n + 2]) {
					$c = 'V' if ($elements[$n + 2] ne '');
					$c = 'W' if ($elements[$n + 2] =~ /^\s/);
					$c = 'C' if ($elements[$n + 2] =~ /^$;/);
					$c = 'B' if ($elements[$n + 2] =~ /^(\)|\]|;)/);
					$c = 'O' if ($elements[$n + 2] eq '');
					$c = 'E' if ($elements[$n + 2] =~ /^\s*\\$/);
				} else {
					$c = 'E';
				}

				my $ctx = "${a}x${c}";

				my $at = "(ctx:$ctx)";

				my $ptr = substr($blank, 0, $off) . "^";
				my $hereptr = "$hereline$ptr\n";

				# Pull out the value of this operator.
				my $op_type = substr($curr_values, $off + 1, 1);

				# Get the full operator variant.
				my $opv = $op . substr($curr_vars, $off, 1);

				# Ignore operators passed as parameters.
				if ($op_type ne 'V' &&
				    $ca =~ /\s$/ && $cc =~ /^\s*[,\)]/) {

#				# Ignore comments
#				} elsif ($op =~ /^$;+$/) {

				# ; should have either the end of line or a space or \ after it
				} elsif ($op eq ';') {
					if ($ctx !~ /.x[WEBC]/ &&
					    $cc !~ /^\\/ && $cc !~ /^;/) {
						ERROR("SPACING",
						      "space required after that '$op' $at\n" . $hereptr);
					}

				# // is a comment
				} elsif ($op eq '//') {

				#   :   when part of a bitfield
				} elsif ($opv eq ':B') {
					# skip the bitfield test for now

				} elsif ($op eq ':' && $ca =~ /^\s*(?:class|struct)\b/) {
					# skip class declaration

				} elsif ($realfile =~ /\.(h|cc)$/ && $op =~ /[<>]/ &&
					 $opline =~ /(?:^|<).*(?:,\s*$|>)/) {
					# skip template

				} elsif ($realfile =~ /\.(h|cc)$/ && $op =~ /[&*]/ &&
					 $opline =~ /(\Q$op\E[>,])/ && $-[1] == $off) {
					# pointer or reference in template arguments

				} elsif ($realfile =~ /\.(h|cc)$/ && $op =~ /[=&]/ && $ctx eq 'BxB') {
					# lambda capture

				} elsif ($realfile =~ /\.(h|cc)$/ &&
					 $opline =~ /operator\s*(\Q$op\E)\s*\(/ && $-[1] == $off) {
					# C++ operator overload
					if ($ctx =~ /Wx.|.xW/) {
						ERROR("SPACING",
						      "spaces prohibited around that '$op' $at\n" . $hereptr);
					}

				# No spaces for:
				#   ->
				} elsif ($op eq '->') {
					if ($ctx =~ /Wx.|.xW/) {
						ERROR("SPACING",
						      "spaces prohibited around that '$op' $at\n" . $hereptr);
					}

				# No spaces after ::. A space before :: is allowed for global namespace specifier.
				} elsif ($op eq '::') {
					if ($ctx =~ /.xW/) {
						ERROR("SPACING",
						      "spaces prohibited after that '$op' $at\n" . $hereptr);
					}

				# , must not have a space before and must have a space on the right.
				} elsif ($op eq ',') {
					if ($ctx =~ /Wx./) {
						ERROR("SPACING",
						      "space prohibited before that '$op' $at\n" . $hereptr);
					}
					if ($ctx !~ /.x[WEC]/ && $cc !~ /^}/) {
						ERROR("SPACING",
						      "space required after that '$op' $at\n" . $hereptr);
					}

				# '*' as part of a type definition -- reported already.
				} elsif ($opv eq '*_') {
					#warn "'*' is part of type\n";

				# '&' or '&&' as part of a type definition -- reported already.
				} elsif ($opv eq '&_' or $opv eq '&&_') {
					#warn "'&' is part of type\n";

				# unary operators should have a space before and
				# none after.  May be left adjacent to another
				# unary operator, or a cast
				} elsif ($op eq '!' || $op eq '~' ||
					 $opv eq '*U' || $opv eq '-U' || $opv eq '+U' ||
					 $opv eq '&U' || $opv eq '&&U') {
					if ($op eq '~' && $ca =~ /::$/) {
						# ~ before the name of a destructor
					} elsif ($ctx !~ /[WEBC]x./ && $ca !~ /(?:\)|!|~|\*|-|\&|\||\+\+|\-\-|\{)$/) {
						ERROR("SPACING",
						      "space required before that '$op' $at\n" . $hereptr);
					}
					if ($op eq '*' && $cc =~/\s*$Modifier\b/) {
						# A unary '*' may be const

					} elsif ($ctx =~ /.xW/) {
						ERROR("SPACING",
						      "space prohibited after that '$op' $at\n" . $hereptr);
					}

				# unary ++ and unary -- are allowed no space on one side.
				} elsif ($op eq '++' or $op eq '--') {
					if ($ctx !~ /[WEOBC]x[^W]/ && $ctx !~ /[^W]x[WOBEC]/) {
						ERROR("SPACING",
						      "space required one side of that '$op' $at\n" . $hereptr);
					}
					if ($ctx =~ /Wx[BE]/ ||
					    ($ctx =~ /Wx./ && $cc =~ /^;/)) {
						ERROR("SPACING",
						      "space prohibited before that '$op' $at\n" . $hereptr);
					}
					if ($ctx =~ /ExW/) {
						ERROR("SPACING",
						      "space prohibited after that '$op' $at\n" . $hereptr);
					}

				# << and >> may either have or not have spaces both sides
				} elsif ($op eq '<<' or $op eq '>>' or
					 $op eq '&' or $op eq '^' or $op eq '|' or
					 $op eq '+' or $op eq '-' or
					 $op eq '*' or $op eq '/' or
					 $op eq '%')
				{
					if (defined $elements[$n + 2] && $ctx !~ /[EW]x[EW]/ &&
					    # Ignore floating point constants such as 1e-5 or 3.14e+10.
					    !($op =~ /[+-]/ && $elements[$n] =~ /^\s*[0-9\.]*[eE]$/)) {
						ERROR("SPACING",
						      "spaces needed around that '$op' $at\n" . $hereptr);
					} elsif (!defined $elements[$n + 2] && $ctx !~ /Wx[OE]/) {
						ERROR("SPACING",
						      "space needed before that '$op' $at\n" . $hereptr);
					}

				# A colon needs no spaces before when it is
				# terminating a case value or a label.
				} elsif ($opv eq ':C' || $opv eq ':L') {
					if ($ctx =~ /Wx./) {
						ERROR("SPACING",
						      "space prohibited before that '$op' $at\n" . $hereptr);
					}

				# All the others need spaces both sides.
				} elsif ($ctx !~ /[EWC]x[CWE]/) {
					my $ok = 0;

					# Ignore email addresses <foo@bar>
					if (($op eq '<' &&
					     $cc =~ /^\S+\@\S+>/) ||
					    ($op eq '>' &&
					     $ca =~ /<\S+\@\S+$/))
					{
						$ok = 1;
					}

					# for asm volatile statements
					# ignore a colon with another
					# colon immediately before or after
					if (($op eq ':') &&
					    ($ca =~ /:$/ || $cc =~ /^:/)) {
						$ok = 1;
					}

					if ($ok == 0) {
						ERROR("SPACING",
						      "spaces required around that '$op' $at\n" . $hereptr);
					}
				}
				$off += length($elements[$n + 1]);
			}
		}

# check for whitespace before a non-naked semicolon
		if ($line =~ /^\+.*\S\s+;\s*$/) {
			ERROR("SPACING",
			      "space prohibited before semicolon\n" . $herecurr);
		}

# check for multiple assignments
		if ($line =~ /^.\s*$Lval\s*=\s*$Lval\s*=(?!=)/) {
			ERROR("MULTIPLE_ASSIGNMENTS",
			      "multiple assignments should be avoided\n" . $herecurr);
		}

#need space before brace following if, while, etc
		if (($line =~ /\(.*\)\{/ && $line !~ /\($Type\)\{/) ||
		    $line =~ /\b(?:else|do)\{/) {
			ERROR("SPACING",
			      "space required before the open brace '{'\n" . $herecurr);
		}

# closing brace should have a space following it when it has anything
# on the line
		if ($line =~ /}(?!(?:,|;|\)|\}))\S/) {
			ERROR("SPACING",
			      "space required after that close brace '}'\n" . $herecurr);
		}

# check spacing on square brackets
		if ($line =~ /\[\s/ && $line !~ /\[\s*$/) {
			ERROR("SPACING",
			      "space prohibited after that open square bracket '['\n" . $herecurr);
		}
		if ($line =~ /\s\]/) {
			ERROR("SPACING",
			      "space prohibited before that close square bracket ']'\n" . $herecurr);
		}

# check spacing on parentheses
		if ($line =~ /\(\s/ && $line !~ /\(\s*(?:\\)?$/ &&
		    $line !~ /for\s*\(\s+;/) {
			ERROR("SPACING",
			      "space prohibited after that open parenthesis '('\n" . $herecurr);
		}
		if ($line =~ /(\s+)\)/ && $line !~ /^.\s*\)/ &&
		    $line !~ /for\s*\(.*;\s+\)/ &&
		    $line !~ /:\s+\)/) {
			ERROR("SPACING",
			      "space prohibited before that close parenthesis ')'\n" . $herecurr);
		}

# check unnecessary parentheses around addressof/dereference single $Lvals
# ie: &(foo->bar) should be &foo->bar and *(foo->bar) should be *foo->bar

		while ($line =~ /(?:[^&]&\s*|\*)\(\s*($Ident\s*(?:$Member\s*)+)\s*\)/g) {
			my $var = $1;
			ERROR("UNNECESSARY_PARENTHESES",
			      "Unnecessary parentheses around $var\n" . $herecurr);
		}

# check for unnecessary parentheses around function pointer uses
# ie: (foo->bar)(); should be foo->bar();
# but not "if (foo->bar) (" to avoid some false positives
		if ($line =~ /(\bif\s*|)(\(\s*$Ident\s*(?:$Member\s*)+\))[ \t]*\(/ && $1 !~ /^if/) {
			my $var = $2;
			ERROR("UNNECESSARY_PARENTHESES",
			      "Unnecessary parentheses around function pointer $var\n" . $herecurr);
		}

# check that goto labels aren't indented (allow a single space indentation)
# and ignore bitfield definitions like foo:1 and C++ scope resolution like foo::bar
# Strictly, labels can have whitespace after the identifier and before the :
# but this is not allowed here as many ?: uses would appear to be labels
		if ($sline =~ /^.\s+[A-Za-z_][A-Za-z\d_]*:(?!\s*\d+|:)/ &&
		    $sline !~ /^. [A-Za-z\d_][A-Za-z\d_]*:/ &&
		    $sline !~ /^.\s+default:/) {
			ERROR("INDENTED_LABEL",
			      "labels should not be indented\n" . $herecurr);
		}

# check if a statement with a comma should be two statements like:
#	foo = bar(),	/* comma should be semicolon */
#	bar = baz();
		if (defined($stat) &&
		    $stat =~ /^\+\s*(?:$Lval\s*$Assignment\s*)?$FuncArg\s*,\s*(?:$Lval\s*$Assignment\s*)?$FuncArg\s*;\s*$/) {
			my $cnt = statement_rawlines($stat);
			my $herectx = get_stat_here($linenr, $cnt, $here);
			ERROR("SUSPECT_COMMA_SEMICOLON",
			      "Possible comma where semicolon could be used\n" . $herectx);
		}

# return is not a function
		if (defined($stat) && $stat =~ /^.\s*return(\s*)\(/s) {
			my $spacing = $1;
			if ($stat =~ /^.\s*return\s*($balanced_parens)\s*;\s*$/) {
				my $value = $1;
				$value = deparenthesize($value);
				if ($value =~ m/^\s*$FuncArg\s*(?:\?|$)/) {
					ERROR("RETURN_PARENTHESES",
					      "return is not a function, parentheses are not required\n" . $herecurr);
				}
			} elsif ($spacing !~ /\s+/) {
				ERROR("SPACING",
				      "space required before the open parenthesis '('\n" . $herecurr);
			}
		}

# unnecessary return in a void function
# at end-of-function, with the previous line a single leading tab, then return;
# and the line before that not a goto label target like "out:"
		if ($sline =~ /^[ \+]}\s*$/ &&
		    $prevline =~ /^\+\treturn\s*;\s*$/ &&
		    $linenr >= 3 &&
		    $lines[$linenr - 3] =~ /^[ +]/ &&
		    $lines[$linenr - 3] !~ /^[ +]\s*$Ident\s*:/) {
			ERROR("RETURN_VOID",
			      "void function return statements are not generally useful\n" . $hereprev);
		}

# if statements using unnecessary parentheses - ie: if ((foo == bar))
		if ($line =~ /\bif\s*((?:\(\s*){2,})/) {
			my $openparens = $1;
			my $count = $openparens =~ tr@\(@\(@;
			my $msg = "";
			if ($line =~ /\bif\s*(?:\(\s*){$count,$count}$LvalOrFunc\s*($Compare)\s*$LvalOrFunc(?:\s*\)){$count,$count}/) {
				my $comp = $4;	#Not $1 because of $LvalOrFunc
				$msg = " - maybe == should be = ?" if ($comp eq "==");
				ERROR("UNNECESSARY_PARENTHESES",
				      "Unnecessary parentheses$msg\n" . $herecurr);
			}
		}

# check for a closing parenthesis on a separate line
		if ($line =~ /^\+\s*\)\s*[;{]?\s*$/) {
			ERROR("DANGLING_PARENTHESIS",
			      "Closing parenthesis should follow function argument or operand\n" . $herecurr);
		}

# comparisons with a constant or upper case identifier on the left
#	avoid cases like "foo + BAR < baz"
#	only fix matches surrounded by parentheses to avoid incorrect
#	conversions like "FOO < baz() + 5" being "misfixed" to "baz() > FOO + 5"
		if ($line =~ /^\+(.*)\b(?:$Constant|[A-Z_][A-Z0-9_]*)\s*$Compare\s*($LvalOrFunc)/) {
			my $lead = $1;
			my $to = $2;
			if ($lead !~ /(?:$Operators|\.)\s*$/ &&
			    $to !~ /^(?:Constant|[A-Z_][A-Z0-9_]*)$/) {
				ERROR("CONSTANT_COMPARISON",
				      "Comparisons should place the constant on the right side of the test\n" . $herecurr);
			}
		}

# Need a space before open parenthesis after if, while etc
		if ($line =~ /\b(if|while|for|switch)\(/) {
			ERROR("SPACING",
			      "space required before the open parenthesis '('\n" . $herecurr);
		}

# Check for illegal assignment in if conditional -- and check for trailing
# statements after the conditional.
		if ($line =~ /do\s*(?!{)/) {
			($stat, $cond, $line_nr_next, $remain_next, $off_next) =
				ctx_statement_block($linenr, $realcnt, 0)
					if (!defined $stat);
			my ($stat_next) = ctx_statement_block($line_nr_next,
						$remain_next, $off_next);
			$stat_next =~ s/\n./\n /g;
			##print "stat<$stat> stat_next<$stat_next>\n";

			if ($stat_next =~ /^\s*while\b/) {
				# If the statement carries leading newlines,
				# then count those as offsets.
				my ($whitespace) =
					($stat_next =~ /^((?:\s*\n[+-])*\s*)/s);
				my $offset =
					statement_rawlines($whitespace) - 1;

				$suppress_whiletrailers{$line_nr_next +
								$offset} = 1;
			}
		}
		if (!defined $suppress_whiletrailers{$linenr} &&
		    defined($stat) && defined($cond) &&
		    $line =~ /\b(?:if|while|for)\s*\(/ && $line !~ /^.\s*#/) {
			my ($s, $c) = ($stat, $cond);

			if ($c =~ /\bif\s*\(.*[^<>!=]=[^=].*/s) {
				ERROR("ASSIGN_IN_IF",
				      "do not use assignment in if condition\n" . $herecurr);
			}

			# Find out what is on the end of the line after the
			# conditional.
			substr($s, 0, length($c), '');
			$s =~ s/\n.*//g;
			$s =~ s/$;//g;	# Remove any comments
			if (length($c) && $s !~ /^\s*{?\s*\\*\s*$/ &&
			    $c !~ /}\s*while\s*/)
			{
				# Find out how long the conditional actually is.
				my @newlines = ($c =~ /\n/gs);
				my $cond_lines = 1 + $#newlines;
				my $stat_real = '';

				$stat_real = raw_line($linenr, $cond_lines)
							. "\n" if ($cond_lines);
				if (defined($stat_real) && $cond_lines > 1) {
					$stat_real = "[...]\n$stat_real";
				}

				ERROR("TRAILING_STATEMENTS",
				      "trailing statements should be on next line\n" . $herecurr . $stat_real);
			}
		}

# Check for bitwise tests written as boolean
		if ($line =~ /
			(?:
				(?:\[|\(|\&\&|\|\|)
				\s*0[xX][0-9]+\s*
				(?:\&\&|\|\|)
			|
				(?:\&\&|\|\|)
				\s*0[xX][0-9]+\s*
				(?:\&\&|\|\||\)|\])
			)/x)
		{
			ERROR("HEXADECIMAL_BOOLEAN_TEST",
			      "boolean test with hexadecimal, perhaps just 1 \& or \|?\n" . $herecurr);
		}

# if and else should not have general statements after it
		if ($line =~ /^.\s*(?:}\s*)?else\b(.*)/) {
			my $s = $1;
			$s =~ s/$;//g;	# Remove any comments
			if ($s !~ /^\s*(?:\sif|(?:{|)\s*\\?\s*$)/) {
				ERROR("TRAILING_STATEMENTS",
				      "trailing statements should be on next line\n" . $herecurr);
			}
		}
# if should not continue a brace
		if ($line =~ /}\s*if\b/) {
			ERROR("TRAILING_STATEMENTS",
			      "trailing statements should be on next line (or did you mean 'else if'?)\n" .
				$herecurr);
		}
# case and default should not have general statements after them
		if ($line =~ /^.\s*(?:case\s*.*|default\s*):/g &&
		    $line !~ /\G(?:
			(?:\s*$;*)(?:\s*{)?(?:\s*$;*)(?:\s*\\)?\s*$|
			\s*return\s+
		    )/xg)
		{
			ERROR("TRAILING_STATEMENTS",
			      "trailing statements should be on next line\n" . $herecurr);
		}

		# Check for }<nl>else {, these must be at the same
		# indent level to be relevant to each other.
		if ($prevline=~/}\s*$/ and $line=~/^.\s*else\s*/ &&
		    $previndent == $indent) {
			ERROR("ELSE_AFTER_BRACE",
			      "else should follow close brace '}'\n" . $hereprev);
		}

		if ($prevline=~/}\s*$/ and $line=~/^.\s*while\s*/ &&
		    $previndent == $indent) {
			my ($s, $c) = ctx_statement_block($linenr, $realcnt, 0);

			# Find out what is on the end of the line after the
			# conditional.
			substr($s, 0, length($c), '');
			$s =~ s/\n.*//g;

			if ($s =~ /^\s*;/) {
				ERROR("WHILE_AFTER_BRACE",
				      "while should follow close brace '}'\n" . $hereprev);
			}
		}

# multi-statement macros should be enclosed in a do while loop, grab the
# first statement and ensure its the whole macro if its not enclosed
# in a known good container
		if ($line =~ /^.\s*\#\s*define\s*$Ident(\()?/) {
			my $ln = $linenr;
			my $cnt = $realcnt;
			my ($off, $dstat, $dcond, $rest);
			my $ctx = '';
			my $has_flow_statement = 0;
			my $has_arg_concat = 0;
			($dstat, $dcond, $ln, $cnt, $off) =
				ctx_statement_block($linenr, $realcnt, 0);
			$ctx = $dstat;
			#print "dstat<$dstat> dcond<$dcond> cnt<$cnt> off<$off>\n";
			#print "LINE<$lines[$ln-1]> len<" . length($lines[$ln-1]) . "\n";

			$has_flow_statement = 1 if ($ctx =~ /\b(goto|return)\b/);
			$has_arg_concat = 1 if ($ctx =~ /\#\#/ && $ctx !~ /\#\#\s*(?:__VA_ARGS__|args)\b/);

			$dstat =~ s/^.\s*\#\s*define\s+$Ident(\([^\)]*\))?\s*//;
			my $define_args = $1;
			my $define_stmt = $dstat;
			my @def_args = ();

			if (defined $define_args && $define_args ne "") {
				$define_args = substr($define_args, 1, length($define_args) - 2);
				$define_args =~ s/\s*//g;
				$define_args =~ s/\\\+?//g;
				@def_args = split(",", $define_args);
			}

			$dstat =~ s/$;//g;
			$dstat =~ s/\\\n.//g;
			$dstat =~ s/^\s*//s;
			$dstat =~ s/\s*$//s;

			# Flatten any parentheses and braces
			while ($dstat =~ s/\([^\(\)]*\)/1u/ ||
			       $dstat =~ s/\{[^\{\}]*\}/1u/ ||
			       $dstat =~ s/.\[[^\[\]]*\]/1u/)
			{
			}

			# Flatten any obvious string concatenation.
			while ($dstat =~ s/($String)\s*$Ident/$1/ ||
			       $dstat =~ s/$Ident\s*($String)/$1/)
			{
			}

			# Make asm volatile uses seem like a generic function
			$dstat =~ s/\b_*asm_*\s+_*volatile_*\b/asm_volatile/g;

			my $exceptions = qr{
				$Declare|
				__typeof__\(|
				union|
				struct|
				\.$Ident\s*=\s*|
				^\"|\"$|
				^\[
			}x;
			#print "REST<$rest> dstat<$dstat> ctx<$ctx>\n";

			$ctx =~ s/\n*$//;
			my $stmt_cnt = statement_rawlines($ctx);
			my $herectx = get_stat_here($linenr, $stmt_cnt, $here);

			if (!$is_test && $dstat ne '' &&
			    !($dstat =~ /,/ && $dstat !~ /;/) &&			# comma-separated list used as array initializer
			    $dstat !~ /^(?:$Ident|-?$Constant),$/ &&			# 10, // foo(),
			    $dstat !~ /^(?:$Ident|-?$Constant);$/ &&			# foo();
			    $dstat !~ /^[!~-]?(?:$Lval|$Constant)$/ &&			# 10 // foo() // !foo // ~foo // -foo // foo->bar // foo.bar->baz
			    $dstat !~ /^'X'$/ && $dstat !~ /^'XX'$/ &&			# character constants
			    $dstat !~ /$exceptions/ &&
			    $dstat !~ /^\.$Ident\s*=/ &&				# .foo =
			    $dstat !~ /^(?:\#\s*$Ident|\#\s*$Constant)\s*$/ &&		# stringification #foo
			    $dstat !~ /^(?:$Ident\s*)+$/ &&				# compound code generation macros: foo() bar() buzz()
			    $dstat !~ /^do\s*$Constant\s*while\s*$Constant;?$/ &&	# do {...} while (...); // do {...} while (...)
			    $dstat !~ /^while\s*$Constant\s*$Constant\s*$/ &&		# while (...) {...}
			    $dstat !~ /^for\s*$Constant$/ &&				# for (...)
			    $dstat !~ /^for\s*$Constant\s+(?:$Ident|-?$Constant)$/ &&	# for (...) bar()
			    $dstat !~ /^do\s*{/ &&					# do {...
			    $dstat !~ /^\(\{/)						# ({...
			{
				if ($dstat =~ /^\s*if\b/) {
					ERROR("MULTISTATEMENT_MACRO_USE_DO_WHILE",
					      "Macros starting with if should be enclosed by a do - while loop to avoid possible if/else logic defects\n" . "$herectx");
				} elsif ($dstat =~ /;/) {
					ERROR("MULTISTATEMENT_MACRO_USE_DO_WHILE",
					      "Macros with multiple statements should be enclosed in a do - while loop\n" . "$herectx");
				} else {
					ERROR("COMPLEX_MACRO",
					      "Macros with complex values should be enclosed in parentheses\n" . "$herectx");
				}

			}

			# Make $define_stmt single line, comment-free, etc
			my @stmt_array = split('\n', $define_stmt);
			my $first = 1;
			$define_stmt = "";
			foreach my $l (@stmt_array) {
				$l =~ s/\\$//;
				if ($first) {
					$define_stmt = $l;
					$first = 0;
				} elsif ($l =~ /^[\+ ]/) {
					$define_stmt .= substr($l, 1);
				}
			}
			$define_stmt =~ s/$;//g;
			$define_stmt =~ s/\s+/ /g;
			$define_stmt = trim($define_stmt);

# check if any macro arguments are reused (ignore '...' and 'type')
			foreach my $arg (@def_args) {
			        next if ($arg =~ /\.\.\./);
			        next if ($arg =~ /^type$/i);
				my $tmp_stmt = $define_stmt;
				$tmp_stmt =~ s/\b(__must_be_array|offsetof|sizeof|sizeof_field|__stringify|typeof|__typeof__|__builtin\w+|typecheck\s*\(\s*$Type\s*,|\#+)\s*\(*\s*$arg\s*\)*\b//g;
				$tmp_stmt =~ s/\#+\s*$arg\b//g;
				$tmp_stmt =~ s/\b$arg\s*\#\#//g;
# check if any macro arguments may have other precedence issues
				if ($tmp_stmt =~ m/(\()?\s*($Operators)?\s*\b$arg\b\s*($Operators)?[\s\*]*(\))?/m &&
				    ((defined($2) && $2 ne ',') ||
				     (defined($3) && $3 ne ',')) &&
				    !(defined($2) && ($2 eq '->' || $2 eq '.')) &&
				    !(defined($1) && !defined($2) && (!defined($3) || $3 eq '*') && defined($4))) {
					ERROR("MACRO_ARG_PRECEDENCE",
					      "Macro argument '$arg' may be better as '($arg)' to avoid precedence issues\n" . "$herectx");
				}
			}

# check for macros with flow control, but without ## concatenation
# ## concatenation is commonly a macro that defines a function so ignore those
			if (!$is_test && $has_flow_statement && !$has_arg_concat) {
				my $cnt = statement_rawlines($ctx);
				my $herectx = get_stat_here($linenr, $cnt, $here);

				ERROR("MACRO_WITH_FLOW_CONTROL",
				      "Macros with flow control statements should be avoided\n" . "$herectx");
			}

# check for line continuations outside of #defines, preprocessor #, and asm

		} else {
			if ($prevline !~ /^..*\\$/ &&
			    $rawline !~ /^\+\s*\*\/\s*\\$/ &&	# multiline comment
			    $line !~ /^\+\s*\#.*\\$/ &&		# preprocessor
			    $line !~ /^\+.*\b(__asm__|asm)\b.*\\$/ &&	# asm
			    $line =~ /^\+.*\\$/) {
				ERROR("LINE_CONTINUATIONS",
				      "Avoid unnecessary line continuations\n" . $herecurr);
			}
		}

# do {} while (0) macro tests:
# single-statement macros do not need to be enclosed in do while (0) loop,
# macro should not end with a semicolon
		if ($line =~ /^.\s*\#\s*define\s+$Ident(\()?/) {
			my $ln = $linenr;
			my $cnt = $realcnt;
			my ($off, $dstat, $dcond, $rest);
			my $ctx = '';
			($dstat, $dcond, $ln, $cnt, $off) =
				ctx_statement_block($linenr, $realcnt, 0);
			$ctx = $dstat;

			$dstat =~ s/\\\n.//g;
			$dstat =~ s/$;/ /g;

			if ($dstat =~ /^\+\s*#\s*define\s+$Ident\s*${balanced_parens}\s*do\s*{(.*)\s*}\s*while\s*\(\s*0\s*\)\s*([;\s]*)\s*$/) {
				my $stmts = $2;
				my $semis = $3;

				$ctx =~ s/\n*$//;
				my $cnt = statement_rawlines($ctx);
				my $herectx = get_stat_here($linenr, $cnt, $here);

				if (($stmts =~ tr/;/;/) == 1 &&
				    $stmts !~ /^\s*(if|while|for|switch)\b/) {
					ERROR("SINGLE_STATEMENT_DO_WHILE_MACRO",
					      "Single statement macros should not use a do {} while (0) loop\n" . "$herectx");
				}
				if (defined $semis && $semis ne "") {
					ERROR("DO_WHILE_MACRO_WITH_TRAILING_SEMICOLON",
					      "do {} while (0) macros should not be semicolon terminated\n" . "$herectx");
				}
			} elsif ($dstat =~ /^\+\s*#\s*define\s+$Ident.*;\s*$/) {
				$ctx =~ s/\n*$//;
				my $cnt = statement_rawlines($ctx);
				my $herectx = get_stat_here($linenr, $cnt, $here);

				ERROR("TRAILING_SEMICOLON",
				      "macros should not use a trailing semicolon\n" . "$herectx");
			}
		}

# check for redundant bracing round if etc
		if ($line =~ /(^.*)\bif\b/ && $1 !~ /else\s*$/) {
			my ($level, $endln, @chunks) =
				ctx_statement_full($linenr, $realcnt, 1);
			#print "chunks<$#chunks> linenr<$linenr> endln<$endln> level<$level>\n";
			#print "APW: <<$chunks[1][0]>><<$chunks[1][1]>>\n";
			if ($#chunks > 0 && $level == 0) {
				my @allowed = ();
				my $allow = 0;
				my $seen = 0;
				my $herectx = $here . "\n";
				my $ln = $linenr - 1;
				for my $chunk (@chunks) {
					my ($cond, $block) = @{$chunk};

					# If the condition carries leading newlines, then count those as offsets.
					my ($whitespace) = ($cond =~ /^((?:\s*\n[+-])*\s*)/s);
					my $offset = statement_rawlines($whitespace) - 1;

					$allowed[$allow] = 0;
					#print "COND<$cond> whitespace<$whitespace> offset<$offset>\n";

					$herectx .= "$rawlines[$ln + $offset]\n[...]\n";
					$ln += statement_rawlines($block) - 1;

					substr($block, 0, length($cond), '');

					$seen++ if ($block =~ /^\s*{/);

					#print "cond<$cond> block<$block> allowed<$allowed[$allow]>\n";
					if (statement_lines($cond) > 1) {
						#print "APW: ALLOWED: cond<$cond>\n";
						$allowed[$allow] = 1;
					}
					if ($block =~/\b(?:if|for|while)\b/) {
						#print "APW: ALLOWED: block<$block>\n";
						$allowed[$allow] = 1;
					}
					if (statement_block_size($block) > 1) {
						#print "APW: ALLOWED: lines block<$block>\n";
						$allowed[$allow] = 1;
					}
					$allow++;
				}
				if ($seen) {
					my $sum_allowed = 0;
					foreach (@allowed) {
						$sum_allowed += $_;
					}
					if ($sum_allowed != $allow &&
						 $seen != $allow) {
						ERROR("BRACES",
						      "braces {} should be used on all arms of this statement\n" . $herectx);
					}
				}
			}
		}

# check for single line unbalanced braces
		if ($sline =~ /^.\s*\}\s*else\s*$/ ||
		    $sline =~ /^.\s*else\s*\{\s*$/) {
			ERROR("BRACES", "Unbalanced braces around else statement\n" . $herecurr);
		}

# check for unnecessary blank lines around braces
		if (($line =~ /^.\s*}\s*$/ && $prevrawline =~ /^.\s*$/)) {
			ERROR("BRACES",
			      "Blank lines aren't necessary before a close brace '}'\n" . $hereprev);
		}
		if (($line =~ /^.\s*{\s*$/ && $prevrawline =~ /^.\s*$/)) {
			ERROR("BRACES",
			      "Blank lines aren't necessary before an open brace '{'\n" . $hereprev);
		}
		if (($rawline =~ /^.\s*$/ && $prevline =~ /^..*{\s*$/ && $prevline !~ /^.\s*namespace\s*(?:$Ident\s*)?{\s*$/)) {
			ERROR("BRACES",
			      "Blank lines aren't necessary after an open brace '{'\n" . $hereprev);
		}

# no volatiles please
		my $asm_volatile = qr{\b(__asm__|asm)\s+(__volatile__|volatile)\b};
		if ($line =~ /\bvolatile\b/ && $line !~ /$asm_volatile/ && $line !~ /\bsig_atomic_t\b/) {
			ERROR("VOLATILE",
			      "Use of volatile is usually wrong\n" . $herecurr);
		}

# check for missing a space in a string concatenation
		if ($prevrawline =~ /[^\\]\w"$/ && $rawline =~ /^\+[\t ]+"\w/) {
			ERROR('MISSING_SPACE',
			      "break quoted strings at a space character\n" . $hereprev);
		}

# check for an embedded function name in a string when the function is known
# This does not work very well for -f --file checking as it depends on patch
# context providing the function name or a single line form for in-file
# function declarations
		if ($line =~ /^\+.*$String/ &&
		    defined($context_function) &&
		    get_quoted_string($line, $rawline) =~ /\b$context_function\b/ &&
		    length(get_quoted_string($line, $rawline)) != (length($context_function) + 2)) {
			ERROR("EMBEDDED_FUNCTION_NAME",
			      "Prefer using '\"%s...\", __func__' to using '$context_function', this function's name, in a string\n" . $herecurr);
		}

# check for spaces before a quoted newline
		if ($rawline =~ /^.*\".*\s\\n/) {
			ERROR("QUOTED_WHITESPACE_BEFORE_NEWLINE",
			      "unnecessary whitespace before a quoted newline\n" . $herecurr);
		}

# concatenated string without spaces between elements
		if ($line =~ /$String[A-Z_]/ ||
		    ($line =~ /([A-Za-z0-9_]+)$String/ && $1 !~ /^[Lu]$/)) {
			ERROR("CONCATENATED_STRING",
			      "Concatenated strings should use spaces between elements\n" . $herecurr);
		}

# uncoalesced string fragments
		if ($line =~ /$String\s*[Lu]?"/) {
			ERROR("STRING_FRAGMENTS",
			      "Consecutive strings are generally better as a single string\n" . $herecurr);
		}

# check for non-standard and hex prefixed decimal printf formats
		my $show_L = 1;	#don't show the same defect twice
		my $show_Z = 1;
		while ($line =~ /(?:^|")([X\t]*)(?:"|$)/g) {
			my $string = substr($rawline, $-[1], $+[1] - $-[1]);
			$string =~ s/%%/__/g;
			# check for %L
			if ($show_L && $string =~ /%[\*\d\.\$]*L([diouxX])/) {
				ERROR("PRINTF_L",
				      "\%L$1 is non-standard C, use %ll$1\n" . $herecurr);
				$show_L = 0;
			}
			# check for %Z
			if ($show_Z && $string =~ /%[\*\d\.\$]*Z([diouxX])/) {
				ERROR("PRINTF_Z",
				      "%Z$1 is non-standard C, use %z$1\n" . $herecurr);
				$show_Z = 0;
			}
			# check for 0x<decimal>
			if ($string =~ /0x%[\*\d\.\$\Llzth]*[diou]/) {
				ERROR("PRINTF_0XDECIMAL",
				      "Prefixing 0x with decimal output is defective\n" . $herecurr);
			}
		}

# check for line continuations in quoted strings with odd counts of "
		if ($rawline =~ /\\$/ && $sline =~ tr/"/"/ % 2) {
			ERROR("LINE_CONTINUATIONS",
			      "Avoid line continuations in quoted strings\n" . $herecurr);
		}

# warn about #if 0
		if ($line =~ /^.\s*\#\s*if\s+0\b/) {
			ERROR("IF_0",
			      "Consider removing the code enclosed by this #if 0 and its #endif\n" . $herecurr);
		}

# warn about #if 1
		if ($line =~ /^.\s*\#\s*if\s+1\b/) {
			ERROR("IF_1",
			      "Consider removing the #if 1 and its #endif\n" . $herecurr);
		}

# check for needless "if (<foo>) free(<foo>)" uses
		if ($prevline =~ /\bif\s*\(\s*($Lval)(?:\s*!=\s*NULL)?\s*\)/) {
			my $tested = quotemeta($1);
			my $expr = '\s*\(\s*' . $tested . '\s*\)\s*;';
			if ($line =~ /\bfree$expr/) {
				ERROR('NEEDLESS_IF',
				      "free(NULL) is safe and this check is probably not required\n" . $hereprev);
			}
		}

# check for unnecessary use of %h[xudi] and %hh[xudi] in logging functions
		if (defined $stat &&
		    $line =~ /\b$logFunctions\s*\(/ &&
		    index($stat, '"') >= 0) {
			my $lc = $stat =~ tr@\n@@;
			$lc = $lc + $linenr;
			my $stat_real = get_stat_real($linenr, $lc);
			pos($stat_real) = index($stat_real, '"');
			while ($stat_real =~ /[^\"%]*(%[\#\d\.\*\-]*(h+)[idux])/g) {
				my $pspec = $1;
				my $h = $2;
				my $lineoff = substr($stat_real, 0, $-[1]) =~ tr@\n@@;
				ERROR("UNNECESSARY_MODIFIER",
				      "Integer promotion: Using '$h' in '$pspec' is unnecessary\n" . "$here\n$stat_real\n");
			}
		}

# check for mask then right shift without a parentheses
		if ($line =~ /$LvalOrFunc\s*\&\s*($LvalOrFunc)\s*>>/ &&
		    $4 !~ /^\&/) { # $LvalOrFunc may be &foo, ignore if so
			ERROR("MASK_THEN_SHIFT",
			      "Possible precedence defect with mask then right shift - may need parentheses\n" . $herecurr);
		}

# warn about spacing in #ifdefs
		if ($line =~ /^.\s*\#\s*(ifdef|ifndef|elif)\s\s+/) {
			ERROR("SPACING",
			      "exactly one space required after that #$1\n" . $herecurr);
		}

# check for uncommented definitions
		my $check_comment = 0;
		my $check_comment_line = $linenr;
		my $check_comment_ident;
		if ($is_test) {
			# ignore tests
		} elsif ($realfile =~ /\bbox\.h$/ && $line =~ /^\+\s*(?:$Declare)?\s*box_set_/) {
			# ignore box_set_XXX in box.h
		} elsif ($line =~ /\boperator\s*()/) {
			# operator() is used as a callback so a comment isn't necessary
		} elsif ($line =~ /^\+\s*(?:$Declare)?\s*(?:generic_|disabled_|exhausted_)/) {
			# generic_XXX, disabled_XXX, exhausted_XXX are functions are stubs so comments are not required
		} elsif ($line =~ /^\+\s*($Declare)?\s*(?:($Ident)\s*\(|\(\s*\*\s*($Ident)\s*\)\s*\(|($Ident)\s*;)/) {
			# function, function pointer, variable / struct member
			my $decl = $1;
			my $is_func = defined($2);
			$check_comment_ident = defined($2) ? $2 : defined($3) ? $3 : $4;
			if (!defined($decl) && $prevline =~ /^[\+ ]\s*($Declare)\s*$/) {
				$decl = $1;
				$check_comment_line -= 1;
				# Skip deleted lines
				while ($check_comment_line >= 1 && $lines[$check_comment_line - 1] =~ /^-/) {
					$check_comment_line -= 1;
				}
			}
			# Skip C++ template and typedef
			while ($check_comment_line >= 2 && $lines[$check_comment_line - 2] =~ /(?:^-|(?:,|>|^.\s*typedef)\s*$)/) {
				$check_comment_line -= 1;
			}
			my $func_body_size;
			if ($is_func && defined($stat)) {
				my $cnt = statement_rawlines($stat);
				for (my $n = 0; $n < $cnt; $n++) {
					my $rl = raw_line($linenr, $n);
					if (!defined($func_body_size)) {
						$func_body_size = -1 if $rl =~ /\{/;
						next;
					}
					if ($rl !~ /^.\s*(?:\(\s*void\s*\)\s*$Ident|unreachable\s*\(\s*\))\s*;\s*$/) {
						$func_body_size += 1;
					}
				}
			}
			if (!defined($decl)) {
				# not a declaration
			} elsif (!$is_func && $decl =~ /\bstruct\s+trigger\b/) {
				# ignore trigger declarations because we usually add a comment to a trigger function instead
			} elsif (!$is_func && defined($context_function)) {
				# ignore local variables
			} elsif ($realfile !~ /\.h$/ && $decl !~ /\bstatic\b/ && !defined($context_struct)) {
				# don't require a comment for a global function or variable defined in a source file,
				# because it should have a comment in a header file
			} elsif ($is_func && $check_comment_ident =~ /_(?:init|free|new|delete|create|destroy)$/) {
				# don't require a comment for constructor/destructor
			} elsif ($is_func && $decl =~ /\bstatic\b/ && $check_comment_ident =~ /_(?:f|fn|cb)$/) {
				# don't require a comment for a static callback function
			} elsif (defined($func_body_size) && $func_body_size <= 3) {
				# ignore short functions
			} elsif (!$check_comment_ignore{$check_comment_ident}) {
				$check_comment = 1;
				# Don't require a comment for a function definition if a forward declaration has one.
				if ($is_func) {
					$check_comment_ignore{$check_comment_ident} = 1;
				}
			}
		} elsif ($line =~ /^\+\s*struct\s+(?:$Modifier\s+)*($Ident)\s*(?:{\s*)?$/) {
			# Skip C++ template
			while ($check_comment_line >= 2 && $lines[$check_comment_line - 2] =~ /(?:^-|(?:,|>|^.\s*typedef)\s*$)/) {
				$check_comment_line -= 1;
			}
			# struct
			$check_comment_ident = $1;
			$check_comment = $check_comment_ident !~ /^$Attribute$/ && !defined($context_function);
		}
		if ($check_comment && !ctx_has_comment($first_line, $check_comment_line)) {
			ERROR("UNCOMMENTED_DEFINITION",
			      "'$check_comment_ident' definition without comment\n" . $herecurr);
		}

# check that the storage class is not after a type
		if ($line =~ /\b($Type)\s+($Storage)\b/) {
			ERROR("STORAGE_CLASS",
			      "storage class '$2' should be located before type '$1'\n" . $herecurr);
		}
# Check that the storage class is at the beginning of a declaration
		if ($line =~ /\b$Storage\b/ &&
		    $line !~ /^.\s*$Storage/ &&
		    $line =~ /^.\s*(.+?)\$Storage\s/ &&
		    $1 !~ /[\,\)]\s*$/) {
			ERROR("STORAGE_CLASS",
			      "storage class should be at the beginning of the declaration\n" . $herecurr);
		}

# check the location of the inline attribute, that it is between
# storage class and type.
		if ($line =~ /\b$Type\s+$Inline\b/ ||
		    $line =~ /\b$Inline\s+$Storage\b/) {
			ERROR("INLINE_LOCATION",
			      "inline keyword should sit between storage class and type\n" . $herecurr);
		}

# Check for __inline__ and __inline, prefer inline
		if ($line =~ /\b(__inline__|__inline)\b/) {
			ERROR("INLINE",
			      "plain inline is preferred over $1\n" . $herecurr);
		}

# Check for compiler attributes
# Ignore src/trivia/util.h, because we define attribute specifiers there
		if ($realfile ne 'src/trivia/util.h' &&
		    $rawline =~ /\b__attribute__\s*\(\s*($balanced_parens)\s*\)/) {
			my $attr = $1;
			$attr =~ s/\s*\(\s*(.*)\)\s*/$1/;

			my %attr_list = (
				"aligned"			=> "alignas",
				"format"			=> "CFORMAT",
				"deprecated"			=> "DEPREACTED",
				"fallthrough"			=> "FALLTHROUGH",
				"nodiscard"			=> "NODISCARD",
				"noinline"			=> "NOINLINE",
				"noreturn"			=> "NORETURN",
				"packed"			=> "PACKED",
				"unused"			=> "MAYBE_UNUSED"
			);

			while ($attr =~ /\s*(\w+)\s*(${balanced_parens})?/g) {
				my $orig_attr = $1;
				my $params = '';
				$params = $2 if defined($2);
				my $curr_attr = $orig_attr;
				$curr_attr =~ s/^[\s_]+|[\s_]+$//g;
				if (exists($attr_list{$curr_attr})) {
					my $new = $attr_list{$curr_attr};
					if ($curr_attr eq "format" && $params) {
						$params =~ /^\s*\(\s*(\w+)\s*,\s*(.*)/;
						$new = "__$1\($2";
					} else {
						$new = "$new$params";
					}
					ERROR("PREFER_DEFINED_ATTRIBUTE_MACRO",
					      "Prefer $new over __attribute__(($orig_attr$params))\n" . $herecurr);
				}
			}
		}

# Check for __attribute__ weak, or __weak declarations (may have link issues)
		if ($line =~ /(?:$Declare|$DeclareMisordered)\s*$Ident\s*$balanced_parens\s*(?:$Attribute)?\s*;/ &&
		    ($line =~ /\b__attribute__\s*\(\s*\(.*\bweak\b/ ||
		     $line =~ /\b__weak\b/)) {
			ERROR("WEAK_DECLARATION",
			      "Using weak declarations can have unintended link defects\n" . $herecurr);
		}

# check for cast of C90 native int or longer types constants
		if ($line =~ /(\(\s*$C90_int_types\s*\)\s*)($Constant)\b/) {
			my $cast = $1;
			my $const = $2;
			my $suffix = "";
			$suffix .= 'U' if ($cast =~ /\bunsigned\b/);
			if ($cast =~ /\blong\s+long\b/) {
			    $suffix .= 'LL';
			} elsif ($cast =~ /\blong\b/) {
			    $suffix .= 'L';
			}
			ERROR("TYPECAST_INT_CONSTANT",
			      "Unnecessary typecast of c90 int constant - '$cast$const' could be '$const$suffix'\n" . $herecurr);
		}

# check for sizeof(&)
		if ($line =~ /\bsizeof\s*\(\s*\&/) {
			ERROR("SIZEOF_ADDRESS",
			      "sizeof(& should be avoided\n" . $herecurr);
		}

# check for sizeof without parenthesis
		if ($line =~ /\bsizeof\s+((?:\*\s*|)$Lval|$Type(?:\s+$Lval|))/) {
			ERROR("SIZEOF_PARENTHESIS",
			      "sizeof $1 should be sizeof($1)\n" . $herecurr);
		}

# Check for misused memsets
		if (defined $stat &&
		    $stat =~ /^\+(?:.*?)\bmemset\s*\(\s*$FuncArg\s*,\s*$FuncArg\s*\,\s*$FuncArg\s*\)/) {

			my $ms_addr = $2;
			my $ms_val = $7;
			my $ms_size = $12;

			if ($ms_size =~ /^(0x|)0$/i) {
				ERROR("MEMSET",
				      "memset to 0's uses 0 as the 2nd argument, not the 3rd\n" . "$here\n$stat\n");
			} elsif ($ms_size =~ /^(0x|)1$/i) {
				ERROR("MEMSET",
				      "single byte memset is suspicious. Swapped 2nd/3rd argument?\n" . "$here\n$stat\n");
			}
		}

# check for naked sscanf
		if (defined $stat &&
		    $line =~ /\bsscanf\b/ &&
		    ($stat !~ /$Ident\s*=\s*sscanf\s*$balanced_parens/ &&
		     $stat !~ /\bsscanf\s*$balanced_parens\s*(?:$Compare)/ &&
		     $stat !~ /(?:$Compare)\s*\bsscanf\s*$balanced_parens/)) {
			my $lc = $stat =~ tr@\n@@;
			$lc = $lc + $linenr;
			my $stat_real = get_stat_real($linenr, $lc);
			ERROR("NAKED_SSCANF",
			      "unchecked sscanf return value\n" . "$here\n$stat_real\n");
		}

# check for new externs in .h files.
		if ($realfile =~ /\.h$/ &&
		    $line =~ /^\+\s*(extern\s+)$Type\s*$Ident\s*\(/s) {
			ERROR("AVOID_EXTERNS",
			      "extern prototypes should be avoided in .h files\n" . $herecurr);
		}

# check for function identifier and arguments written on different lines
		if (defined $stat &&
		    $stat =~ /^.\s*(?:extern\s+)?$Type\s+$Ident(\s*)\(/s)
		{
			my $paren_space = $1;
			if ($paren_space =~ /\n/) {
				ERROR("FUNCTION_ARGUMENTS",
				      "arguments for function declarations should follow identifier\n" . $herecurr);
			}
		}

# check for function declarations that have arguments without identifier names
# suppress the check for expressions in function context to avoid FP error for class object definition
		if (defined $stat && !defined $context_function &&
		    $stat =~ /^.\s*(?:extern\s+)?$Type\s*(?:$Ident|\(\s*\*\s*$Ident\s*\))\s*\(\s*([^{]+)\s*\)\s*;/s &&
		    $1 ne "void") {
			my $args = trim($1);
			while ($args =~ m/\s*($Type\s*(?:$Ident|\(\s*\*\s*$Ident?\s*\)\s*$balanced_parens)?)/g) {
				my $arg = trim($1);
				if ($arg =~ /^$Type$/ && $arg !~ /enum\s+$Ident$/) {
					ERROR("FUNCTION_ARGUMENTS",
					      "function definition argument '$arg' should also have an identifier name\n" . $herecurr);
				}
			}
		}

# check for function definitions
		if (defined $stat &&
		    $stat =~ /^.\s*$Declare\s*($Ident)\s*$balanced_parens\s*{/s) {
			$context_function = $1;

# check for multiline function definition with misplaced open brace
			my $ok = 0;
			my $cnt = statement_rawlines($stat);
			my $herectx = $here . "\n";
			for (my $n = 0; $n < $cnt; $n++) {
				my $rl = raw_line($linenr, $n);
				$herectx .=  $rl . "\n";
				$ok = 1 if ($rl =~ /^[ \+]\s*\{/);
				# allow opening and closing braces on the same line
				$ok = 1 if ($rl =~ /\{.*\}/);
				last if $rl =~ /^[ \+].*\{/;
			}
			if (!$ok) {
				ERROR("OPEN_BRACE",
				      "open brace '{' following function definitions go on the next line\n" . $herectx);
			}
		}

# check for pointless casting of alloc functions
		if ($realfile =~ /\.c$/ &&  $line =~ /\*\s*\)\s*$allocFunctions\b/) {
			ERROR("UNNECESSARY_CASTS",
			      "unnecessary cast may hide bugs, see http://c-faq.com/malloc/mallocnocast.html\n" . $herecurr);
		}

# alloc style
# p = alloc(sizeof(struct foo), ...) should be p = alloc(sizeof(*p), ...)
		if ($line =~ /\b($Lval)\s*\=\s*(?:$balanced_parens)?\s*((?:x)malloc)\s*\(\s*(sizeof\s*\(\s*struct\s+$Lval\s*\))/) {
			ERROR("ALLOC_SIZEOF_STRUCT",
			      "Prefer $3(sizeof(*$1)...) over $3($4...)\n" . $herecurr);
		}

# check for realloc arg reuse
		if ($line =~ /\b($Lval)\s*\=\s*(?:$balanced_parens)?\s*realloc\s*\(\s*($Lval)\s*,/ &&
		    $1 eq $3) {
			ERROR("REALLOC_ARG_REUSE",
			      "Reusing the realloc arg is almost always a bug\n" . $herecurr);
		}

# check for alloc argument mismatch
		if ($line =~ /\b((?:x)?calloc)\s*\(\s*sizeof\b/) {
			ERROR("ALLOC_ARRAY_ARGS",
			      "$1 uses number as first arg, sizeof is generally wrong\n" . $herecurr);
		}

# prefer xmalloc over malloc
		if ($line =~ /\b((?:m|c|re)alloc|strdup|strndup)\s*\(/) {
			my $func = $1;
			ERROR("XMALLOC",
			      "Please use x$func instead of $func\n" . $herecurr);
		}

# warn about unsafe functions
		if (!$is_test && $line =~ /\b($Ident)\s*\(/) {
			my $func = $1;
			my %func_list = (
				"getenv"		=> "getenv_safe",
				"sprintf"		=> "snprintf",
				"vsprintf"		=> "vsnprintf",
				"strcpy"		=> "strlcpy",
				"strncpy"		=> "strlcpy",
				"strcat"		=> "strlcat",
				"strncat"		=> "strlcat",
				"strerror"		=> "tt_strerror",
			);
			if (exists($func_list{$func})) {
				my $new = $func_list{$func};
				ERROR("UNSAFE_FUNCTION",
				      "$func is unsafe. Please use $new instead\n" . $herecurr);
			}
		}

# check for multiple semicolons
		if ($line =~ /;\s*;\s*$/) {
			ERROR("ONE_SEMICOLON",
			      "Statements terminations use 1 semicolon\n" . $herecurr);
		}

		my @fallthroughs = (
			'fallthrough',
			'@fallthrough@',
			'lint -fallthrough[ \t]*',
			'intentional(?:ly)?[ \t]*fall(?:(?:s | |-)[Tt]|t)hr(?:ough|u|ew)',
			'(?:else,?\s*)?FALL(?:S | |-)?THR(?:OUGH|U|EW)[ \t.!]*(?:-[^\n\r]*)?',
			'Fall(?:(?:s | |-)[Tt]|t)hr(?:ough|u|ew)[ \t.!]*(?:-[^\n\r]*)?',
			'fall(?:s | |-)?thr(?:ough|u|ew)[ \t.!]*(?:-[^\n\r]*)?',
		    );
		if ($raw_comment ne '') {
			foreach my $ft (@fallthroughs) {
				if ($raw_comment =~ /$ft/) {
					ERROR("PREFER_FALLTHROUGH",
					      "Prefer 'FALLTHROUGH;' over fallthrough comment\n" . $herecurr);
					last;
				}
			}
		}

# check for switch/default statements without a break;
		if (defined $stat &&
		    $stat =~ /^\+[$;\s]*(?:case[$;\s]+\w+[$;\s]*:[$;\s]*|)*[$;\s]*\bdefault[$;\s]*:[$;\s]*;/g) {
			my $cnt = statement_rawlines($stat);
			my $herectx = get_stat_here($linenr, $cnt, $here);

			ERROR("DEFAULT_NO_BREAK",
			      "switch default: should use break\n" . $herectx);
		}

# check for gcc specific __FUNCTION__
		if ($line =~ /\b__FUNCTION__\b/) {
			ERROR("USE_FUNC",
			      "__func__ should be used instead of gcc specific __FUNCTION__\n"  . $herecurr);
		}

# check for uses of __DATE__, __TIME__, __TIMESTAMP__
		while ($line =~ /\b(__(?:DATE|TIME|TIMESTAMP)__)\b/g) {
			ERROR("DATE_TIME",
			      "Use of the '$1' macro makes the build non-deterministic\n" . $herecurr);
		}

# check for comparisons against true and false
		if ($line =~ /\+\s*(.*?)\b(true|false|$Lval)\s*(==|\!=)\s*(true|false|$Lval)\b(.*)$/i) {
			my $lead = $1;
			my $arg = $2;
			my $test = $3;
			my $otype = $4;
			my $trail = $5;
			my $op = "!";

			($arg, $otype) = ($otype, $arg) if ($arg =~ /^(?:true|false)$/i);

			my $type = lc($otype);
			if ($type =~ /^(?:true|false)$/) {
				if (("$test" eq "==" && "$type" eq "true") ||
				    ("$test" eq "!=" && "$type" eq "false")) {
					$op = "";
				}

				ERROR("BOOL_COMPARISON",
				      "Using comparison to $otype is error prone\n" . $herecurr);

## maybe suggesting a correct construct would better
##				    "Using comparison to $otype is error prone.  Perhaps use '${lead}${op}${arg}${trail}'\n" . $herecurr);

			}
		}

# likely/unlikely comparisons similar to "(likely(foo) > 0)"
		if ($line =~ /\b((?:un)?likely)\s*\(\s*$FuncArg\s*\)\s*$Compare/) {
			ERROR("LIKELY_MISUSE",
			      "Using $1 should generally have parentheses around the comparison\n" . $herecurr);
		}

# Mode permission misuses where it seems decimal should be octal
# This uses a shortcut match to avoid unnecessary uses of a slow foreach loop
		if (defined $stat &&
		    $line =~ /$mode_perms_search/) {
			foreach my $entry (@mode_permission_funcs) {
				my $func = $entry->[0];
				my $arg_pos = $entry->[1];

				my $lc = $stat =~ tr@\n@@;
				$lc = $lc + $linenr;
				my $stat_real = get_stat_real($linenr, $lc);

				my $skip_args = "";
				if ($arg_pos > 1) {
					$arg_pos--;
					$skip_args = "(?:\\s*$FuncArg\\s*,\\s*){$arg_pos,$arg_pos}";
				}
				my $test = "\\b$func\\s*\\(${skip_args}($FuncArg(?:\\|\\s*$FuncArg)*)\\s*[,\\)]";
				if ($stat =~ /$test/) {
					my $val = $1;
					$val = $6 if ($skip_args ne "");
					if ((($val =~ /^$Int$/ && $val !~ /^$Octal$/) ||
					     ($val =~ /^$Octal$/ && length($val) ne 4))) {
						ERROR("NON_OCTAL_PERMISSIONS",
						      "Use 4 digit octal (0777) not decimal permissions\n" . "$here\n" . $stat_real);
					}
				}
			}
		}
	}

	# If we have no input at all, then there is nothing to report on
	# so just keep quiet.
	if ($#rawlines == -1) {
		return 1;
	}

	# In mailback mode only produce a report in the negative, for
	# things that appear to be patches.
	if ($mailback && ($clean == 1 || !$is_patch)) {
		return 1;
	}

	# This is not a patch, and we are in 'no-patch' mode so
	# just keep quiet.
	if (!$chk_patch && !$is_patch) {
		return 1;
	}

	if (!$is_patch && $filename !~ /cover-letter\.patch$/) {
		ERROR("NOT_UNIFIED_DIFF",
		      "Does not appear to be a unified-diff format patch\n");
	}
	if ($is_patch && $has_commit_log && $chk_signoff) {
		if ($signoff == 0) {
			ERROR("MISSING_SIGN_OFF",
			      "Missing Signed-off-by: line(s)\n");
		} elsif ($authorsignoff != 1) {
			# authorsignoff values:
			# 0 -> missing sign off
			# 1 -> sign off identical
			# 2 -> names and addresses match, comments mismatch
			# 3 -> addresses match, names different
			# 4 -> names match, addresses different
			# 5 -> names match, addresses excluding subaddress details (refer RFC 5233) match

			my $sob_msg = "'From: $author' != 'Signed-off-by: $author_sob'";

			if ($authorsignoff == 0) {
				ERROR("NO_AUTHOR_SIGN_OFF",
				      "Missing Signed-off-by: line by nominal patch author '$author'\n");
			} elsif ($authorsignoff == 2) {
				ERROR("FROM_SIGN_OFF_MISMATCH",
				      "From:/Signed-off-by: email comments mismatch: $sob_msg\n");
			} elsif ($authorsignoff == 3) {
				ERROR("FROM_SIGN_OFF_MISMATCH",
				      "From:/Signed-off-by: email name mismatch: $sob_msg\n");
			} elsif ($authorsignoff == 4) {
				ERROR("FROM_SIGN_OFF_MISMATCH",
				      "From:/Signed-off-by: email address mismatch: $sob_msg\n");
			} elsif ($authorsignoff == 5) {
				ERROR("FROM_SIGN_OFF_MISMATCH",
				      "From:/Signed-off-by: email subaddress mismatch: $sob_msg\n");
			}
		}
	}

	if ($is_patch && $has_commit_log) {
		if ($commit_log_no_wrap) {
			ERROR("UNTERMINATED_TAG",
			      "Unterminated NO_WRAP section in commit description\n")
		}
		if (!$has_doc && !exists($commit_log_tags{'NO_DOC'})) {
			ERROR("NO_DOC",
			      "Please add doc or NO_DOC=<reason> tag\n");
		}
		if ($has_doc && exists($commit_log_tags{'NO_DOC'})) {
			ERROR("REDUNDANT_TAG",
			      "Redundant NO_DOC tag\n");
		}
		if (!$has_changelog && !exists($commit_log_tags{'NO_CHANGELOG'})) {
			ERROR("NO_CHANGELOG",
			      "Please add changelog or NO_CHANGELOG=<reason> tag\n");
		}
		if (!$has_test && !exists($commit_log_tags{'NO_TEST'})) {
			ERROR("NO_TEST",
			      "Please add test or NO_TEST=<reason> tag\n");
		}
	}

	print report_dump();
	if ($summary && !($clean == 1 && $quiet == 1)) {
		print "$filename " if ($summary_file);
		print "total: $cnt_error errors, $cnt_lines lines checked\n";
	}

	if ($clean == 1 && $quiet == 0) {
		print "\n";
		print "$vname has no obvious style problems and is ready for submission.\n";
	}
	if ($clean == 0) {
		print "$vname has style problems, please review.\n";
	}
	return $clean;
}
