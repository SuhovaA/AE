package AE::Simple2;

use 5.016000;
use strict;
use warnings;
use lib './blib';

use IO::Select;
use Socket;
use Fcntl;
use HTTP::Easy::Headers;
use HTTP::Easy::Cookies;
use DDP;

require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
);
our $VERSION = '0.01';

sub new {
	my $class = shift;

	vec(my $rin, 0, 1) = 0;
	vec(my $win, 0, 1) = 0;
	vec(my $ein, 0, 1) = 0;


	my %arr1 = ();
	my $arr_w = \%arr1;
	my %arr2 = ();
	my $arr_r = \%arr2;
	my %arr3 = ();
	my $arr_e = \%arr3;

	my $self = bless {
		rin => $rin,
		win => $win,
		ein => $ein,
		wait_r => my $wait_r,
		wait_w => my $wait_w,
		wait_e => my $wait_e,
		get_fh_r => $arr_r,
		get_fh_w => $arr_w,
		get_fh_e => $arr_e,
		deadlines => my $deadlines,
		end_loop => 0,
	}, $class;
	return $self;
}

sub io {
	my ($self, $fh, $sign, $cb) = @_;
	if ($sign eq "r") {
		vec($self->{rin}, fileno($fh), 1) = 1;
		${ $self->{wait_r} }{$fh} = $cb;
		${ $self->{get_fh_r} }{fileno($fh)} = $fh;
	} elsif ($sign eq "w") {
		vec($self->{win}, fileno($fh), 1) = 1;
		${ $self->{wait_w} }{$fh} = $cb;
		${ $self->{get_fh_w} }{fileno($fh)} = $fh;
	} elsif ($sign eq "e") {
		vec($self->{ein}, fileno($fh), 1) = 1;
		${ $self->{wait_e} }{$fh} = $cb;
		${ $self->{get_fh_e} }{fileno($fh)} = $fh;
	} else {
		die "Error: sign != (r, w, e)";
	}


	my @a = ($fh, $sign);
	return \@a;

}

sub destroy {
	my ($self, $ref) = @_;
	my ($fh, $sign) = @$ref;
	if ($sign eq "r") {
		vec($self->{rin}, fileno($fh), 1) = 0;
		delete ${ $self->{get_fh_r} }{fileno($fh)};
		delete ${ $self->{wait_r} }{$fh};
	} elsif ($sign eq "w") {
		vec($self->{win}, fileno($fh), 1) = 0;
		delete ${ $self->{get_fh_w} }{fileno($fh)};
		delete ${ $self->{wait_w} }{$fh};
	} elsif ($sign eq "e") {
		vec($self->{ein}, fileno($fh), 1) = 0;
		delete ${ $self->{get_fh_e} }{fileno($fh)};
		delete ${ $self->{wait_e} }{$fh};
	} else {
		die "Error: sign != (r, w, e)";
	};
}

sub ready_fds_r {
	my ($self, $vec) = @_;
	my %get_fh = %{ $self->{get_fh_r} };
	my @map = map { $get_fh{$_} } grep { vec($vec,$_,1) } 0..8*length($vec)-1;
	return @map;
}
sub ready_fds_w {
	my ($self, $vec) = @_;
	my %get_fh = %{ $self->{get_fh_w} };
	my @map = map { $get_fh{$_} } grep { vec($vec,$_,1) } 0..8*length($vec)-1;
	return @map;
}
sub ready_fds_e {
	my ($self, $vec) = @_;
	my %get_fh = %{ $self->{get_fh_e} };
	my @map = map { $get_fh{$_} } grep { vec($vec,$_,1) } 0..8*length($vec)-1;
	return @map;
}

sub end_loop {
	my $self = shift;
	$self->{end_loop} = 1;
	return 0;
}

sub timer {
	my ($self, $t, $cb) = @_;
	my $deadline = time + $t;
	my @deadlines;
	@deadlines = sort { $a->[0] <=> $b->[0] } @deadlines, [ $deadline, $cb ];
	@{ $self->{deadlines} } = @deadlines;
}

sub run_loop {
	my ($self, $timeout) = @_;

	my $rin;
	my $win;
	my $ein;

	while (1) {
		last if $self->{end_loop} == 1;

		$rin = $self->{rin};
		$win = $self->{win};
		$ein = $self->{ein};

		my $nfound = select($rin, $win, $ein, $timeout);
		print "read: ", unpack "B*", $rin;
		print " write: ", unpack "B*", $win;
		print " ein: ", unpack "B*", $rin;
		print "\n";

		if ($nfound) {
			#my %waiters = %{ $self->{wait} };
			#say "rin: ", ready_fds_r($self, $rin);
			for my $fh (ready_fds_r($self, $rin)) {
				#my $cb = $waiters{$fh};
				my $cb = ${ $self->{wait_r} }{$fh};
				$cb->();
			}
			#say "win: ", ready_fds_w($self, $win);
			for my $fh (ready_fds_w($self, $win)) {
				#my $cb = $waiters{$fh};

				#say %{ $self->{wait_w} };
				#say "fh:   ", $fh;
				my $cb = ${ $self->{wait_w} }{$fh};
				$cb->();
			}
		}
		if (defined $self->{deadlines}) {
			my @deadlines = @{ $self->{deadlines} };
			if (@deadlines) {
				my $now = time;
				my @exec;

			    while ((@deadlines) && ($now > $deadlines[0][0])) {
			        push @exec, shift(@deadlines);
			    }
		    	for my $dl (@exec) {
		        	$dl->[1]->();
		    	}
		    	$self->{deadlines} = \@deadlines;
			}
		}
		sleep(1);
	}
}


1;
__END__
