#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use Mojo::UserAgent;
use Data::Dumper;
use Redis;
use URI::Escape qw/uri_escape/;
use Mojo::JSON;
use constant DEBUG => 1;
binmode(STDOUT,":utf8");
my $threads = 8;
my @pids;
my $ua = Mojo::UserAgent->new;
$ua->max_connections(20);
$ua->transactor->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1944.0 Safari/537.36');
my $headers = {
   'Host' => 'weixin.sogou.com',
   'Referer' => 'http://weixin.sogou.com/'
};
my $json = Mojo::JSON->new;
my $redis = Redis->new(
  server=>'127.0.0.1:6379',reconnect => 60,read_timeout => 0.5
);
my @keywords = qw/科技 科学/;
my $url = 'http://weixin.sogou.com/weixin?_asf=www.sogou.com&_ast=1410417561&w=01019900&p=40040100&ie=utf8&type=1&sut=54285&sst0=1410417561270&lkt=4%2C1410417558233%2C1410417558736';
my $now = time;
my %exists_no;
my $pubtask = "publicno-task";

foreach(1..$threads) {
   my $pid = fork;
   if($pid == 0) {
      #DEBUG && say "I am child process $_ my parent id is :",getppid();
      while(my $keyword = $redis->lpop("kw-task")) {
         my $tmp_url = "$url&query=$keyword";
         while($tmp_url) {
            my $tx = $ua->get($tmp_url => $headers);
            my $dom = $tx->res->dom;
            my $next_href = $dom->find("#sogou_next")->attr("href");
            $tmp_url = $next_href?"http://weixin.sogou.com/weixin$next_href" : undef;
            foreach my $div($dom->find("._item")->each) {
		       my $pub_info = {};
                       my $openid = $div->attr("href");
                       $openid = @{[split /=/,$openid]}[1];
		       my $time = $div->find(".hui")->script->text;
		       next if $time eq "";
		       $time = int(@{[split /'/,$time]}[1]);
		       next if $now - $time > 30 * 86400;
		       my $logo = $div->find(".img-box")->img->attr("src");
		       my $title = $div->find(".txt-box")->h3->text;
		       my $weixin_no = $div->find(".txt-box")->h4->span->text;
		       $weixin_no = @{[split /[^\w]/, $weixin_no]}[1];
		       my $intro = $div->find(".sp-txt")->text;
		       $pub_info = {-title => $title, -logo => $logo, -weixin_no => $weixin_no, -intro => $intro, -openid => $openid};

		       if ( not exists $exists_no{$weixin_no} ) {
		          $exists_no{$weixin_no} = 1;
                          $redis->lpush($pubtask, $json->encode($pub_info));
		       }
		   }
         }
      }
      exit;
   }
   push @pids,$pid;
}

#push keyword task queue
foreach(@keywords) {
   $redis->lpush("kw-task", uri_escape($_));
}

foreach(@pids) {
    waitpid($_,0);
}

#Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
