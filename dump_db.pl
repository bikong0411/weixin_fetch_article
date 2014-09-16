#!/usr/bin/env perl
use strict;
use warnings;
use Mojo::UserAgent;
use Mojo::JSON;
use Data::Dumper;
use DBI;
use Redis;
use feature 'say';
use constant DEBUG => 1;

my $threads = 8;
my @pids;
my $user = "club";
my $passwd = "DsWz\@sohucluB";
my $ua = Mojo::UserAgent->new;
$ua->max_connections(20);
my $task = 'url-task';
my $headers = {
   'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
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
my $dsn ="dbi:mysql:weixin;hostname=192.168.103.97;port=8210";
my $mysql = DBI->connect($dsn,$user,$passwd,{PrintError => 0, RaiseError => 1}) or die "$DBI::errstr";

for(1..$threads) {
   my $pid = fork;
   if($pid == 0) {
      while(my $info = $redis->rpop($task)) {
         $info = $json->decode($info);
         my $wx_name = $info->{"-title"};
         my $wx_no = $info->{"-weixin_no"};
         my $wx_intro = $info->{"-wx_intro"};
         my $urls = $info->{"-url"};
         DEBUG && say Dumper $info;
         foreach my $url(@$urls) {
                 my $proxy = 'http://192.168.103.107:3128';
		 $ua->proxy->http($proxy);
                 DEBUG && say $url;
		 my $tx = $ua->get($url=>$headers=>);
		 my $article = analysis($tx);
		 DEBUG && say Dumper $article;
                 my $article_time = $article->{'-posttime'};
                 my $article_title = $article->{'-title'};
                 my $article_images = $article->{'-images'};
                 my $article_content = $article->{'-content'};
                 my $article_user = $article->{'-user'};
                 my $article_url = $url;
                 save_to_db($wx_name, $wx_no, $wx_intro, $article_time, $article_title, $article_images, $article_content, $article_user, $article_url);
                 sleep 1;
         }
         last;
      }
      DEBUG && say "I am child process $_ , parent pid is".getppid();
      exit;
   }
   push @pids, $pid;
}

foreach(@pids) {
   waitpid($_, 0);
}
say "GAME OVER!!!";

sub analysis {
   my %hash ;
   my @images;
   my $tx = shift;
   my $dom = $tx->res->dom;
   $hash{-title} = $dom->find("title")->text;
   $hash{-user} = $dom->find("#post-user")->text;
   $hash{-posttime} = $dom->find("#post-date")->text;
   $hash{-content} = $dom->find("#js_content")->content;
   @images = $hash{-content} =~ /<img.*?src="([^\"]*)"[^>]*>/g;
   $hash{-images} = \@images;
   say $hash{-title};
   \%hash;
}

sub save_to_db {
  my ($wx_name, $wx_no, $wx_intro, $article_time, $article_title, $article_images, $article_content, $article_user, $article_url) = @_;
  $article_title = "\Q$article_title\E";
  $article_images = $json->encode($article_images);
  $wx_intro = "\Q$wx_intro\E";
  $article_content = $json->encode($article_content);
  if(not $mysql->ping()) {
     $mysql = DBI->connect($dsn,$user,$passwd,{PrintError => 0, RaiseError => 1}) or die "$DBI::errstr";
  }
  $mysql->do("set names utf8");
  my $sql = "INSERT INTO `content` SET `wx_name` = '$wx_name', `wx_no` = '$wx_no', `wx_intro` = '$wx_intro', `wx_title`='$article_title',`wx_images`='$article_images', `wx_article_url`='$article_url',`wx_content`='$article_content', `wx_posttime` = '$article_time'";
  DEBUG && say $sql;
  return $mysql->do($sql);
}
