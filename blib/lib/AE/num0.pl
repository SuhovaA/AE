use 5.016;
use warnings;
use lib './lib';
use Socket;
use AnyEvent::Simple;

my ($remote, $port, $iaddr, $paddr, $proto);

$remote  = "127.0.0.1";
$port    = 8888;
$iaddr   = inet_aton($remote) or die "no host: $remote";
$paddr   = sockaddr_in($port, $iaddr);
$proto   = getprotobyname("tcp");

socket(SOCK, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
connect(SOCK, $paddr) or die "connect: $!";
autoflush SOCK, 1;

my $obj = AnyEvent::Simple->new();

my $r = $obj->io(\*STDIN, "r", sub {
	my $read = sysread(\*STDIN, my $buf, 1024);
    
    if ($read) {
        print SOCK $buf;
        if ($buf eq "exit\n") { 
        	exit 0;
        }
    }
});

$obj->timer(30, sub {
	$obj->destroy($r);
	say "Time is over!";
	exit 0;
});

$obj->run_loop(1);