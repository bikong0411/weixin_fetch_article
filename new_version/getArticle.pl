#!/usr/bin/env perl
use strict;
use warnings;
use Redis;
use Mojo::UserAgent;
use JSON::XS qw/encode_json decode_json/;
use XML::Simple;
use Data::Dumper;
use constant DEBUG => 1;
use feature 'say';
use utf8;

my $ua = Mojo::UserAgent->new;
$ua->max_connections(20);
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
  server=>'127.1:8388',reconnect => 60,read_timeout => 0.5,password=>'pwd'
);
my $max_age = Redis->new(
  server=>'127.1:8388',reconnect => 60,read_timeout => 0.5,password=>'pwd'
);
$max_age->select(1);

my %exists_no;
my $pubtask = "pub";
my $urltask = "url-task";
my $xml_url = 'http://weixin.sogou.com/gzhjs?cb=sogou.weixin.gzhcb';
#DEBUG && say "I am child process $_ my parent id is :",getppid();
while() {
	while(my $info = $redis->lpop($pubtask)) {
		 $info = decode_json($info);
		 my $openid = $info->{-openid};
		 $headers->{'Referer'} .= "&openid=$openid";
		 my $api = "$xml_url&openid=$openid&t=".time * 1000;
		 DEBUG && say $api;
		 DEBUG && say $info->{-class};
		 my $article_url = geturl($max_age,$info->{-weixin_no},$ua, $api, []);
		 next unless scalar @$article_url > 0;
		 $info->{-url} = $article_url;
		 DEBUG && say Dumper $info;
		 $redis->lpush($urltask, encode_json($info));
	}
    sleep 10;
}

sub geturl {
   my ($r, $weixin_no, $ua, $url, $links) = @_;
   my $u = $r->get($weixin_no);
   if($u && $u eq $url) {
	   return $links;
   }
   my $i=1;
   my $tx;
   while($i<=3) {
       $tx = $ua->get($url=>$headers=>)->res;
       if($tx->code != 200) {
          sleep 10;
          $i+=1;
          redo;
       }
       last;
   }
   my $body = $tx->body;
   $body =~ s/gbk/utf-8/g;
   $body = $1 if $body =~ m/sogou\.weixin\.gzhcb\((.*)\)/ms;
   eval {
       $body = decode_json($body);
   };
   return $links unless (!$@) &&  $body;
   my $items = $body->{'items'};
   my $totalPages = int($body->{'totalPages'});
   foreach my $item(@$items) {
      $item =~ s/[^[:ascii:]]+//g;
      my $xml = XMLin($item);
      return $links if scalar @$links >= 30;
      $u =  $xml->{'item'}->{'display'}->{'url'};
      if(scalar @$links == 0) {
         $r->set($weixin_no, $u);
      }
      push @$links, $u;
   }
   foreach my $page(2..$totalPages) {
      my $p_url = "$url&page=$page&t=".time*1000;
      return $links if scalar @$links >= 30;
      sleep 10;
      return geturl($r,$weixin_no, $ua, $p_url, $links);
   }
   return $links;
}
