use strict;
use File::Path qw(make_path remove_tree);
use File::Spec::Functions qw(catfile splitpath);
use File::Find::Rule;
use Spreadsheet::Read;
use JSON;

my %QUARTER_SECONDS = (
	1 => 8 * 60,
	2 => 8 * 60,
	3 => 8 * 60,
	4 => 8 * 60,
	5 => 5 * 60,
	6 => 5 * 60
);

my %PERCENT_COLUMNS = (
	"percent2Pt" => 1,
	"percent3Pt" => 1,
	"percentTotal" => 1,
	"percentFt" => 1
);


my $gamesDir = shift;
my $flowDir = shift;
my $outDir = shift;
my $fileMask = shift;

$fileMask = '*.ods' if(!$fileMask);

my @gameFiles = File::Find::Rule
	->maxdepth(1)
	->file()
	->name($fileMask)
	->in($gamesDir);
my %flowFiles;
my $json = JSON->new
	->utf8(1)
	->pretty(1)
	->allow_nonref(1);
my @games;
my %playerGames;
my %playerNames;
my @teamGames;
my $wins = 0;
my $losses = 0;
	
if(!-e catfile($outDir, 'games'))
{
	make_path(catfile($outDir, 'games'));
	make_path(catfile($outDir, 'games/flows'));
	make_path(catfile($outDir, 'players/average'));
	make_path(catfile($outDir, 'players/games'));
	make_path(catfile($outDir, 'players/cumulative'));
}

{
	my @fs = File::Find::Rule
		->maxdepth(1)
		->file()
		->name($fileMask)
		->in($flowDir);
	foreach my $f (@fs)
	{
		my ($v, $d, $fn) = splitpath($f);
		$fn =~ /(.+?(\d+))\.ods/;
		$flowFiles{int($2)} = $f;
	}
	print "Flow files:\n";
	print "  $_ = $flowFiles{$_}\n" foreach (keys %flowFiles);
	print "\n";
}

foreach my $inFile (sort @gameFiles)
{
	next if($inFile !~ /game\d+.ods/i);
	
	print "Processing '$inFile'...\n";
	
	my ($v, $d, $fn) = splitpath($inFile);
	$fn =~ /(.+?(\d+))\.ods/;
	my $gameNum = int($2);
	my $jsonFileName = sprintf("game%02d.json", $gameNum);
	my $outFile = catfile($outDir, catfile('games', $jsonFileName));
	my $flowFileName = GenFlowFileName($gameNum);
	print "  $outFile\n";
	#exit;
	
	my $spreadsheet = ReadData ($inFile);
	my $sheet = $spreadsheet->[1];
	my $opponent = $sheet->{cell}[1][1];
	my $opponentScore = $sheet->{cell}[2][1];
	my $gameDetail = $sheet->{cell}[3][1];
	my $location = $sheet->{cell}[4][1];
	my $gameDate = $sheet->{cell}[5][1];
	my %headers;
	
	$gameDetail =~ /([\w\s]+)/i;
	my $gameType = $1;
	$gameType =~ s/^\s+//;
	$gameType =~ s/\s+$//;
	
	#print "$opponent => $opponentScore\n";
	for(my $j = 1; $j <= $sheet->{maxcol}; $j++)
	{
		my $c = $sheet->{cell}[$j][2];
		$headers{$j} = $sheet->{cell}[$j][2] if($c);
		#print "$_ = $headers{$_}\n" foreach (sort keys %headers);
		#exit;
	}

	my %output = (
		'opponent' => $opponent,
		'opponentScore' => $opponentScore,
		'location' => $location,
		'date' => $gameDate,
		'winLoss' => '',
		'gameFlowUrl' => $flowFileName,
		'players' => []
	);

	for(my $i = 3; $i <= $sheet->{maxrow}; $i++)
	{
		my $p = $sheet->{cell}[1][$i];
		next if(!$p);
		
		my %stats = (
			'gameNumber' => $gameNum,
			'opponent' => $opponent,
			'gameType' => $gameType
		);
		foreach my $col (sort { $a <=> $b } keys %headers)
		{
			my $x = $sheet->{cell}[$col][$i];
			
			# Account for percent columns where the value does not come out formatted as a percent
			if(exists $PERCENT_COLUMNS{$headers{$col}} && $x !~ /^\d+\.\d+%$/)
			{
				$stats{$headers{$col}} = sprintf("%0.2f%%", 100.0 * $x);
			}
			elsif($x && $x =~ /^[\d\.]+$/)
			{
				$stats{$headers{$col}} = 1.0 * $x;
			}
			else
			{
				$stats{$headers{$col}} = $x;
			}
			#print "$headers{$col} => $x => $stats{$headers{$col}}\n";
		}
		
		if($p =~ /totals/i)
		{
			$output{'teamTotals'} = \%stats;
			push @teamGames, \%stats;
		}
		else
		{
			push @{$output{'players'}}, \%stats;
			
			my $n = lc $stats{'name'};
			if(!exists $playerGames{$n})
			{
				$playerGames{$n} = [];
				$playerNames{$n} = $stats{'name'};
			}
			push @{$playerGames{$n}}, \%stats;
		}
	}
	$output{'winLoss'} = ($output{'teamTotals'}->{'pointsTotal'} > $opponentScore) ? 'W' : 'L';

	open OUT_FILE, '>', $outFile
		or die "ERROR: Failed to open output file '$outFile': $!\n\n";

	print OUT_FILE $json->encode(\%output), "\n";
	close OUT_FILE;
	
	my %gi = (
		'gameNumber' => $gameNum,
		'gameDetail' => $gameDetail,
		'gameType' => $gameType,
		'gameFlowUrl' => $flowFileName,
		'location' => $location,
		'date' => $gameDate,
		'opponent' => $opponent,
		'scoreFor' => $output{'teamTotals'}->{'pointsTotal'},
		'scoreAgainst' => $opponentScore,
		'gameJson' =>  $jsonFileName,
		'winLoss' => ($output{'teamTotals'}->{'pointsTotal'} > $opponentScore) ? 'W' : 'L'
	);
	push @games, \%gi;
	
	if($output{'teamTotals'}->{'pointsTotal'} > $opponentScore)
	{
		$wins++;
	}
	else
	{
		$losses++;
	}
	
	print "  Done.\n";
}

