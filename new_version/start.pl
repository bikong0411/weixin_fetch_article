#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use Mojo::UserAgent;
use Data::Dumper;
use Redis;
use URI::Escape qw/uri_escape uri_unescape/;
use JSON::XS qw/encode_json/;
use POSIX qw/strftime/;
use constant DEBUG => 1;
use utf8;

my $ua = Mojo::UserAgent->new;
$ua->max_connections(20);
$ua->transactor->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1944.0 Safari/537.36');
my $headers = {
   'Host' => 'weixin.sogou.com',
   'Referer' => 'http://weixin.sogou.com/'
};
my $redis = Redis->new(
  server=>'127.1:8388',reconnect => 60,read_timeout => 0.5,password=>'pwd'
);
my $url = 'http://weixin.sogou.com/weixin?_asf=www.sogou.com&_ast=1410417561&w=01019900&p=40040100&ie=utf8&type=1&sut=54285&sst0=1410417561270&lkt=4%2C1410417558233%2C1410417558736';
my $now = time;
my %exists_no;
my $index = 0;
my $pubtask = "pub";

while() {
	while(my $line = $redis->lpop("kw_$index")) {
	 my($class, $keyword) = split /#/, $line;
	 $keyword = uri_escape($keyword);
	 my $tmp_url = "$url&query=$keyword";
	 DEBUG && say $tmp_url;
	 my $i = 0;
	 while($tmp_url ne "nil") {
		my $retry = 1;
		my $tx;
		while( $retry <= 3) {
			$tx = $ua->get($tmp_url => $headers=>);
			if( $tx->res->code != 200) {
			   sleep 15;
			   $retry += 1;
			   redo;
			}
			last;
		}
		my $dom = $tx->res->dom;
		my $next_href = $dom->find("#sogou_next")->attr("href");
		$tmp_url = $next_href?"http://weixin.sogou.com/weixin$next_href" : "nil";
		foreach my $div($dom->find("._item")->each) {
		   my $pub_info = {};
		   my $openid = $div->attr("href");
		   $openid = @{[split /=/,$openid]}[1];
		   my $time = $div->find(".hui")->script->text;
		   next if $time eq "";
		   $time = int(@{[split /'/,$time]}[1]);
		   next if $now - $time > 30 * 86400;
		   goto NEXT if $i >= 100;
		   $i += 1;
		   my $logo = $div->find(".img-box")->img->attr("src");
		   my $title = $div->find(".txt-box")->h3->em->text;
		   my $weixin_no = $div->find(".txt-box")->h4->span->text;
		   $weixin_no = @{[split /[^\w]/, $weixin_no]}[1];
		   my $intro = $div->find(".sp-txt")->text;
		   $pub_info = {-title => "$title", -logo => "$logo", -weixin_no => "$weixin_no", -intro => "$intro", -openid => "$openid", -class => "$class"};
		   DEBUG && say Dumper $pub_info;
		   if ( not exists $exists_no{$weixin_no} ) {
				  $exists_no{$weixin_no} = 1;
				  $redis->lpush($pubtask, encode_json($pub_info));
		   }
		}
		sleep 15;
	 }
	 NEXT:
	 sleep 15;
	}
    sleep 10;
}
#Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
sub LOG {
   my ($level, $message) = @_;
   open my $log,">>fetch_weixin.log" or die "Can't open fetch_weixin.log: $!";
   my $time = strftime("%Y-%m-%d %H:%I:%S",localtime());
   print $log "[ $time ] - $level -  $message\n";
   close $log;
}
