package AE::HTTP_request;

use 5.016;
use warnings;
use lib './blib';
#use lib '/home/nastena/perl5/lib/perl5';

use Socket;
use Fcntl;
use AE::Simple;
use DDP;
use HTTP::Easy::Headers;

require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
);
our $VERSION = '0.01';

sub tcp_connect {
	my ($host, $port) = @_;
	my $proto = getprotobyname("tcp");
	socket(my $sock, AF_INET, SOCK_STREAM, $proto) or warn "Error: socket";
	say $host, $port;
	my $addr = gethostbyname $host;
	my $sa = sockaddr_in($port, $addr);

	my $flags = fcntl($sock, F_GETFL, 0) or die "Can't get flags for the socket: $!\n";
	$flags = fcntl($sock, F_SETFL, $flags | O_NONBLOCK) or die "Can't set flags for the socket: $!\n";

	connect($sock, $sa) or warn "error: $!";
	return $sock;
}

sub new ($$$$;@){

	my ($self, $host, $port, $method, $uri, %arg) = @_;
	my $sock = tcp_connect($host, $port);

	$method = uc $method;

	my %hdr;
	if (my $hdr = $arg{headers}) {
      while (my ($k, $v) = each %$hdr) {
         $hdr{lc $k} = $v;
      }
    }
	my $request = "$method $uri HTTP/1.0\015\012"
            . (join "", map "$_: $hdr{$_}\015\012", keys %hdr)
            . "\015\012"
            . $arg{body};
			
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

				if ($buf =~ /\n\n/) {

					$obj->destroy($r);
					my $n1 = index($response, "\n");
					my $n2 = index($response, "\n\n");
					my $status_line = substr($response, 0, $n1);
					$results{'status-line'} = $status_line;
					say $status_line;
					my $h = substr($response, $n1 + 1, $n2 - $n1 - 1);
					my $headers = HTTP::Easy::Headers->decode($h);
					$results{'headers'} = $headers;
					p $headers;
					if (defined $headers->{'content-length'} && $headers->{'content-length'} > 0) {

						my $body = substr($response, $n2 + 2);
						if (length($body) < $headers->{'content-length'}) {
							my $p;
							$p = $obj->io($sock, "r", sub {
								sysread($sock, my $buf, $headers->{'content-length'} - length($body) );
								$body .= $buf;
								if (length($body) == $headers->{'content-length'}) {
									$obj->destroy($p);
									$results{'body'} = $body;
									p $status_line;
									say "return";
									$obj->end_loop();
								}
							});
						} else {
							$results{'body'} = $body;
							$obj->end_loop();
						}
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