my $indexFile = catfile($outDir, 'gameindex.json');
my %gameIndex = (
	'wins' => $wins,
	'losses' => $losses,
	'games' => \@games
);
open INDEX_FILE, '>', $indexFile;
print INDEX_FILE $json->encode(\%gameIndex);
close INDEX_FILE;

print "Outputting team game stats...\n";
{
	my $outFile = catfile($outDir, "teamgames.json");
	open TGAME_FILE, '>', $outFile;
	my %data = (
		'name' => "Team",
		'stats' => \@teamGames);
	print TGAME_FILE $json->encode(\%data);
	close TGAME_FILE;
	
	OutputCumulativeStats(catfile($outDir, 'teamcumulative.json'),
		"Team", \@teamGames);
}
print "  Done.\n";

print "Outputting player game stats...\n";
foreach my $n (keys %playerGames)
{
	print "  $n...\n";
	my $outFile = catfile($outDir, catfile('players/games', "$n.json"));
	open PGAME_FILE, '>', $outFile;
	my %data = (
		'name' => $playerNames{$n},
		'stats' => $playerGames{$n});
	print PGAME_FILE $json->encode(\%data);
	close PGAME_FILE;
	
	OutputCumulativeStats(
		catfile($outDir, catfile('players/cumulative', "$n.json")),
		$playerNames{$n},
		$playerGames{$n});
	OutputGameTypeAverageStats(
		catfile($outDir, catfile('players/average', "$n.json")),
		$playerNames{$n},
		$playerGames{$n});
}
print "  Done.\n";

