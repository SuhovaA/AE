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

	$response = AE::HTTP::Request->new($method, $url, \%arg)
	%arg = { headers = \%headers,
		cookie = \%cookie,
		body = $body,
	}
	p $response->{'status-line'}; 
	p $response->{headers};
	p $response->{body};
	p $response->{cookie};
=cut

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

sub new ($$$){

	#my ($self, $host, $port, $method, $uri, $r_arg) = @_;
	
	my ($self, $method, $url, $r_arg) = @_;
	
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


	my $obj = AE::Simple2->new();
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
				say $response;	
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
				
					my $cookie_jar = HTTP::Easy::Cookies->decode($headers->{'set-cookie'});
					$results{cookie} = $cookie_jar;
					$r_arg->{cookie} = $cookie_jar;
					say $method;
					if (lc $method eq "head") {
						$results{body} = '';
						$obj->end_loop();
						exit 0;
					}
					my $body;
					if (defined $headers->{'content-length'}) {
						if ($headers->{'content-length'} > 0) {
							$body = $buf;
							if (length($body) < $headers->{'content-length'}) {
								my $p;
								$p = $obj->io($sock, "r", sub {
									sysread($sock, my $buf, $headers->{'content-length'} - length($body) + 1);
									$body .= $buf;
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
					} elsif (defined $headers->{'transfer-encoding'} && ($headers->{'transfer-encoding'} eq 'chunked')) {
						my $n;
						my $x = "\r\n";

						if ($buf =~ /^([^$x]+)$x/) {
							$n = hex($1);
							$buf = substr($buf, length($1) + 2);
						} else {
							say "read";	
							sysread($sock, my $tmp, 15);
							$buf .= $tmp;
							$buf =~ /^([^$x]+)$x/;
							$n = hex($1);
							$buf = substr($buf, length($1) + 2);
						}
						
						#$buf =~ /^([^$x]+)/;		
						#$n = hex($1);
						#$buf = substr($buf, length($1) + 2);
						my $p;
						
						$body = "";
						$p = $obj->io($sock, "r", sub {
							if (!$n) {
								$obj->destroy($p);
								$results{body} = $body;
								$obj->end_loop();
							} else {
								if (length($buf) < $n) {
									sysread($sock, my $tmp, $n - length($buf) + 5);
									$buf .= $tmp;
									say $tmp;
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
						$s = $obj->io($sock, "r", sub {
							$body = $buf;
							my $read = sysread($sock, my $tmp, 10000);
							if ($read) {
								$body .= $buf;
							} else {
								$obj->destroy($s);
								$results{body} = $body;
								$obj->end_loop();
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
