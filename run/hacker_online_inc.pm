package hacker_online_inc;
use strict;
use warnings;
use Exporter;
use Win32::OLE;
use Time::HiRes qw(time);
use POSIX qw(strftime);

our @ISA= qw( Exporter );

my $iim;
my $log_file;
my $log_dir;
my $user_name;
my $script_name;
my $password;
my $user_agent;
my $dbg_lvl = 1;

# these CAN be exported.
our @EXPORT_OK = qw( InitMacroSystem LogLine Login rand_time imacro_err NewEnough rtrim ltrim IM_Sleep DbgLvl );

# these are exported by default.
our @EXPORT = qw( InitMacroSystem LogLine Login rand_time imacro_err NewEnough rtrim ltrim IM_Sleep DbgLvl );


#####################
# exported
#####################
sub InitMacroSystem {  ($user_name, $password, $script_name, $user_agent, $log_dir, $log_file) = @_;
	$iim = Win32::OLE->new('imacros') or die "iMacros Browser could not be started by Win32:OLE\n";
	$iim->iimInit();
	LogLine ("New run started for  script: $script_name for user: $user_name", 1);
	LogLine ("====================================================================", 1);
	return $iim;
}

sub DbgLvl {
	$dbg_lvl = $_[0];
}

sub LogLine {
	my $lvl = -1;
	if (defined $_[1]) { $lvl = $_[1]; }
	if ( (!defined $log_dir || !defined $log_file || length $log_file == 0) && 
	     ($lvl == -1 || $lvl > $dbg_lvl) ) {
		return;
	}
	# all log lines get a standard timestamp format.   "YYYYmmdd HH24:MM:SS.sss : "
	my $t = time;
	my $dt = strftime "%Y%m%d %H:%M:%S", localtime $t;
	$dt .= sprintf ".%03d", ($t-int($t))*1000;

	# write to stdout (optional)
	if ($lvl > -1 && $lvl <= $dbg_lvl) { print "$dt : $_[0]\n"; }

	# write to log file.
	if ( (defined $log_dir && defined $log_file && length $log_file > 0) ) {
		open LOG, ">>", $log_dir.'/'.$log_file;
		print LOG "$dt : $_[0]\n";
		close(LOG);
	}
}
sub Login {
	my $s = "VERSION BUILD=11.5.498.2403\n";
	$s   .= "TAB T=1\n";
	$s   .= "SET !USERAGENT \"$user_agent\"\n";
	$s   .= "URL GOTO=http://www.hacker-online-game.com/index.php?action=logout\n";
	$s   .= "TAG POS=1 TYPE=INPUT:TEXT ATTR=NAME:user CONTENT=$user_name\n";
	$s   .= "SET !ENCRYPTION NO\n";
	$s   .= "TAG POS=1 TYPE=INPUT:PASSWORD ATTR=NAME:pwd CONTENT=$password\n";
	$s   .= "TAG POS=1 TYPE=INPUT:SUBMIT ATTR=NAME:submit\n";
	$s   .= "WAIT SECONDS=" . rand_time(1,1) . "\n";
	my $err = $iim->iimPlayCode($s);
	imacro_err ($err, "login");
	return $err;
}

sub rand_time {  my ($tm, $rnd) = @_;
	$tm += rand()*$rnd;
	my $s = sprintf("%0.2f", $tm);
	return $s;
}

sub imacro_err {  my ($err, $data_fname) = @_;
	if ($err < 0) {
		my $err_txt = $iim->iimGetErrorText();
		LogLine ("FAILURE: run $data_fname  <$err_txt>");
		exit 1;
	} elsif ($dbg_lvl > 1) {
		LogLine ("Success: run $data_fname");
	}
}

sub NewEnough {
	my $base = strdate_to_sortable_num($_[1]);
	my $this = strdate_to_sortable_num($_[0]);
	return $this*1 > $base*1;
}

sub rtrim {
	while (substr($_[0],length($_[0])-1,1) eq ' ') {
		$_[0] = substr($_[0],0, length($_[0])-1);
	}
	return $_[0];
}
sub ltrim {
	while (substr($_[0],0,1) eq ' ') {
		$_[0] = substr($_[0],1);
	}
	return $_[0];
}
sub IM_Sleep {
	if (defined $_[2]) { print ("$_[2]\n"); }
	$iim->iimPlayCode("WAIT SECONDS=".rand_time($_[0],$_[1])."\n", 3600);
}
####################################
# Local to the module (not exported)
####################################
sub timestamp {
	my $t = time;
	my $date = strftime "%Y%m%d %H:%M:%S", localtime $t;
	$date .= sprintf ".%03d", ($t-int($t))*1000; # without rounding
	return $date;
}

sub Month {
	my $m = $_[0];
	if ($m eq "Jan") { return 1; }
	if ($m eq "Feb") { return 2; }
	if ($m eq "Mar") { return 3; }
	if ($m eq "Apr") { return 4; }
	if ($m eq "May") { return 5; }
	if ($m eq "Jun") { return 6; }
	if ($m eq "Jul") { return 7; }
	if ($m eq "Aug") { return 8; }
	if ($m eq "Sep") { return 9; }
	if ($m eq "Oct") { return 10; }
	if ($m eq "Nov") { return 11; }
	if ($m eq "Dec") { return 12; }
}

sub strdate_to_sortable_num {
	#  29-Nov-2016 07:38:57   (date format)
	my $t = $_[0];
	my @ar = split(" ", $t);
	my @d = split("-", $ar[0]);
	my @m = split(":", $ar[1]);
	my $s = sprintf("%04d%02d%02d%02d%02d%02d", $d[2], Month($d[1]), $d[0], $m[0], $m[1], $m[2]);
	return $s;
}
