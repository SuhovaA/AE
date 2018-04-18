use 5.016;
use warnings;
use lib './lib';
use AE::Simple;
use AE::HTTP_request;
use DDP;

my $method = 'get';
my $uri = '/?gfe_rd=cr&dcr=0&ei=IDDXWqOtCs6F3APz6ZOoDg';
my %arg;
$arg{'headers'} = {Host => "www.google.ru"};
$arg{'body'} = "";
my $response = AE::HTTP_request->new("www.google.ru", $method, $uri, %arg);

p $response->{'status-line'};
p $response->{'headers'};
p $response->{'body'};
