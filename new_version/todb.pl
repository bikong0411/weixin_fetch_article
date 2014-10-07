#!/usr/bin/env perl
use feature 'say';
use Mojo::DOM;
use Data::Dumper;
use DBI;
use Redis;
use JSON::XS qw/encode_json decode_json/;
use Encode;
use feature 'say';
use constant DEBUG => 0;


my $user = "sky";
my $passwd = "keys\@zuchenhui";
my $task = 'url-task';
my $redis = Redis->new(
  server=>'127.1:8388',reconnect => 60,read_timeout => 0.5,password => 'pwd'
);
my $dsn ="dbi:mysql:weixin;hostname=127.1;port=8210";
my $mysql = DBI->connect($dsn,$user,$passwd,{PrintError => 0, RaiseError => 1}) or die "$DBI::errstr";
#test
while() {
	while(my $info = $redis->rpop($task)) {
			 $info = decode_json($info);
			 my $meta={};
			 $meta->{'wx_name'} = $info->{'-title'};
			 $meta->{'wx_no'} = $info->{'-weixin_no'};
			 $meta->{'wx_intro'} = $info->{'-intro'};
			 my $urls = $info->{'-url'};
			 $meta->{'class'} = $info->{'-class'};
			 foreach my $url(@$urls) {
				 my $cmd = qq#/usr/bin/curl -s '$url'#;
				 DEBUG && say $cmd;
				 my $res = qx[$cmd];
				 my $dom = Mojo::DOM->new($res);
				 my $article = analysis($dom);
				 $meta->{'url'} = $url;
				 save_to_db->($meta, $article);
				 sleep 15;
			 }
	}
}
sub analysis {
   my %hash ;
   my @images;
   my $dom = shift;
   $hash{-title} = $dom->find("title")->text;
   $hash{-user} = $dom->find("#post-user")->text;
   $hash{-posttime} = $dom->find("#post-date")->text;
   $hash{-content} = $dom->find("#js_content")->content;
   @images = $hash{-content} =~ /<img.*?src="([^\"]*)"[^>]*>/g;
   $hash{-images} = \@images;
   \%hash;
}

sub save_to_db {
  my ($meta, $article) = @_;
  my $article_time = $article->{'-posttime'};
  my $article_title = $article->{'-title'};
  my $article_images = $article->{'-images'};
  my $article_content = $article->{'-content'};
  my $article_user = $article->{'-user'};
  my $article_url = $meta->{'url'};
  my $wx_name = $meta->{'wx_name'};
  my $wx_no = $meta->{'wx_no'};
  my $wx_intro = $meta->{'wx_intro'};
  my $class = Encode::decode("utf8", $meta->{'class'});
  $article_title = Encode::decode("utf8", $article_title);
  $article_title = qq#\Q$article_title\E#;
  $article_images = encode_json($article_images);
  $wx_intro = qq#\Q$wx_intro\E#;
  
  $article_content = Encode::decode("utf8", $article_content);
  $article_content = qq#\Q$article_content\E#;
  if(not $mysql->ping()) {
     $mysql = DBI->connect($dsn,$user,$passwd,{PrintError => 0, RaiseError => 1}) or die "$DBI::errstr";
  } 
  $mysql->do("set names utf8");
#  $class = uri_escape $class;
  my $sql = "INSERT INTO `content` SET `wx_name` = '$wx_name', `wx_no` = '$wx_no', `wx_intro` = '$wx_intro', `wx_title`='$article_title',`wx_images`='$article_images',`type`='$class', `wx_article_url`='$article_url',`wx_content`='$article_content', `wx_posttime` = '$article_time'"; 
  return $mysql->do($sql);
}