print "Outputting game flows...\n";
foreach my $gn (sort keys %flowFiles)
{
	next if($flowFiles{$gn} =~ /Blank.ods/i);
	
	print "  Processing '$flowFiles{$gn}'...\n";
	my $spreadsheet = ReadData ($flowFiles{$gn});
	my $sheet = $spreadsheet->[1];
	my $opponent = $sheet->{cell}[1][1];
	my %headers;
	
	for(my $j = 1; $j <= $sheet->{maxcol}; $j++)
	{
		my $c = $sheet->{cell}[$j][2];
		$headers{$c} = $j if($c);
	}
	#print "$_ = $headers{$_}\n" foreach (sort keys %headers);
	
	my @scoresFor;
	my @scoresAgainst;
	my $lastQ = 0;
	for(my $i = 3; $i <= $sheet->{maxrow}; $i++)
	{
		#print "$i\n";
		my $q = $sheet->{cell}[$headers{'quarter'}][$i];
		next if(!$q);
		
		my $tr = sprintf('%d:%02d',
			$sheet->{cell}[$headers{'minutesRemaining'}][$i],
			$sheet->{cell}[$headers{'secondsRemaining'}][$i]);
		my $s = $sheet->{cell}[$headers{'score'}][$i];
		my $n = $sheet->{cell}[$headers{'name'}][$i];
		my $os = $sheet->{cell}[$headers{'opponentScore'}][$i];
		my $on = $sheet->{cell}[$headers{'opponentName'}][$i];
		my $gs = CalcGameSeconds($q, $tr);
		my %d = (
			'quarter' => $q,
			'timeRemaining' => $tr,
			'score' => ($s ? $s : $os),
			'name' => ($s ? $n : $on),
			'totalSeconds' => $gs
		);
		if($s)
		{
			push @scoresFor, \%d;
		}
		else
		{
			push @scoresAgainst, \%d;
		}
		
		$lastQ = $q;
	}
	
	my %f = (
		'quarter' => $lastQ,
		'timeRemaining' => '0:00',
		'score' => $scoresFor[$#scoresFor]->{'score'},
		'name' => undef,
		'totalSeconds' => CalcGameSeconds($lastQ, '0:00')
	);
	push @scoresFor, \%f;
	
	my %a = (
		'quarter' => $lastQ,
		'timeRemaining' => '0:00',
		'score' => $scoresAgainst[$#scoresAgainst]->{'score'},
		'name' => undef,
		'totalSeconds' => CalcGameSeconds($lastQ, '0:00')
	);
	push @scoresAgainst, \%a;
	
	my $outFile = catfile($outDir, GenFlowFileName($gn));
	my %flow = (
		'opponent' => $opponent,
		'scoresFor' => \@scoresFor,
		'scoresAgainst' => \@scoresAgainst
	);
	open FLOW_FILE, '>', $outFile;
	print FLOW_FILE $json->encode(\%flow);
	close FLOW_FILE;
}
print "  Done.\n";

my $playerFile = catfile($gamesDir, "Players.ods");
if(-e $playerFile)
{
	print "Outputting players...\n";
	my $spreadsheet = ReadData ($playerFile);
	my $sheet = $spreadsheet->[1];
	my %headers;
	my @players;
	
	for(my $i = 1; $i <= $sheet->{maxrow}; $i++)
	{
		if(1 == $i)
		{
			for(my $j = 1; $j <= $sheet->{maxcol}; $j++)
			{
				my $c = $sheet->{cell}[$j][1];
				$headers{$c} = $j if($c);
			}
			next;
		}
		
		my %p;
		foreach my $c (keys %headers)
		{
			$p{$c} = $sheet->{cell}[$headers{$c}][$i];
		}
		$p{'gamesUrl'} = 'players/games/' . lc($p{'lastName'}) . '.json';
		$p{'cumulativeUrl'} = 'players/cumulative/' . lc($p{'lastName'}) . '.json';
		$p{'averagesUrl'} = 'players/average/' . lc($p{'lastName'}) . '.json';
		push @players, \%p;
	}
	
	my $outFile = catfile($outDir, "players.json");
	open PLAYER_FILE, '>', $outFile;
	print PLAYER_FILE $json->encode(\@players);
	close PLAYER_FILE;
	print "  Done.\n";
}

sub GenFlowFileName
{
	my $gn = shift;
	if(exists $flowFiles{$gn})
	{
		return sprintf("games/flows/gameflow%02d.json", $gn);
	}
	return undef;
}

sub OutputCumulativeStats
{
	my $outFile = shift;
	my $name = shift;
	my $stats = shift;
	my @cumu;
	my %cur;
	
	my @copy = qw(name gameNumber opponent);
	my @sum = qw(made2Pt attempted2Pt made3Pt attempted3Pt madeFt attemptedFt offRebounds defRebounds steals assists fouls turnovers blocks reboundsTotal pointsTotal);

	
	foreach my $k (keys %{${$stats}[0]})
	{
		$cur{$k} = 0;
	}
	
	my $gameCnt = 1;
	foreach my $g (@{$stats})
	{
		foreach my $c (@copy)
		{
			$cur{$c} = $g->{$c};
		}
		foreach my $s (@sum)
		{
			#print "$g->{$s}\n";
			$cur{$s} = $cur{$s} + (($g->{$s}) ? $g->{$s} : 0);
		}
		CalcPercent(['made2Pt'], ['attempted2Pt'], 'percent2Pt', \%cur);
		CalcPercent(['made3Pt'], ['attempted3Pt'], 'percent3Pt', \%cur);
		CalcPercent(['made2Pt', 'made3Pt'], ['attempted2Pt', 'attempted3Pt'], 'percentTotal', \%cur);
		CalcPercent(['madeFt'], ['attemptedFt'], 'percentFt', \%cur);
		
		my %cpy = %cur;
		my %aves = CalcAverages($gameCnt, \%cpy);
		$cpy{'averages'} = \%aves;
		push @cumu, \%cpy;
		$gameCnt++;
	}
	
	open CUMU_FILE, '>', $outFile;
	my %d = (
		'name' => $name,
		'stats' => \@cumu);
	print CUMU_FILE $json->encode(\%d);
	close CUMU_FILE;
}

sub OutputGameTypeAverageStats
{
	my $outFile = shift;
	my $name = shift;
	my $stats = shift;
	my %cur;
	
	my @sum = qw(made2Pt attempted2Pt made3Pt attempted3Pt madeFt attemptedFt offRebounds defRebounds steals assists fouls turnovers blocks reboundsTotal pointsTotal);
	
	foreach my $g (@{$stats})
	{
		my $gt = $g->{'gameType'};
		if(not exists $cur{$gt})
		{
			foreach my $k (keys %{${$stats}[0]})
			{
				$cur{$gt}{$k} = 0;
			}
			$cur{$gt}{'gameCount'} = 0;
		}
		if(not exists $cur{'Season'})
		{
			foreach my $k (keys %{${$stats}[0]})
			{
				$cur{'Season'}{$k} = 0;
			}
			$cur{'Season'}{'gameCount'} = 0;
		}
	}
	
	foreach my $g (@{$stats})
	{
		my $gt = $g->{'gameType'};
		foreach my $s (@sum)
		{
			#print "$g->{$s}\n";
			$cur{$gt}{$s} = $cur{$gt}{$s} + (($g->{$s}) ? $g->{$s} : 0);
			$cur{'Season'}{$s} = $cur{'Season'}{$s} + (($g->{$s}) ? $g->{$s} : 0);
		}
		
		$cur{$gt}{'gameCount'} = $cur{$gt}{'gameCount'} + 1;
		$cur{'Season'}{'gameCount'} = $cur{'Season'}{'gameCount'} + 1;
	}
	
	foreach my $gt (keys %cur)
	{
		delete ${$cur{$gt}}{'gameType'};
		delete ${$cur{$gt}}{'name'};
		
		CalcPercent(['made2Pt'], ['attempted2Pt'], 'percent2Pt', \%{$cur{$gt}});
		CalcPercent(['made3Pt'], ['attempted3Pt'], 'percent3Pt', \%{$cur{$gt}});
		CalcPercent(['made2Pt', 'made3Pt'], ['attempted2Pt', 'attempted3Pt'], 'percentTotal', \%{$cur{$gt}});
		CalcPercent(['madeFt'], ['attemptedFt'], 'percentFt', \%{$cur{$gt}});
		
		my %aves = CalcAverages($cur{$gt}{'gameCount'}, \%{$cur{$gt}});
		${$cur{$gt}}{'averages'} = \%aves;
	}
	
	open AVE_FILE, '>', $outFile;
	my %d = (
		'name' => $name,
		'stats' => \%cur);
	print AVE_FILE $json->encode(\%d);
	close AVE_FILE;
}

sub CalcPercent
{
	my $num = shift;
	my $denom = shift;
	my $out = shift;
	my $stats = shift;
	my $n = 0;
	my $d = 0;
	
	$n += $stats->{$_} foreach (@{$num});
	$d += $stats->{$_} foreach (@{$denom});
	$stats->{$out} = sprintf('%.1f%%',
		($d > 0) ? 100.0 * ($n / $d) : 0);
}

sub CalcAverages
{
	my $gameCnt = shift;
	my $stats = shift;
	my %aves = (
		'games' => $gameCnt
	);
	my %aveStats = (
		'offRebounds' => 'aveOffRebounds',
		'defRebounds' => 'aveDefRebounds',
		'steals' => 'aveSteals',
		'assists' => 'aveAssists',
		'fouls' => 'aveFouls',
		'turnovers' => 'aveTurnovers',
		'blocks' => 'aveBlocks',
		'reboundsTotal' => 'aveRebounds',
		'pointsTotal' => 'avePoints'
	);
	
	foreach my $s (keys %aveStats)
	{
		#print "$s => $aveStats{$s}\n";
		#print "int(10000 * ($stats->{$s} / $gameCnt)) / 100.0 = ", int(10000 * ($stats->{$s} / $gameCnt)) / 100.0, "\n";
		$aves{$aveStats{$s}} = 1.0 * sprintf('%.1f', $stats->{$s} / $gameCnt);
	}
	#exit;
	return %aves;
}

sub CalcGameSeconds
{
	my $q = shift;
	my $tr = shift;
	my $s = 0;
	
	$s += $QUARTER_SECONDS{$_} foreach (1 .. ($q - 1));
	$tr =~ /(\d+):(\d+)/;
	$tr = (60 * $1) + $2;
	$s += $QUARTER_SECONDS{$q} - $tr;
	return $s;
}