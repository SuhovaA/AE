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

our @hdrs  = (
	qw(Upgrade),
	qw(Accept Accept-Charset Accept-Encoding Accept-Language Accept-Ranges),
  qw(Allow Authorization Cache-Control Connection Content-Disposition),
  qw(Content-Encoding Content-Length Content-Range Content-Type Cookie DNT),
  qw(Date ETag Expect Expires Host If-Modified-Since Last-Modified Link),
  qw(Location Origin Proxy-Authenticate Proxy-Authorization Range),
  qw(WebSocket-Origin WebSocket-Location Sec-WebSocket-Origin Sec-Websocket-Location ),
  qw(Sec-WebSocket-Accept Sec-WebSocket-Extensions Sec-WebSocket-Key),
  qw(Sec-WebSocket-Protocol Sec-WebSocket-Version Server Set-Cookie Status),
  qw(TE Trailer Transfer-Encoding Upgrade User-Agent Vary WWW-Authenticate),
  qw(X-Requested-With),
);

sub tcp_connect {
	my ($host, $port) = @_;
	my $proto = getprotobyname("tcp");
	socket(my $sock, AF_INET, SOCK_STREAM, $proto) or die "Error: socket";
	#say $host, $port;
	my $addr = gethostbyname $host or die "Problems with host: $host";

	my $sa = sockaddr_in($port, $addr);
	my $flags = fcntl($sock, F_GETFL, 0) or die "Can't get flags for the socket: $!\n";
	$flags = fcntl($sock, F_SETFL, $flags | O_NONBLOCK) or die "Can't set flags for the socket: $!\n";

	connect($sock, $sa) or warn "error: $!";
	return $sock;
}

sub http_request() {

	my ($self, $method, $url, $r_arg, $r_results, $cb) = @_;
	
	die "There is no such method: $method" if $method !~ /options|get|head|post|put|patch|delete|trace|connect/i;
	$method = uc $method;

	my ($scheme, $authority, $path, $query, $fragment) = $url =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;
	my $port = $scheme eq "http" ? 80 : die "Only http scheme supported: \$scheme = $scheme";
	
	$authority =~ /^(?: .*\@ )? ([^\@:]+) (?: : (\d+) )?$/x  or die "unparsable URL: $authority";
	my $host = $1;
	$port = $2 if defined $2;

	$path .= "?$query" if length $query;
	$path =~ s%^/?%/%;
	
	my %hdr;
	if (my $hdr = $r_arg->{headers}) {
    	while (my ($k, $v) = each %$hdr) {
			$hdr{lc $k} = $v;
		}
	}
	$hdr{'content-length'} = length($r_arg->{body}) if ($r_arg->{body}); 

	for my $h (keys %hdr) { die "There is no such headers: \"$h\" " if  (!grep /$h/i, @hdrs); }	
	
	$hdr{cookie} = HTTP::Easy::Cookies->encode($r_arg->{cookie}, host => $host, path => $path);
	
	my $sock = tcp_connect($host, $port);
	my $request = "$method $path HTTP/1.1\015\012"
            . (join "", map "$_: $hdr{$_}\015\012", keys %hdr)
            . "\015\012"
            . $r_arg->{body}; 

	my $w;
	my $length = length($request);
	my $buf = $request;
	my $send_last;

	$w = $self->io($sock, "w", sub {
		$send_last = syswrite($sock, $buf);
		$buf = substr($buf, $send_last);
		if (length($buf) == 0) {
			$self->destroy($w);
			my $r;
			#my $flag = 1;
			my $response = "";
			$r = $self->io($sock, "r", sub {

				sysread($sock, my $buf, 1024);
				$response .= $buf;
				if ($buf =~/\015\12\015\012/) {

					$self->destroy($r);

					my $x = "\015\012";
					$response =~ /^([^$x]+)(($x[^$x]+)*)$x$x(.*)/s;
					my $status_line = $1;
					my $h = substr($2, 2);
					my $buf = $4;
					
					$r_results->{'status-line'} = $status_line;
					my $headers = HTTP::Easy::Headers->decode($h);
					$r_results->{headers} = $headers;
				
					my $cookie_jar = HTTP::Easy::Cookies->decode($headers->{'set-cookie'});
					$r_results->{cookie} = $cookie_jar;
					$r_arg->{cookie} = $cookie_jar;
					
					my $body;
					if (lc $method eq "head") {
						$r_results->{body} = '';
						$cb->();
					} elsif (defined $headers->{'content-length'}) {
						if ($headers->{'content-length'} > 0) {
							$body = $buf;
							if (length($body) < $headers->{'content-length'}) {
								my $p;
								$p = $self->io($sock, "r", sub {
									sysread($sock, my $buf, $headers->{'content-length'} - length($body) + 1);
									$body .= $buf;
									if (length($body) == $headers->{'content-length'}) {
										$self->destroy($p);
										$r_results->{body} = $body;
										$cb->();
									}
								});
							} else {
								$r_results->{body} = $body;
								$cb->();
							}
						} else {
							$r_results->{body} = "";
							$cb->();
						}
					} elsif (defined $headers->{'transfer-encoding'} && ($headers->{'transfer-encoding'} eq 'chunked')) {
						my $n;
						my $x = "\r\n";

						if ($buf =~ /^([^$x]+)$x/) {
							$n = hex($1);
							$buf = substr($buf, length($1) + 2);
						} else {
							sysread($sock, my $tmp, 15);
							$buf .= $tmp;
							$buf =~ /^([^$x]+)$x/;
							$n = hex($1);
							$buf = substr($buf, length($1) + 2);
						}
						
						my $p;
						$body = "";
						$p = $self->io($sock, "r", sub {
							if (!$n) {
								$self->destroy($p);
								$r_results->{body} = $body;
								$cb->();
							} else {
								if (length($buf) < $n) {
									sysread($sock, my $tmp, $n - length($buf) + 5);
									$buf .= $tmp;
								}
							
								$body .= substr($buf, 0, $n);
								$buf = substr($buf, $n + 2);
								if ($buf =~ /^([^$x]+)$x/) {
									$n = hex($1);
									$buf = substr($buf, length($1) + 2);
								} else {
									sysread($sock, my $tmp, 15);
									$buf .= $tmp;
									$buf =~ /^([^$x]+)$x/;
									$n = hex($1);
									$buf = substr($buf, length($1) + 2);
								}
							}
						});
					} else {
						my $s;
						$s = $self->io($sock, "r", sub {
							$body = $buf;
							my $read = sysread($sock, my $tmp, 10000);
							if ($read) {
								$body .= $buf;
							} else {
								$self->destroy($s);
								$r_results->{body} = $body;
								$cb->();
							}
						});
					}
				}
				
			});
		}
	});

	$self->io(\*STDIN, "r", sub {
		sysread(\*STDIN, my $buf, 1024);
		chomp($buf);
		if ($buf eq "exit") {
			#exit 0;
			$cb->();
		}
	});

}




1;
__END__
