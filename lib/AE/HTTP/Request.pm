package AE::HTTP::Request;
 

use 5.016;
use warnings;
use lib './blib';
#use lib '/home/nastena/perl5/lib/perl5';

use Socket;
use Fcntl;
use AE::Simple;
use DDP;
use HTTP::Easy::Headers;
use HTTP::Easy::Cookies;

require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
);
our $VERSION = '0.01';


=head1 SYNOPSIS

	AE::HTTP::Request->new($host, $method, $uri, %arg)
	%arg = { headers = %headers,
			body = $body,
			}

=cut

sub tcp_connect {
	my ($host, $port) = @_;
	my $proto = getprotobyname("tcp");
	socket(my $sock, AF_INET, SOCK_STREAM, $proto) or warn "Error: socket";
	#say $host, $port;
	my $addr = gethostbyname $host;

	my $sa = sockaddr_in($port, $addr);
	my $flags = fcntl($sock, F_GETFL, 0) or die "Can't get flags for the socket: $!\n";
	$flags = fcntl($sock, F_SETFL, $flags | O_NONBLOCK) or die "Can't set flags for the socket: $!\n";

	connect($sock, $sa) or warn "error: $!";
	return $sock;
}

sub new ($$$$;$){

	my ($self, $host, $port, $method, $uri, $r_arg) = @_;
	#my %arg = %$r_arg;
	my $sock = tcp_connect($host, $port);

	$method = uc $method;
	

	my %hdr;
	if (my $hdr = $r_arg->{headers}) {
    	while (my ($k, $v) = each %$hdr) {
			$hdr{lc $k} = $v;
		}
	}

	my $request = "$method $uri HTTP/1.1\015\012"
            . (join "", map "$_: $hdr{$_}\015\012", keys %hdr)
            . "\015\012"
            . $r_arg->{body};
    
    #say "request: ", $request;

	$hdr{cookie} = HTTP::Easy::Cookies->encode($r_arg->{cookie}, host => $host, path => $uri);
	#say $hdr{cookie};

	

	my $obj = AE::Simple->new();
	my $w;
	my $length = length($request);
	my $buf = $request;
	my $send_last;

	my %results = ();

	$w = $obj->io($sock, "w", sub {
		$send_last = syswrite($sock, $buf);
		$buf = substr($buf, $send_last);
		if (length($buf) == 0) {
			$obj->destroy($w);
			my $r;
			my $flag = 1;
			my $response = "";
			$r = $obj->io($sock, "r", sub {

				sysread($sock, my $buf, 1024);
				$response .= $buf;
				#say $buf;

				if ($buf =~/\015\12\015\012/) {

					$obj->destroy($r);

					my $x = "\015\012";
					$response =~ /^([^$x]+)(($x[^$x]+)*)$x$x(.*)/s;
					my $status_line = $1;
					my $h = substr($2, 2);
					my $buf = $4;
					
					$results{'status-line'} = $status_line;
					my $headers = HTTP::Easy::Headers->decode($h);
					$results{headers} = $headers;
					#p $headers;
					#p $headers->{'set-cookie'};

					my $cookie_jar = HTTP::Easy::Cookies->decode($headers->{'set-cookie'});
					#for (keys %$cookie_jar) {
						#$arg{cookie}{$_} = $cookie_jar->{$_};
					#}
					$results{cookie} = $cookie_jar;
					$r_arg->{cookie} = $cookie_jar;#чтоб изменилось извне
					
					#my $buf = substr($response, $n2 + 2);

					
					my $body;
					if (defined $headers->{'content-length'}) {
						if ($headers->{'content-length'} > 0) {
							$body = $buf;
							if (length($body) < $headers->{'content-length'}) {
								my $p;
								$p = $obj->io($sock, "r", sub {
									sysread($sock, my $buf, $headers->{'content-length'} - length($body) + 1);
									$body .= $buf;
									#say $buf;
									if (length($body) == $headers->{'content-length'}) {
										$obj->destroy($p);
										$results{body} = $body;
										$obj->end_loop();
									}
								});
							} else {
								$results{body} = $body;
								$obj->end_loop();
							}
						} else {
							$results{body} = "";
							$obj->end_loop();
						}
					}
					my $n;
					if (defined $headers->{'transfer-encoding'} && ($headers->{'transfer-encoding'} eq 'chunked')) {
						my $x = "\r\n";
						$buf =~ /^([^$x]+)/;
						#say ">>>>", $buf;
						$n = hex($1);
						#say $n;
						$buf = substr($buf, length($1) + 2);
						my $p;
						
						$body = "";
						$p = $obj->io($sock, "r", sub {
							if ($n == 0) {
								$obj->destroy($p);
								$results{body} = $body;
								$obj->end_loop();
							} else {
								if (length($buf) < $n) {
									sysread($sock, my $tmp, $n - length($buf) + 5);
									$buf .= $tmp;
									#say ">>>>", $buf;
								}
								$body .= substr($buf, 0, $n);
								$buf = substr($buf, $n + 2);
								#say ">>>>>", $buf;
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
								#say $n;
							}
						});
					}

				}
				
			});
		}
	});

	$obj->io(\*STDIN, "r", sub {
		sysread(\*STDIN, my $buf, 1024);
		chomp($buf);
		if ($buf eq "exit") {
			exit 0;
		}
	});

	$obj->run_loop(1);
	return \%results;

}

1;
__END__
