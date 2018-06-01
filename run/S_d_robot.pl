#!/usr/bin/perl -w

my $ver = "v1.15";

################################################################################
# v1.13 12/20/17, boobear
#	Full robot for doing S/D missions
#
#
# usage:    ./S_d_robot.pl config_file
#
#  layout of config_file:
#		key`value
#		keys:
#			IPs    (ip file).	This is the faction IP file.
#			breakers			This is the breaker ID file for the user's server #1
#			Many more (see sd_polt.cfg as it has all keys in it).
#
#   ToDO:
#          Handle a 'steal' mission files server which changes the logs.  In other words
#            come up with ways to have fewer IDS warnings.
#
#          Way to optimize overall finish time.  Sort by most $hdp first. That way, the
#            longer decrypt stuff will be started first. It will take the most time, so
#            starting it first will get ALL work done quicker. Do the sort when doing
#            the IP cracks, and then sort each time we have a block (multiple) items to
#            work on (starting decrypts, etc).  Overall, it should complete 10-20 minutes
#            faster (I hope).  Also, there should be fewer times where we have data which
#            spills over into the next hour.  ALSO, we should be able to take a IDS check
#            in the middle of LONG work!!! like starting cracks.
#
#          On the crack box, only uncheck items that can be completed.  if there is a connect/bounce
#            then do not worry.  NOTE, we may need to adjust this thought to handle file share
#            virus installs where we bounce to ourseleves.
#
#          ***** Add protection to IDS check.  Will change IP, and restart new change IP job. *****
#
#          add -1+ command line switch.  This will run a -1 but stay running, until all data is being
#            decrypted.  It will not try to complete anything, just pull cracks, and start decr on them
#            until all cracks are done.
#
#          if decr and crack are same gateway, then use 'last' for sort on decr vs using completed.
#
#   done:  
#          (new for v1.14)
#          check for running warez, and restart it.  (fixed for stolen and non-gold in v1.15)
#          (new for v1.15)
#          if IDS validated is top line (when there is a log change upon IDS
#             check), then do NOT warn. Simply update the IDS cache.
#          the password for IDS check is configurable, and in the scripts config
#             file.
################################################################################

use hacker_online_inc;
use Digest::MD5;

if (defined $ARGV[0] && $ARGV[0] eq '-?') {
	print("usage: ./S_d_robot.pl config_file [-1] [-teamcomp | -teamdecr] [-nitemode] [-sil]\n");
	exit(0);
}

$| = 1;		# no buffering of stdout.

#{  variables used to change timings of each part of the script.
my $extra_delay_run_new_sd_decr = 0;
my $extra_delay_get_new_missions = 0;
my $extra_delay_reload_missions_tables = 0;
my $extra_delay_run_new_sd_cracks = 0;
my $extra_delay_finish_sd_cracks = 0;
#}

#{ vars filled in by load_config() and used throughout the bot script.
my @breakers;
my @IPs;
my $ldir;
my $user; my $pass; my $userid; my $ids_pass;
my $breaker_file;
my @ids_gateways=();
my %gateway_ips=();
my %ids_gateway_logs=();
my %enemy_decr=();
my $ids_group_count=0;
my $faction;
my $crack_svr; my $decr_svr; 
my $sd_ip_dat;
my $add_to_db = 1;		# we always add to the db.  It allow better robot tracking of what state a server is in.
my $agent = 'Mozilla/5.0<SP>(Windows<SP>NT<SP>10.0;<SP>Win64;<SP>x64)<SP>AppleWebKit/537.36<SP>(KHTML,<SP>like<SP>Gecko)<SP>Chrome/51.0.2704.79<SP>Safari/537.36<SP>Edge/14.14393'; # win10 edge browser.
my $bounceMax = 5;
my $gold = 'no';
my $one = 0; my $skip_init_load = 0;
my $hours_run=0;
my $first_load=1;
my $complete_ip_change=0;
my $complete_non_breakers=0;
#}

#{ Runtime vars
my $last_hour = -1;
my $ids_delay_min = 15;
my $iim;
my $err;
my $dbg_cnt = 0;
my $min_decr_to_show=1;
my $next_ids_check=0;
my $uncrack_cnt = 0; my $cracked_cnt = 0; my $this_run_count = 0;
my $hour_crk_start=0; my $hour_crk_done=0; my $hour_dec_start=0; my $hour_dec_done=0; $hour_dec_dead=0;
# variables for special 2 user team mode (one decrypts one completes missions. The decr user should be icarus faction member (for faster decrypts)
my $decr_mode=0; my $comp_mode=0;
my $comp_input_flag_file = "comp_input_trigger.txt";
my $comp_input_file      = "comp_input_file.txt";
my $decr_input_flag_file = "decr_input_trigger.txt";
my $decr_input_file      = "decr_input_file.txt";
#
# used for running at nite. Will bail and run when other IP seen on decr server, or MOB seen on decr server. We must have a ready IP change on the decr server!
#  0  not using nite mode
#  1  using nite mode, but clear to run (nothing bad seen)
#  2  We saw something bad.  Switch IP as soon as all cracks are being decrypted OR right before MOV fires.  We re-start a new 24 hour IP change instantly.
#  3  We have switched IP. We NO longer load any new missions (at minute :40).  Also, we watch and when decr is done, we exit.
my $nite_mode = 0;
#
my @sd_uncracked = ();   my @dl_uncracked = ();   my @rc_uncracked = ();
my @sd_cracking = ();    my @dl_cracking = ();    my @rc_cracking = ();
my @sd_cracked = ();     my @dl_cracked = ();     my @rc_cracked = ();
my @sd_decrypting = ();  my @dl_decrypting = ();  my @rc_decrypting = ();
my @sd_tocomplete = ();
#}

main();

