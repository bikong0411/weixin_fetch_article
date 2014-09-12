#!/usr/bin/env perl
use strict;
use warnings;
use Mojo::UserAgent;
use Mojo::JSON;
use Mojo::DOM;
use Data::Dumper;
use DBI;
use Redis;
use feature 'say';
use constant DEBUG => 1;

my $threads = 8;
my @pids;
my $user = "usr";
my $passwd = "DsWz\@wwww";
my $ua = Mojo::UserAgent->new;
$ua->max_connections(20);
#$ua->proxy->http('http://192.168.0.12:3128');
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
my $dsn ="dbi:mysql:test;hostname=127.0.0.1;port=8210";
my $mysql = DBI->connect($dsn,$user,$passwd,{PrintError => 0, RaiseError => 1}) or die "$DBI::errstr";
say $mysql;
for(1..$threads) {
   my $pid = fork;
   if($pid == 0) {
      DEBUG && say "I am child process $_ , parent pid is".getppid();
      exit;
   }
   push @pids, $pid;
}

foreach(@pids) {
   waitpid($_, 0);
}
say "GAME OVER!!!";
