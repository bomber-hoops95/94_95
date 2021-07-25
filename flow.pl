use strict;

foreach my $q (1 .. 4)
{
	foreach my $m (reverse 0 .. 7)
	{
		for(my $s = 55; $s >= 0; $s -= 5)
		{
			printf "%d\t%d:%02d\n", $q, $m, $s;
		}
	}
	print "\n"
}