sub main {
	#### Prepare the system.  Load config, init iMacros, then log in to hacker-online game.
	LoadConfig($ARGV[0]);

	my $i = 1;
	while (defined ($ARGV[$i])) {
		if    ($ARGV[$i] eq '-1')        { $one = 1; }
		elsif ($ARGV[$i] eq '-sil')      { $skip_init_load = 1; }
		elsif ($ARGV[$i] eq "-teamcomp") { $comp_mode = 1; }
		elsif ($ARGV[$i] eq "-teamdecr") { $decr_mode = 1; }
		elsif ($ARGV[$i] eq "-nitemode") { $nite_mode = 1; }
		else {
			print "Unknown running option $ARGV[1]\n";
			die;
		}
		++$i;
	}

	$iim = InitMacroSystem($user, $pass, "[OFC]_Search_and_Destroy_robot", $agent, $ldir, "sd_robot_".$user.".log");
	my $ret = Login();
	if ($ret < 0) {
		print "return from Login is $ret\n"; exit 1;
	}
	get_breaker_ids($breaker_file);
	get_faction_ips();
	# DbgLvl(2);

	# initialize the IDS monitoring data, AND loades IP's of all gateways (for the switch_to_gateway() function.
	if ($one != 1) { build_initial_IDS_data(); }

	if ($comp_mode > 0) { switch_to_gateway($crack_svr); }

	# check for new work at ??:xx minutes after the hour.  NOTE, this time DOES slowly drift a bit
	# so it has to be monitored about once a month, to see if we need to wait until next minute.
	my $new_work_MIN = 55;
	
	while (1) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		if ( ($last_hour == -1 && $skip_init_load == 0) || ($last_hour != -1 && $last_hour != $hour && $min >= $new_work_MIN) ) {
			if ($nite_mode < 2) {
				if ($last_hour != -1) {
					#IM_Sleep(10,3);
					# always IDS check before the LONG running cracking of new missions.
					perform_IDS_check(1);
					switch_to_gateway($crack_svr);
					validate_crack_sw();
				}
				drop_stats();
				# at xx:$new_work_MIN we get every new faction mission.  We only do this at this time.
				if ($last_hour == -1 && $min < $new_work_MIN) { $last_hour = 666; } # if we start at 10:15, we want to be sure to get THIS hour at 10:40 also.
				else { $last_hour = $hour; }
				LogLine("======= At minute $new_work_MIN. [$faction] $user == ($ver) ===", 1);
				# reload file. This allows us to edit the file, while script is running, and it will pick it up next hour.
				LoadConfig($ARGV[0]);
				if ($hours_run > 0) {
					get_faction_ips();
				}
				if ($decr_mode == 0) {
					# if decr mode, we do not pull mission IP's, but get them from a file.
					get_new_missions();
					IM_Sleep(4,3);
					$uncrack_cnt = reload_missions_tables();	# this may need to be run at other times.
				}
				$hours_run++;
			}
		}
		if ($decr_mode > 0) { reload_decr_mode_missions(); }
		if ($last_hour == -1) { $last_hour = $hour; }

		if ($one != 1) { perform_IDS_check(0); }	# perform IDS check every X minutes (15 right now, we SHOULD change to a config var)

		$this_run_count = 0;	# set to zero, then each pw crack, and decry finish increment this by 1
		switch_to_gateway($crack_svr);
		validate_crack_sw();

		# see if there are any cracks to run, and if so, then start cracking all of them  (Note, this 'could' be in the xx:42 if statement??
		IM_Sleep(4,3);
		if (scalar @sd_uncracked > 0) {
			$uncrack_cnt -= run_new_sd_cracks();
			IM_Sleep(4,3);
		}
		if ($one == 1) {
			LogLine("Exiting after loading cracks (by request)", 1);
			exit(0);
		}

		# goto crack server, complete all work, and check for any new IP's cracked.  The count of all cracked IP's is returned.
		$cracked_cnt = finish_sd_cracks();	# go back to crack server, and get new cracked IP's
		if ($comp_mode > 0) { @sd_cracked = (); }	# we will never run these crackes.  We run the cracks we get from the other server.
		IM_Sleep(4,3);

		# goto Decr server, Start any new decrs
		if ($comp_mode == 0) { switch_to_gateway($decr_svr); }
		perform_IDS_check(2);
		validate_decr_sw();
		my $some_crk = 1;
		if ($some_crk) {
			run_new_sd_decr();
			IM_Sleep(4,3);
		}
		finish_sd_decr();

		if ($this_run_count < 6) {
			IM_Sleep(30,20);
		} else {
			IM_Sleep(1,2);
		}
	}
}
sub trim {
	# left/right trim spaces.
	my $s = shift;
	$s =~ s/^\s+|\s+$//g;
	return $s;
}
sub ConfigLine {
	if (!defined $_[0] || substr($_[0], 0, 1) eq "#") { return; }
	my $line = $_[0];
	chomp $line;
	my @ar = split('`', $line);
	if (scalar @ar != 2) { return; }
	trim($ar[0]); trim($ar[1] );
	if ($ar[0] eq "breakers") {
		$breaker_file = $ar[1];
	} elsif ($ar[0] eq "logdir") {
		$ldir = $ar[1];
	} elsif ($ar[0] eq "password") {
		$pass = $ar[1];
	} elsif ($ar[0] eq "ids_pass") {
		$ids_pass = $ar[1];
	} elsif ($ar[0] eq "user") {
		$user = $ar[1];
	} elsif ($ar[0] eq "crack_svr") {
		$crack_svr = $ar[1];
	} elsif ($ar[0] eq "decr_svr") {
		$decr_svr = $ar[1];
	} elsif ($ar[0] eq "sd_ip_dat") {
		$sd_ip_dat = $ar[1];
	} elsif ($ar[0] eq "bouncemax") {
		$bounceMax = $ar[1];
	} elsif ($ar[0] eq "gold") {
		$gold = $ar[1];
	} elsif ($ar[0] eq "agent") {
		$agent = $ar[1];
	} elsif ($ar[0] eq "ids_gateway") {
		push (@ids_gateways, $ar[1]);	# there can be many of these.
	} elsif ($ar[0] eq "userid") {
		$userid = $ar[1];
	} elsif ($ar[0] eq "ids_group_svr_cnt") {
		$ids_group_count = $ar[1];
	}
}
sub LoadConfig {
	@ids_gateways = ();
	open FILE, $_[0];
	foreach my $line (<FILE>) {
		ConfigLine($line);
	}
	close(FILE);
	my $s = ValidateOptions();
	if (length($s) > 0) { print "config file error:  [$s]\n"; exit(1); }
}
sub ValidateOptions {
	if (scalar @ids_gateways == 0) { return "ids_gateways"; }
	if (length($ldir) == 0) { return "ldir"; }
	if (length($user) == 0) { return "user"; }
	if (length($pass) == 0) { return "pass"; }
	if (length($userid) == 0) { return "userid"; }
	if (length($crack_svr) == 0) { return "crack_svr"; }
	if (length($decr_svr) == 0) { return "decr_svr"; }
	return "";
}
sub switch_to_gateway {
	#####################################################################
	# If we are not on specific gateway, switch to it.
	#####################################################################
	my $svr_id = $_[0];
	my $ip = $gateway_ips{$svr_id};
	my $scr; my $scr2;

	$scr  = "TAB T=1\n";
	$scr .= "SET !ERRORIGNORE YES\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "SET !EXTRACT_TEST_POPUP NO\n";
	$scr .= "WAIT SECONDS=".rand_time(0.10+$extra_delay_run_new_sd_cracks,0.02)."\n";
	$scr .= "TAG POS=1 TYPE=TD ATTR=TXT:IP<SP>[* EXTRACT=TXT\n";
	$scr .= "WAIT SECONDS=".rand_time(0.10+$extra_delay_run_new_sd_cracks,0.02)."\n";
	$err = $iim->iimPlayCode($scr, 600);
	imacro_err ($err, "switch_to_gateway1.iim");
	my $s = $iim->iimGetLastExtract(1);
	if (defined $ip && index($ip, $s) > -1) {
		LogLine ("Already on gateway $svr_id   $gateway_ips{$svr_id}.  No switch needed", 2);
		return;
	}

	$scr2  = "TAB T=1\n";
	$scr2 .= "SET !ERRORIGNORE YES\n";
	$scr2 .= "SET !TIMEOUT_STEP 0\n";
	$scr2 .= "SET !EXTRACT_TEST_POPUP NO\n";
	$scr2 .= "'\n' switch to gateway {$svr_id}\n";
	$scr2 .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_run_new_sd_cracks,0.1)."\n";
	$scr2 .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_gate ATTR=NAME:g_id CONTENT=\%$svr_id\n";
	$scr2 .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_run_new_sd_cracks,0.1)."\n";
	$scr2 .= "TAG POS=1 TYPE=A ATTR=TXT:Connect\n";
	$scr2 .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_run_new_sd_cracks,0.1)."\n";
	$err = $iim->iimPlayCode($scr2, 600);
	imacro_err ($err, "switch_to_gateway2.iim");
	if (!defined $ip) {
		$err = $iim->iimPlayCode($scr, 600);
		imacro_err ($err, "switch_to_gateway1.iim");
		$gateway_ips{$svr_id} = $iim->iimGetLastExtract(1);
	}
	LogLine ("Changed to gateway $svr_id   $gateway_ips{$svr_id}", 2);
}
sub get_new_missions {
	#####################################################################
	# goes out and walks ALL faction IP's, getting all faction missions.
	# It then loads all mission information into our data structures,
	# so we know what new missions we have to do.
	#####################################################################
	my $i;
	my $scr;

	$scr  = "TAB T=1\n";
	$scr .= "SET !ERRORIGNORE YES\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:IP<SP>Database\n";
	$scr .= "WAIT SECONDS=" . rand_time(0.3+$extra_delay_get_new_missions,0.25) . "\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Faction\n";
	$scr .= "WAIT SECONDS=" . rand_time(0.3+$extra_delay_get_new_missions,0.25) . "\n";
	for ($i = 0; $i < scalar @IPs; ++$i) {
		$scr .= "TAG POS=1 TYPE=INPUT:TEXT FORM=NAME:fc ATTR=NAME:con_ip CONTENT=$IPs[$i]\n";
		$scr .= "WAIT SECONDS=" . rand_time(0.12+$extra_delay_get_new_missions,0.05) . "\n";
		$scr .= "TAG POS=3 TYPE=A ATTR=TXT:Connect\n";
		#$scr .= "WAIT SECONDS=" . rand_time(0.12+$extra_delay_get_new_missions,0.05) . "\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Secret<SP>faction<SP>board\n";
		#$scr .= "WAIT SECONDS=" . rand_time(0.12+$extra_delay_get_new_missions,0.05) . "\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Accept<SP>All\n";
		$scr .= "WAIT SECONDS=" . rand_time(0.12+$extra_delay_get_new_missions,0.05) . "\n";
		$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Connect\n";
		#$scr .= "WAIT SECONDS=" . rand_time(0.12+$extra_delay_get_new_missions,0.05) . "\n";
	}
	$scr .= "WAIT SECONDS=" . rand_time(1+$extra_delay_get_new_missions,0.8). "\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Mission<SP>data\n";
	$scr .= "WAIT SECONDS=" . rand_time(0.3+$extra_delay_get_new_missions,0.25) . "\n";

	$err = $iim->iimPlayCode($scr, 240);
	imacro_err ($err, "get_missions.iim");

	return $err;
}
sub reload_missions_tables {
	#####################################################################
	# Loads data from ../data/mission_table_$user.csv and looks for any
	# N/A S-D missions.  If it finds any, it starts cracks going for them.
	#####################################################################
	my $line = "";
	my $i;
	my $scr;

	LogLine("Pulling data from ../data/mission_table_$user.csv  to find S/D missions", 2);

	$scr  = "TAB T=1\n";
	$scr .= "SET !ERRORIGNORE NO\n";
	$scr .= "SET !TIMEOUT_STEP 1\n";
	$scr .= "SET !EXTRACT_TEST_POPUP NO\n";
	$scr .= "WAIT SECONDS=" . rand_time(0.3+$extra_delay_reload_missions_tables,0.2) . "\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Mission<SP>data\n";
	$scr .= "WAIT SECONDS=" . rand_time(0.3+$extra_delay_reload_missions_tables,0.2) . "\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Faction\n";
	$scr .= "WAIT SECONDS=" . rand_time(0.3+$extra_delay_reload_missions_tables,0.2) . "\n";
	$iim->iimPlayCode($scr, 600);
	@sd_uncracked = (); @dl_uncracked = (); @rc_uncracked = ();
	my @sd_cracking = (); my @dl_cracking = (); my @rc_noadmin = (); my @rc_admin = ();
	my $DECRTEMPFILE;
	if ($comp_mode > 0) { open ($DECRTEMPFILE, ">", $decr_input_file.'tmp'); }
	my $k;
	for ($k = 0; $k < 64; ++$k) {
		$scr  = "TAB T=1\n";
		$scr .= "SET !ERRORIGNORE NO\n";
		$scr .= "SET !TIMEOUT_STEP 1\n";
		$scr .= "SET !EXTRACT_TEST_POPUP NO\n";
		if ($gold eq 'yes') {
		$scr .= "TAG POS=12 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
		} else {
		$scr .= "TAG POS=13 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
		}
		$scr .= "WAIT SECONDS=" . rand_time(0.15+$extra_delay_reload_missions_tables,0.1) . "\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
		$scr .= "WAIT SECONDS=" . rand_time(0.1,0.01) . "\n";
		$iim->iimPlayCode($scr, 600);
		$line = $iim->iimGetLastExtract(1);
		my $fstr = $line;
		my $fnd = 0;
		$line =~ s/\r\n//g;
		$line =~ s/#NEXT##NEWLINE#/,/g;
		$line =~ s/#NEXT#/,/g;
		my @ar = split(",", $line);
		for ($i = 0; $i < scalar @ar - 5; ++$i) {
			if ($ar[$i] eq 'Mark' && $ar[$i+3] eq 'Connect') {
				$fnd = 1;
				my $faction = $ar[++$i];
				my $ip = $ar[++$i];
				my $con = $ar[++$i];
				my $bou = $ar[++$i];
				my $admin = $ar[++$i];
				my $serv_type = $ar[++$i];	# IP data N/A   or   Unlisted faction Server  etc.
				my $type = $ar[++$i];
				if ($admin eq "Admin: No") {
					if ($serv_type eq "IP data N/A") {
						# uncracked and not started on crack server.
						if ($type eq "Search and Destroy") { 
							push @sd_uncracked, $ip;
							if ($comp_mode > 0) { print $DECRTEMPFILE "$ip\n"; }
						}
						elsif ($type eq "Steal Research file") { push @dl_uncracked, $ip;  }
						elsif ($type eq "Recover Codes") { push @rc_uncracked, $ip; }	# should not see this (until the server roll times)
					} else {
							# uncracked but started on crack server.
							if ($type eq "Search and Destroy") { push @sd_cracking, $ip; }
							elsif ($type eq "Steal Research file") {  push @dl_cracking, $ip; }
							elsif ($type eq "Recover Codes") {  push @rc_noadmin, $ip; }
					}
				} else {
					# cracked items.
					if ($type eq "Recover Codes") {
						push (@rc_admin, $ip); 
					}
				}
			}
		}
		if ($fnd == 0 && length $fstr < 6000) {
			$k = 100;
			next;
		}
	}

	if ( (scalar @sd_uncracked) + (scalar @dl_uncracked) + (scalar @rc_uncracked)) {
		my $logline = "  there are ";
		if (scalar @sd_uncracked) { $logline .= scalar @sd_uncracked . " S/D, "; }
		if (scalar @dl_uncracked) { $logline .= scalar @dl_uncracked . " Steal, "; }
		if (scalar @rc_uncracked) { $logline .= scalar @rc_uncracked . " R/C, "; }
		$logline .= "uncracked missions";
		LogLine ($logline, 1);
	}
	if ( (scalar @sd_cracking) + (scalar @dl_cracking)) {
		my $logline = "  there are ";
		if (scalar @sd_cracking) { $logline .= scalar @sd_cracking . " S/D, "; }
		if (scalar @dl_cracking) { $logline .= scalar @dl_cracking . " Steal, "; }
		$logline .= "missions cracking";
		LogLine ($logline, 1);
	}
	if ( (scalar @rc_noadmin) + (scalar @rc_admin)) {
		my $logline = "  there are ";
		if (scalar @rc_noadmin) { $logline .= scalar @rc_noadmin . " with no admin, and "; }
		if (scalar @rc_admin) { $logline .= scalar @rc_admin . " with cracked admin "; }
		$logline .= "R/C missions";
		LogLine ($logline, 1);
	}
	my $cntx = scalar @sd_uncracked;
	if ($comp_mode > 0) {
		close ($DECRTEMPFILE);
		if (scalar @sd_uncracked) {
			# append IPs to the 'real' decr input file.
			open ($DECRTEMPFILE, "<", $decr_input_file.'tmp');
			open FILE, ">>", $decr_input_file;
			foreach my $s (<$DECRTEMPFILE>) { print FILE $s; }
			close ($DECRTEMPFILE);
			close (FILE);
			open (FILE, ">", $decr_input_flag_file);
			print FILE "Done ".scalar @sd_uncracked." items\n";
			close (FILE);
		}
		unlink ($decr_input_file.'.tmp');
	}
	return scalar $cntx;
}
sub run_new_sd_cracks {
	#####################################################################
	# Looks through running processes, for any PW breaks complete. Any
	# found, get completed, AND the IP's are updated so that we know they
	# are ready to start decr missions.
	#####################################################################
	if (scalar @sd_uncracked == 0) { return 0; }
	my $i; my $cnt = 0; my $scr;
	my $long_wait = int rand(23)+40;

	LogLine ("Starting run_new_sd_cracks() There are ".scalar @sd_uncracked." cracks to run.", 2);

	$scr  = "TAB T=1\n";
	$scr .= "SET !ERRORIGNORE YES\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "SET !EXTRACT_TEST_POPUP NO\n";
	$scr .= "WAIT SECONDS=".rand_time(0.2+$extra_delay_run_new_sd_cracks,0.05)."\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Gateway\n";
	$scr .= "WAIT SECONDS=".rand_time(0.4+$extra_delay_run_new_sd_cracks,0.05)."\n";
	$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Connect\n";
	$scr .= "WAIT SECONDS=".rand_time(0.4+$extra_delay_run_new_sd_cracks,0.05)."\n";
	$scr .= "'\n' End of header\n'\n";

	my @Breakers = @breakers;
	foreach my $ip (@sd_uncracked) {
		next if($ip eq "None");
		next if (scalar @Breakers < 1);	# make it so fewer breakers than IP's is 'ok'
		my $proc = pop(@Breakers);
		$scr .= "TAG POS=1 TYPE=INPUT:TEXT ATTR=NAME:con_ip CONTENT=$ip\n";
		$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=3 TYPE=A ATTR=TXT:Connect\n";
		$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Crack<SP>admin\n";
		$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_crack ATTR=NAME:sel_break CONTENT=\%$proc\n";
		$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_cracks,0.05)."\n"; 
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Start<SP>crack\n";
		$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_cracks,0.05)."\n";
		if ($add_to_db > 0) {
			$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Add<SP>to<SP>IP<SP>Db\n";
			$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_cracks,0.05)."\n";
		}
		++$cnt;
		$scr .= "' [$cnt of ".scalar @sd_uncracked."] done! [$ip]\n";
		push(@sd_cracking, $ip);
	}

	LogLine ("found " . scalar @sd_uncracked . " S/D procesing $cnt ", 1);
	LogLine ("===========================================================", 1);
	$err = $iim->iimPlayCode($scr, 1200);	# NOTE, this script does need to run longer.  600s is not enough!
	imacro_err ($err, "get_missions.iim");
	$hour_crk_start += scalar @sd_uncracked;
	@sd_uncracked = ();
	return $cnt;
}
sub finish_sd_cracks {
	#####################################################################
	# Calls complete for all tasks. Once all have been completed on a page, we
	# scan through the data, looking for the completed IP's.
	#####################################################################
	#if (scalar @sd_cracking == 0) { return; }

	LogLine ("In finish_sd_cracks() function.  PREPARING to run complete cracks", 2);

	my $tot = 1;
	while ($tot > 0) {
		my $scr;
		my $uncheck_str = "";
		my $idx = 1;
		if ($complete_non_breakers==0) {
		    $iim->iimPlayCode("VERSION BUILD=10022823\nTAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM");
			my $s = $iim->iimGetLastExtract(1);
			$s =~ s/%//g;
			
			my $pos = index($s, "script language=\"JavaScript\">document.write(unescape('");  # 55 bytes long.
			while ($pos != -1) {
				$s = substr($s, $pos+54);
				$pos = index($s, "'");
				my $p = substr($s, 0, $pos);
				# ok, now crack the bitch
				my $v = pack("H*", $p);
				if (index($v, "Password Break") == -1 && index($v, "decrypt file #") == -1) {
					$pos = index($v, "document.frm_files.");
					$pos += 19;
					$v = substr($v, $pos);
					$pos = index($v, ")");
					$uncheck_str .= "TAG POS=1 TYPE=INPUT:CHECKBOX FORM=NAME:frm_files ATTR=NAME:".substr($v, 0, $pos)." CONTENT=NO\n";
					
				}
				$pos = index($s, "script language=\"JavaScript\">document.write(unescape('");
			}
		}
		$scr  = "TAB T=1\n";
		$scr .= "SET !ERRORIGNORE YES\n";
		$scr .= "SET !TIMEOUT_STEP 0\n";
		$scr .= "SET !EXTRACT_TEST_POPUP NO\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
		$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_finish_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=\$Completed<SP>tasks\n";
		$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_finish_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Sel\n";
		if ($complete_ip_change == 0) {
			$scr .= "' MAKE sure that the change IP is NOT checked!!!\n";
			$scr .= "TAG POS=1 TYPE=TD ATTR=TXT:Change<SP>gateway<SP>IP<SP>[Owned][localhost]<SP>-><SP>task*\n";
			$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_finish_sd_cracks,0.05)."\n";
		}
		$scr .= $uncheck_str;
		$scr .= "WAIT SECONDS=.1\n";
		
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:a3 CONTENT=\$Complete<SP>Task\n";
		$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_finish_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Confirm\n";
		# now find completed, or IPs that no longer exist.  Remove them from @sd_uncracked.  Add cracked ones to @sd_cracked
		$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_finish_sd_cracks,0.05)."\n";
		$scr .= "TAG POS=8 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
		$scr .= "TAG POS=9 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
		$scr .= "TAG POS=10 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";

		$err = $iim->iimPlayCode($scr, 600);
		imacro_err ($err, "get_missions.iim");
		my $str = $iim->iimGetLastExtract(1);
		$str .= $iim->iimGetLastExtract(2);
		$str .= $iim->iimGetLastExtract(3);
		my @ar1 = split("\n", $str);

		$tot = 0;
		foreach my $s (@ar1) {
			# " Password for 97.49.186.1 acquired."
			if (index($s, "Password for ") >= 0 && index($s, " acquired.") >= 0) {
				@ar = split(" ", substr($s,1));
				push (@sd_cracked, $ar[2]);
				++$tot;
			}
		}
		close(FILE);
	}
	$this_run_count += scalar @sd_cracked;
	$hour_crk_done += scalar @sd_cracked;
	if (scalar @sd_cracked) { LogLine("Decrypting " . scalar @sd_cracked . " servers", 2-$comp_mode); }
	foreach my $s (@sd_cracked) { LogLine($s,2); }

	# An enemy was seen.  If we have no cracks done this time then assume all cracks are done, AND 
	if ($nite_mode == 2 && scalar @sd_cracked == 0) {
		$nite_mode = 3;
		IM_Sleep(1,1);
		switch_to_gateway($decr_svr);
		IM_Sleep(1,1);
		change_ip();
	}

	return scalar @sd_cracked;
}
sub run_new_sd_decr {
	if (scalar @sd_cracked == 0) { return; }
	if ($comp_mode > 0) { return; }
	my $scr;

	if (scalar @sd_cracked) { LogLine("Decrypting " . scalar @sd_cracked . " servers", 1); }

	my $cnt = scalar @sd_cracked;
	my $cur = 1;
	foreach my $ip (@sd_cracked) {
		$scr  = "TAB T=1\n";
		$scr .= "SET !ERRORIGNORE YES\n";
		$scr .= "SET !TIMEOUT_STEP 0\n";
		$scr .= "'\n' $cur of $cnt\n'\n";
		++$cur;
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Connect\n";
		$scr .= "TAG POS=1 TYPE=INPUT:TEXT FORM=NAME:fc ATTR=NAME:con_ip CONTENT=$ip\n";
		$scr .= "TAG POS=3 TYPE=A ATTR=TXT:Connect\n";
		$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Decrypt\n";
		# if the 'Decrypt' button is not there, we get a $err < 0  Thus we know if it was good or not.
		$err = $iim->iimPlayCode($scr, 1200);
		if ($err > 0) {
			$hour_dec_start++;
		} else {
			$scr  = "TAB T=1\n";
			$scr .= "SET !ERRORIGNORE YES\n";
			$scr .= "SET !TIMEOUT_STEP 0\n";
			$scr .= "'\n' end of header\n'\n";
			$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Activate\n";
			# need to do an extract here and NOT use the $err < 0 check
			$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_run_new_sd_decr,0.1)."\n";
			$scr .= "TAG POS=1 TYPE=SPAN ATTR=CLASS:red EXTRACT=TXT\n";
			$scr .= "TAG POS=3 TYPE=SPAN ATTR=CLASS:green EXTRACT=TXT\n";
			$scr .= "WAIT SECONDS=".rand_time(0.05+$extra_delay_run_new_sd_decr,0.1)."\n";
			$err = $iim->iimPlayCode($scr, 1200);
			my $fail = $iim->iimGetLastExtract(1);
			my $success = $iim->iimGetLastExtract(2);
			if (index($success, "VERIFIED!") > -1) {
				#$hour_dec_start++;
				#$hour_dec_done++;
				$this_run_count++;
			} else {
				$hour_dec_dead++;
			}
		}
	}
	@sd_cracked = ();
	LogLine("Decrypt Run Done", 2);
}
sub finish_sd_decr {
	#####################################################################
	# Runs complete mission on the running software.  This gets the cash.
	#####################################################################
	my $scr;
	if ($comp_mode > 0) {
		reload_comp_mode_missions();
		if (scalar @sd_tocomplete == 0) { return; }
		my $cnt = 0; my $cnt_dead=0;
		for (my $i = 0; defined $sd_tocomplete[$i]; ++$i) {
			my $ip = $sd_tocomplete[$i];
			next if ($ip eq "X");	# in case one got through.
			$scr = "SET !TIMEOUT_STEP 0\n";
			$scr .= "SET !ERRORIGNORE YES\n";
			$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Connect\n";
			$scr .= "'\n";
			$scr .= "'  end of header lines\n";
			$scr .= "'\n";
			$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Connect\n";
			$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
			$scr .= "TAG POS=1 TYPE=INPUT:TEXT FORM=NAME:fc ATTR=NAME:con_ip CONTENT=$ip\n";
			$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
			$scr .= "TAG POS=3 TYPE=A ATTR=TXT:Connect\n";
			$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
			$scr .= "TAG POS=1 TYPE=SPAN ATTR=CLASS:red EXTRACT=TXT\n";
			$scr .= "WAIT SECONDS=".rand_time(0.05+$extra_delay_run_new_sd_decr,0.02)."\n";
			$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
			$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
			$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Activate\n";
			$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
			$scr .= "TAG POS=3 TYPE=SPAN ATTR=CLASS:green EXTRACT=TXT\n";
			$scr .= "WAIT SECONDS=".rand_time(0.05+$extra_delay_run_new_sd_decr,0.02)."\n";
			$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Connect\n";
			$err = $iim->iimPlayCode($scr, 600);
			imacro_err ($err, "complete_comp_missions.iim");
			if ($iim->iimGetLastExtract(1) eq 'VERIFIED!' || $iim->iimGetLastExtract(2) eq 'VERIFIED!') { 
				++$cnt;
				$sd_tocomplete[$i] = "X";
			} elsif ($iim->iimGetLastExtract(1) eq 'Request timed out.') { 
				++$cnt_dead;
				$sd_tocomplete[$i] = "X";
			}
			# !!!Need to also handle the IP does not exist any more, and remove it from the list!!!
			# does the 'Request timed out.' check do this?????
		}
		if ($cnt) {
			my @a = @sd_tocomplete;
			@sd_tocomplete = ();
			foreach my $s (@a) {
				if ($s ne "X") {
					push @sd_tocomplete, $s;
				}
			}
		}
		if ($cnt > 1 || $cnt_dead) {
			LogLine("Completed $cnt missions  (lost $cnt_dead)", 1);
		}
		$hour_dec_done += $cnt;
		$this_run_count += $cnt;
		$hour_dec_dead += $cnt_dead;
		return;
	}

	LogLine("Starting completion loop", 2);
	my $cnt = 0;
	$scr  = "TAB T=1\n";
	$scr .= "SET !ERRORIGNORE YES\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_run_new_sd_decr,0.2)."\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=\$Completed<SP>tasks\n";
	$scr .= "WAIT SECONDS=".rand_time(0.15+$extra_delay_run_new_sd_decr,0.2)."\n";
	$err = $iim->iimPlayCode($scr, 600);
	imacro_err ($err, "complete_decr_missions.iim");

	$scr  = "SET !ERRORIGNORE YES\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "TAG POS=4 TYPE=A ATTR=TXT:Connect\n";
	$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
	if ($decr_mode > 0) {
	$scr .= "TAG POS=4 TYPE=SPAN ATTR=CLASS:green EXTRACT=TXT\n";
	$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
	}
	$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.0)."\n";
	$scr .= "TAG POS=11 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=12 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=13 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=14 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:task<SP>complete\n";
	$scr .= "TAG POS=2 TYPE=A ATTR=TXT:task<SP>complete\n";
	if ($decr_mode == 0) {
	$scr .= "TAG POS=2 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Activate\n";
	$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";
	}
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "TAG POS=8 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=9 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=10 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=11 TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "WAIT SECONDS=".rand_time(0.1+$extra_delay_run_new_sd_decr,0.05)."\n";

	my $more = 1;
	my $enemy_seen = 0;
	$cnt = 0;
	my $cnt2 = 0;
	my $TEMP_FILE;
	my $cur_enemy_ip = "";
	my %cur_enemy_ips = ();
	if ($decr_mode > 0) { open ($TEMP_FILE, ">", $comp_input_file.".tmp"); }
	while ($more) {
		$err = $iim->iimPlayCode($scr, 600);
		# check extract(1) to (4) for IP's from gateways other than ours.  
		my $txt = $iim->iimGetLastExtract(1);
		my $x1 = $iim->iimGetLastExtract(2); $txt .= $x1;
		$x1 = $iim->iimGetLastExtract(3);    $txt .= $x1;
		$x1 = $iim->iimGetLastExtract(4);    $txt .= $x1;
		my $me=0;
		foreach my $s ($txt) {
			my $pos = index($s, "/root/OS/os.sock V");
			while ($pos > -1) {
				$s = substr($s, $pos+10);
				my $s2 = substr($s, 0, 40);
				if (index($s2, "Owned") == -1) {
					my $enemy_ip = "";
					if($s2 =~/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/){
						$enemy_ip = $1;
					}
					if (length($enemy_ip) > 0) {
						$enemy_seen = 1;
						if (!defined $enemy_decr{$enemy_ip}) {$enemy_decr{$enemy_ip}=0;}
						$enemy_decr{$enemy_ip} += 1;
						$cur_enemy_ips{$enemy_ip} += 1;
					}
				} else {
					++$me;
				}
				$pos = index($s, "/root/OS/os.sock V");
			}
		}
		$cnt += !!$me;	# me count can be more than 1 (more than 1 decr started). But only count 1 for this server.
		if (scalar %cur_enemy_ips ne "0") {
			$cur_enemy_ip = "  Enemy: ";
			while (my ($ip, $cnt) = each(%cur_enemy_ips)) {
				$cur_enemy_ip .= "$ip($cnt) ";
			}
		}
		$more = 0;
		my $table = $iim->iimGetLastExtract(5);
		my $x = $iim->iimGetLastExtract(6);
		$table .= $x;
		$x = $iim->iimGetLastExtract(7);
		$table .= $x;
		$x = $iim->iimGetLastExtract(8);
		$table .= $x;
		if ($decr_mode > 0) {
			$x = $iim->iimGetLastExtract(9);
			$table .= $x;
			$x = $iim->iimGetLastExtract(5);
		}
		if (index($table, '/root/OS/os.sock V') > -1) {$more = 1; } # && index($table, 'class="smlink">Bounce</a>]') > -1 && index($table, 'gate&a2=connect&bounce_ip=') > -1 ) { $more = 1; }
		if ($decr_mode > 0) {
			$ip = $iim->iimGetLastExtract(5);
			if (index($ip, "#EANF#") == -1) {
				print $TEMP_FILE "$ip\n";
				++$cnt2;
			}
		}
	}
	if ($cnt>=$min_decr_to_show||length($cur_enemy_ip)>0) { LogLine("Completed $cnt missions$cur_enemy_ip", 1); }
	elsif ($cnt == 0) { LogLine("Found no completed tasks!", 2); }
	else { LogLine("Completed $cnt missions", 2); IM_Sleep(18,8); }
	$hour_dec_done += $cnt;
	$this_run_count += $cnt;
	if ($decr_mode > 0) {
		close($TEMP_FILE);
		if ($cnt2) {
			open ($TEMP_FILE, "<", $comp_input_file.".tmp");
			open FILE, ">>", $comp_input_file; 
			foreach my $s (<$TEMP_FILE>) { print FILE "$s"; }
			close (FILE);
			close ($TEMP_FILE);
			open FILE, ">", $comp_input_flag_file;
			print FILE "got some\n";
			close (FILE);
		}
		unlink ($comp_input_file.".tmp");
	}
	# An enemy was seen.  Set the flag to list this fact.
	if ($enemy_seen > 0 && $nite_mode == 1) {
		$nite_mode = 2;
	} elsif ($nite_mode == 3) {
		# see if we are done (i.e. no decr left).  If so, then exit.
		$scr = "SET !TIMEOUT_STEP 0\n";
		$scr .= "SET !ERRORIGNORE YES\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Connect\n";
		$scr .= "WAIT SECONDS=.2\n";
		$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
		$scr .= "WAIT SECONDS=.2\n";
		$scr .= "'\n";
		$scr .= "'  end of header lines\n";
		$scr .= "'\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%pid_desc\n";
		$scr .= "wait seconds=.5\n";
		$scr .= "TAG POS=1 TYPE=TD ATTR=* EXTRACT=TXT\n";
		$scr .= "wait seconds=.5\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%complete\n";
		$scr .= "wait seconds=.5\n";
		$err = $iim->iimPlayCode($scr, 600);
		imacro_err ($err, "complete_decr_missions.iim");
		my $txt = $iim->iimGetLastExtract(1);
		if (index($txt, "decrypt file #") == -1) {
			print "All work done, and since we are in EXIT nite mode, we are exiting\n";
			$hour_dec_done += $cnt;
			$this_run_count += $cnt;
			drop_stats();
			exit(0);
		}
	}
}
sub change_ip {
	# called in nite mode when we first see an enemy IP competing with our decr server.
	#  We change IP, set a new 24 hour IP change, and then complete the work.
	my $scr;

	LogLine ("In change_ip() function.  An enemy system was seen, and we are hiding", 1);
	$scr  = "TAB T=1\n";
	$scr .= "SET !ERRORIGNORE YES\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Connect\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "'\n";
	$scr .= "' Check the change IP task (hopefully it is still here!!!)\n";
	$scr .= "TAG POS=1 TYPE=TD ATTR=TXT:Change<SP>gateway<SP>IP<SP>[Owned][localhost]<SP>-><SP>task*\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:a3 CONTENT=\$Complete<SP>Task\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Confirm\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Disconnect\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Change <SP>IP\n";
	$scr .= "WAIT SECONDS=.2\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Yes,<SP>change<SP>IP!\n";
	$scr .= "WAIT SECONDS=.2\n";
	$err = $iim->iimPlayCode($scr, 600);
	imacro_err ($err, "complete_comp_missions.iim");
}
sub drop_stats {
	################################################################################
	#   Called every hour, right before going to faction servers to get new missions.
	################################################################################
	if ($hour_crk_start) { LogLine("Started  $hour_crk_start cracks this hour",1); }
	if ($hour_crk_done)  { LogLine("Finished $hour_crk_done cracks this hour",1);  }
	if ($hour_dec_start) { LogLine("Started  $hour_dec_start decryp this hour",1); }
	if ($hour_dec_done)  {
		if ($hour_dec_dead)  { LogLine("Finished $hour_dec_done decryp this hour  (lost $hour_dec_dead)",1);  }
		else { LogLine("Finished $hour_dec_done decryp this hour",1);  } 
	}
	elsif ($hour_dec_dead)  { LogLine("lost all: $hour_dec_dead",1);  }
	$hour_crk_start=0;
	$hour_crk_done=0;
	$hour_dec_start=0;
	$hour_dec_done=0;
	$hour_dec_dead=0;
	my $first = 1;
	while(my($ip, $cnt) = each %enemy_decr) {
		if ($first) {
			LogLine ("===========================================================", 1);
			LogLine ("!!!WARNING!!! Some enemy IPs were seen this hour!", 1);
		}
		$first = 0;
		LogLine ("   Enemy IP: $ip seen $cnt times this hour",1);
	}
	%enemy_decr = (); 
}
sub reload_decr_mode_missions {
	################################################################################
	#   Functions used in dual player mode (where one decrypts, the other completes)
	#     We use flat files to shoot data back and forth between the 2 players.
	################################################################################
	# open a file, and if it exists, get the IPs.
	open (FILE, $decr_input_flag_file) or return;
	close(FILE);
	open (FILE, $decr_input_file) or return;
	@sd_uncracked = ("None");
	foreach my $ip (<FILE>) {
		chomp $ip;
		push @sd_uncracked, $ip;
	}
	close(FILE);
	unlink($decr_input_flag_file);
	unlink($decr_input_file);
	if ( (scalar @sd_uncracked) > 1 ) {
		LogLine ("  there are " . scalar @sd_uncracked-1 . " S/D missions, found in the -teamcomp file", 1);
	}
}
sub reload_comp_mode_missions {
	################################################################################
	#   Functions used in dual player mode (where one decrypts, the other completes)
	#     We use flat files to shoot data back and forth between the 2 players.
	################################################################################
	# open a file, and if it exists, get the IPs.
	open (FILE, $comp_input_flag_file) or return;
	close(FILE);
	open (FILE, $comp_input_file) or return;
	foreach my $ip (<FILE>) {
		chomp $ip;
		push @sd_tocomplete, $ip;
	}
	close(FILE);
	unlink($comp_input_flag_file);
	unlink($comp_input_file);
	if ( (scalar @sd_tocomplete) ) {
		LogLine ("  there are " . scalar @sd_tocomplete . " S/D missions still to_complete", 2);
	}
}
sub is_hex32 {
	# there has to be a better way, BUT this works, lol
	if (length $_[0] != 32) { return 0; }
	my @ar = split("", $_[0]);
	for (my $i = 0; $i < 32; ++$i) {
		if (index("0123456789abcdef",$ar[$i]) == -1) {
			return 0;	 # not a 32 byte lower case hex string (as should be in the IDS signature)
		}
	}
	return 1;
}
sub get_log_lines {
	my $cnt = $_[1];  my $scr;
	my $svr = $_[0];
	my @LogLines = (); my $LogCnt = 0;
	if (!defined $cnt) { $cnt = 1; }
	
	$scr  = "TAB T=1\n";
	$scr .= "SET !EXTRACT_TEST_POPUP NO\n";
	$scr .= "SET !TIMEOUT_STEP 0\n";
	$scr .= "wait seconds=.1\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Logs\n";
	$scr .= "wait seconds=.1\n";
	for (my $i = 1; $i <= 10; ++$i) {
		my $j = $i*2;
		$scr .= "TAG POS=$i TYPE=TEXTAREA ATTR=CLASS:logText&&NAME:log_str EXTRACT=TXT\n";
		$scr .= "TAG POS=$j TYPE=TD ATTR=CLASS:dbg EXTRACT=TXT\n";
	}
	$scr .= "wait seconds=.1\n";
	$scr .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr .= "wait seconds=.1\n";
	for (my $a = 0; $a < $cnt; ++$a) {
		$err = $iim->iimPlayCode($scr);
		imacro_err ($err, "get_log_data.iim");
		# get the data returned.
		for (my $i = 1; $i <= 20; $i += 2) {
			my $log = $iim->iimGetLastExtract($i);
			if (index($log,"#EANF#") > -1) { return return @LogLines; }
			my $date = $iim->iimGetLastExtract($i+1);
			$LogCnt++;
			push (@LogLines, "$date\t$log");
			if (Digest::MD5::md5_hex($date."...${ids_pass}...".$date) eq $log) {
				$LogLines[$LogCnt-1] .= "  [IDS VALIDATED]";
			} elsif (is_hex32($log)) {
				$LogLines[$LogCnt-1] .= "  [!! IDS HACKED !!]";
				LogLine("Svr: $svr $gateway_ips{$svr}  $LogLines[$LogCnt-1]\n", 0);
			}
		}
	}
	return @LogLines;
}
sub build_initial_IDS_data {
	# builds the initial IDS data.  It loads the @ids_gateway_logs and sets all @gateway_ips
	LogLine("Loading initial IDS data for ".scalar @ids_gateways." local gateways", 1);
	foreach my $svr_id (@ids_gateways) {
		switch_to_gateway($svr_id);
		my @ar = get_log_lines($svr_id);
		$ids_gateway_logs{$svr_id} = \@ar;
	}
	$next_ids_check = time() + $ids_delay_min*60;	# 15 min delay until next non forced IDS check.
}
sub perform_IDS_check {
	if ($_[0] == 0) {
		# perform check and ONLY do this code every $ids_delay_min minutes, unless force_run is true.
		if ($next_ids_check > time()) { return; }
	}
	if ($_[0] == 2) {
		# perform check every time we go to the DECR server!
		my @ar1 = get_log_lines($decr_svr);
		if (scalar @ar1 == 0) {
			$ids_gateway_logs{$decr_svr} = \@ar1;
			return;
		}
		my $ar2 = $ids_gateway_logs{$decr_svr};
		if (scalar @ar1 == 0) {
			$ids_gateway_logs{$decr_svr} = \@ar1;
			if (scalar @$ar2 != 0) {
				LogLine ("WARNING LOG change on $gateway_ips{$decr_svr} (DECR server)\n\t\t\t\[\]\n\t\t\t\[@$ar2[0]\]\n", 0);
			}
			return;
		}
		for (my $i = 0; defined($ar2) && $i < scalar @$ar2 && $i < scalar @ar1; ++$i) {
			if ($ar1[$i] ne @$ar2[$i]) {
				if (index($ar1[0], '[IDS VALIDATED]') == -1) {
					LogLine ("WARNING LOG change on $gateway_ips{$decr_svr} (DECR server)\n\t\t\t\[$ar1[$i]\]\n\t\t\t\[@$ar2[$i]\]\n", 0);
				}
				$i = 50000;
			}
		}
		$ids_gateway_logs{$decr_svr} = \@ar1;
		return;
	}
	$next_ids_check = time() + $ids_delay_min*60;	# 15 min delay until next non forced IDS check.
	LogLine("Performing an IDS check".($_[0]>0?" forced":""), 1);
	foreach my $svr_id (@ids_gateways) {
		switch_to_gateway($svr_id);
		my @ar1 = get_log_lines($svr_id);
		my $ar2 = $ids_gateway_logs{$svr_id};
		if (scalar @$ar2 == 0 && scalar @ar1 > 0) {
			if (index($ar1[0], '[IDS VALIDATED]') == -1) {
				LogLine ("WARNING LOG change on $gateway_ips{$svr_id}\n\t\t\t\[$ar1[0]\]\n\]\n", 0);
			}
		}
		for (my $i = 0; $i < scalar @ar1 && $i < scalar @$ar2; ++$i) {
			if ($ar1[$i] ne @$ar2[$i]) {
				if (index($ar1[0], '[IDS VALIDATED]') == -1) {
					LogLine ("WARNING LOG change on $gateway_ips{$svr_id}\n\t\t\t\[$ar1[$i]\]\n\t\t\t\[@$ar2[$i]\]\n", 0);
				}
				$i = 50000;
			}
		}
		$ids_gateway_logs{$svr_id} = \@ar1;
	}
}
sub get_faction_ips {
	switch_to_gateway($crack_svr);
	my $scr1 = "";
	$scr1 .= "TAB T=1\n";
	$scr1 .= "WAIT SECONDS=".rand_time(1,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:IP<SP>Database\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.1,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Faction\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.3,.1)."\n";

	$err = $iim->iimPlayCode($scr1, 600);
	my $expected = 0;
	my $data = $iim->iimGetLastExtract(1);
	if    (index($data, "Secret True Light Server") > -1) { $faction = 'TrueLight'; $expected = 56;}
	elsif (index($data, "Secret Hakuza Server") > -1)     { $faction = 'Hakuza';    $expected = 46;}
	elsif (index($data, "Secret Icarus Server") > -1)     { $faction = 'Icarus';    $expected = 57;}
	elsif (index($data, "Secret Omnicron Server") > -1)   { $faction = 'Omnicron';  $expected = 41;}
	else                                                  { $faction = 'UNKOWN';    $expected = 0;}

	@IPs = ();
	my $fn = 1;
	while ($fn < 9) {
		$data = $iim->iimGetLastExtract($fn++);
		my $pos = index($data, "mis_");
		while ($pos > -1) {
			$data = substr($data, $pos+4);
			my $faction_check = substr($data, 0, 300);
			if (index($faction_check, "(faction)") > -1) {
				$pos = index($data, 'value="');
				$pos += 7;
				my $pos2 = index($data, '">');
				push(@IPs, substr($data, $pos, $pos2-$pos));
			}
			$pos = index($data, "mis_");
		}
		
	}

	open FILE, ">", "faction-IP-$user.dat";
	foreach my $ip (@IPs) { print FILE "$ip\n"; }
	close (FILE);
	my $tot = scalar @IPs;
	if ($tot != $expected) {
	LogLine("found $tot faction IPs for $faction  WARNING, expected to find $expected IPs", 1);
	} else {
	LogLine("found $tot faction IPs for $faction", 1);
	}
}
sub get_breaker_ids {
	my $fname = $_[0];
	LogLine("finding breakers and putting into $fname", 1);
	switch_to_gateway($crack_svr);
	my $src1 = "";
	$src1 .= "TAB T=1\n";
	$scr1 .= "WAIT SECONDS=".rand_time(1,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.2,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%4\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.2,.1)."\n";
	$scr1 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr1 .= "WAIT SECONDS=".rand_time(.2,.1)."\n";

	my $src2 = "";
	$scr2 .= "TAG POS=1 TYPE=A ATTR=TXT:Next\n";
	$scr2 .= "WAIT SECONDS=".rand_time(.2,.1)."\n";
	$scr2 .= "TAG POS=1 TYPE=HTML ATTR=* EXTRACT=HTM\n";
	$scr2 .= "WAIT SECONDS=".rand_time(.2,.1)."\n";

	my $cnt = 1;
	@breakers = ();
	$err = $iim->iimPlayCode($scr1, 600);
	my $data = $iim->iimGetLastExtract(1);
	while ($cnt > 0) {
		$cnt = 0;
		my $pos = index($data, '<td class="snl">');
		while ($pos > -1) {
			$pos += 16;
			$data = substr($data, $pos);
			my $pos2 = index($data, "</td>");
			my $id = substr($data, 0, $pos2);

			$pos = index($data, '<td class="sm">');
			$pos += 15;
			if ( substr($data, $pos, 24) eq 'Special Password Break <' || substr($data, $pos, 22) eq 'Basic Password Break <' || substr($data, $pos, 23) eq 'Stolen Password Break <') {
				push (@breakers, $id);
			}
			$pos = index($data, '<td class="snl">');
			++$cnt;
		}
		$err = $iim->iimPlayCode($scr2, 600);
		$data = $iim->iimGetLastExtract(1);
	}
	open FILE, ">",$fname;
	foreach my $s (@breakers) {
		print FILE "$s\n";
	}
	close(FILE);
	my $tot = scalar @breakers;
	LogLine("found $tot password crackers on cracker machine.", 1);
}
sub validate_base_sw {
	my $scr;
	my $tbl = 13; if ($gold eq 'no') { $tbl = 14; }
	# make log deleter, cloaker, FWP and PWP are running
	$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%24\n";	# log deleter
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%19\n";	# cloaker
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%1\n";	# FWP
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%3\n";	# PWP
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";

	$err = $iim->iimPlayCode($scr, 600);
	my $logdel = $iim->iimGetLastExtract(1);
	my $cloaker = $iim->iimGetLastExtract(2);
	my $fwp = $iim->iimGetLastExtract(3);
	my $pwp = $iim->iimGetLastExtract(4);
	if (index($logdel, "Special Log Deleter") == -1 && index($logdel, "Stolen Log Deleter") == -1) {
		# restart log del
		LogLine("WARNING!!! log deleter is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%24\n";	# log deleter
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
	if (index($cloaker, "Special IP Cloaker") == -1 && index($cloaker, "Stolen IP Cloaker") == -1) {
		# restart cloaker
		LogLine("WARNING!!! ip cloaker is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%19\n";	# Cloaker
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
	if (index($fwp, "Special Firewall Protect") == -1 && index($fwp, "Stolen Firewall Protect") == -1) {
		# restart FWP
		LogLine("WARNING!!! FWP is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%1\n";	# fwp
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
	if (index($pwp, "Special Password Protect") == -1 && index($pwp, "Stolen Password Protect") == -1) {
		# restart PWP
		LogLine("WARNING!!! PWP is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%3\n";	# pwp
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
}
sub validate_crack_sw {
	my $scr;
	my $tbl = 13; if ($gold eq 'no') { $tbl = 14; }
	# make sure that proper fwb is running
	$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%2\n";	# fwb
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$err = $iim->iimPlayCode($scr, 600);
	my $fwb = $iim->iimGetLastExtract(1);
	if (index($fwb, "Special Firewall Bypass") == -1 && index($fwb, "Stolen Firewall Bypass") == -1) {
		# restart fwb
		LogLine("WARNING!!! FWB is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%2\n";	# fwb
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
	validate_base_sw();
}
sub validate_decr_sw {
	my $scr;
	my $tbl = 13; if ($gold eq 'no') { $tbl = 14; }
	# make sure that proper unhide/decr are running is running
	$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Running<SP>Software\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%6\n";	# unhide files
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_filter CONTENT=%8\n";	# decryptor
	$scr .= "TAG POS=$tbl TYPE=TABLE ATTR=TXT:* EXTRACT=TXT\n";
	$err = $iim->iimPlayCode($scr, 600);
	my $unhider = $iim->iimGetLastExtract(1);
	my $decrypt = $iim->iimGetLastExtract(2);
	if (index($decrypt, "Special Decryptor") == -1 && index($decrypt, "Stolen Decryptor") == -1) {
		# restart decrypt
		LogLine("WARNING!!! decryptor is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%8\n";	# decryptor
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
	if (index($unhider, "Special Unhide Files") == -1 && index($unhider, "Stolen Unhide Files") == -1) {
		# restart unhide files
		LogLine("WARNING!!! Unhide Files is NOT running!  Restarting it.\n", 1);
		$scr  = "TAG POS=1 TYPE=A ATTR=TXT:Files<SP>/<SP>Programs\n";
		$scr .= "TAG POS=1 TYPE=SELECT FORM=NAME:frm_files ATTR=NAME:sel_f_filter CONTENT=%6\n";	# unhide files
		$scr .= "TAG POS=1 TYPE=A FORM=NAME:frm_files ATTR=TXT:Run\n";
		$iim->iimPlayCode($scr, 600);
	}
	validate_base_sw();
}
