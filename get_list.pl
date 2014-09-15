#!/usr/bin/env perl
use strict;
use warnings;
use Redis;
use Mojo::UserAgent;
use Mojo::IOLoop;
use Mojo::JSON;
use XML::Simple;
use Data::Dumper;
use constant DEBUG => 1;
use feature 'say';

#binmode(STDOUT,":utf8");

my $ua = Mojo::UserAgent->new;
$ua->max_connections(20);
$ua->proxy->http('http://192.168.1.197:3128', 'http://192.168.1.101:3128');
my $threads = 1;
my @pids;
my $headers = {
   'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
   'Accept-Language' => 'zh-CN,zh;q=0.8,en;q=0.6',
   'Cache-Control' => 'no-cache',
   'Host' => 'weixin.sogou.com',
   'Referer' => 'http://weixin.sogou.com/gzh',
   'Pragma' => 'no-cache'
};
$ua->transactor->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1944.0 Safari/537.36');
my $json = Mojo::JSON->new;
my $redis = Redis->new(
  server=>'127.0.0.1:6379',reconnect => 60,read_timeout => 0.5
);

my %exists_no;
my $pubtask = "publicno-task";
my $urltask = "url-task";
my $xml_url = 'http://weixin.sogou.com/gzhjs?cb=sogou.weixin.gzhcb';
foreach(1..$threads) {
   my $pid = fork;
   if($pid == 0) {
      #DEBUG && say "I am child process $_ my parent id is :",getppid();
      while(my $info = $redis->lpop($pubtask)) {
         $info = $json->decode($info);
         my $openid = $info->{-openid};
         $headers->{'Referer'} .= "&openid=$openid";
         my $api = "$xml_url&openid=$openid&t=".time * 1000;
         DEBUG && say $api;
         my $article_url = geturl($ua, $api, []);
         next unless scalar @$article_url > 0;
         $info->{-url} = $article_url;
         DEBUG && say Dumper $info;
         $redis->lpush($urltask, $json->encode($info));
      }
   }

}

foreach(@pids) {
    waitpid($_,0);
}

sub geturl {
   my ($ua, $url, $links) = @_;
   my $tx = $ua->get($url=>$headers=>)->res;
   my $body = $tx->body;
   $body =~ s/gbk/utf-8/g;
   $body = $1 if $body =~ m/sogou\.weixin\.gzhcb\((.*)\)/ms;
   eval {
       $body = $json->decode($body);
   };
   return $links unless (!$@) &&  $body;
   my $items = $body->{'items'};
   my $totalPages = int($body->{'totalPages'});
   foreach my $item(@$items) {
      $item =~ s/[^[:ascii:]]+//g;
      my $xml = XMLin($item);
      return $links if scalar @$links > 30;
      push @$links, $xml->{'item'}->{'display'}->{'url'};
   }
   foreach my $page(2..$totalPages) {
      my $p_url = "$url&page=$page&t=".time*1000;
      return $links if scalar @$links > 30;
      return geturl($ua, $p_url, $links);
   }
   return $links;
}
