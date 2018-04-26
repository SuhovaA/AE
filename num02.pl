use 5.016;
use warnings;
use lib './lib';
use AE::Simple2;
#use AE::HTTP::Request;
use DDP;


my %arg;
$arg{'headers'} = {};
$arg{'body'} = '';
$arg{'cookie'} = {version => '1'};

#my $response = AE::HTTP::Request->new("get", 'http://www.google.ru', \%arg);

my $obj = AE::Simple2->new();
my %results = ();
my $response;
$response = $obj->http_request("get", 'http://www.google.ru', \%arg, \%results, sub { 
	$obj->end_loop();
	p $results{'status-line'};
	p $results{'headers'};
	p $results{'body'};
	#p $response->{'cookie'};
	p %arg;

});

$obj->run_loop();

