package FeedrTest;

use strict;
use warnings;

use base 'TestBase';

use Test::More;
use Test::Fatal;
use Test::MockObject::Extends;

use Feedr;

sub build_feed : Test(2) {
    my $self = shift;

    my $feedr =
      $self->_build_feedr(
        [   {url => 'http://foo.com', data => <<'EOF'}], config => {title => 'Title', description => 'Description'});
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>My channel</title>
    <link>http://foo.com/</link>
    <description>Description</description>
    <pubDate>Tue, 10 Jun 2003 04:00:00 GMT</pubDate>
    <lastBuildDate>Tue, 10 Jun 2003 09:41:01 GMT</lastBuildDate>
    <item>
      <title>One</title>
      <link>http://foo.com/One</link>
      <description>Two</description>
      <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
      <guid>http://http://foo.com/One</guid>
    </item>
  </channel>
</rss>
EOF

    my $feed = $feedr->run;

    is($feed->title,       'Title');
    is($feed->description, 'Description');
}

sub grep_by_categories : Test(2) {
    my $self = shift;

    my $feedr =
      $self->_build_feedr(
        [   {url => 'http://foo.com', data => <<'EOF'}], config => {limits => {categories => ['foo', '!bar']}});
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>My channel</title>
    <link>http://foo.com/</link>
    <description>Description</description>
    <pubDate>Tue, 10 Jun 2003 04:00:00 GMT</pubDate>
    <lastBuildDate>Tue, 10 Jun 2003 09:41:01 GMT</lastBuildDate>
    <item>
      <title>One</title>
      <link>http://foo.com/One</link>
      <description>One</description>
      <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
      <guid>http://http://foo.com/One</guid>
      <category>foo</category>
    </item>
    <item>
      <title>Two</title>
      <link>http://foo.com/Two</link>
      <description>Two</description>
      <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
      <guid>http://http://foo.com/Two</guid>
      <category>bar</category>
    </item>
  </channel>
</rss>
EOF

    my $feed = $feedr->run;

    my @items = $feed->items;
    is(@items, 1);
}

sub grep_by_keywords : Test(2) {
    my $self = shift;

    my $feedr =
      $self->_build_feedr(
        [   {url => 'http://foo.com', data => <<'EOF'}], config => {limits => {keywords => ['foo', '!bar']}});
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>My channel</title>
    <link>http://foo.com/</link>
    <description>Description</description>
    <pubDate>Tue, 10 Jun 2003 04:00:00 GMT</pubDate>
    <lastBuildDate>Tue, 10 Jun 2003 09:41:01 GMT</lastBuildDate>
    <item>
      <title>One</title>
      <link>http://foo.com/One</link>
      <description>foo</description>
      <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
      <guid>http://http://foo.com/One</guid>
    </item>
    <item>
      <title>Two</title>
      <link>http://foo.com/Two</link>
      <description>bar</description>
      <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
      <guid>http://http://foo.com/Two</guid>
    </item>
  </channel>
</rss>
EOF

    my $feed = $feedr->run;

    my @items = $feed->items;
    is(@items, 1);
}

sub _build_feedr {
    my $self = shift;
    my ($feeds, %params) = @_;

    my $feedr = Feedr->new(%params);

    $feedr = Test::MockObject::Extends->new($feedr);

    $feedr->mock(_resolve_urls => sub { $_[1] });
    $feedr->mock(
        _fetch_feeds => sub {
            my $self = shift;
            my ($cb) = @_;

            for my $feed (@$feeds) {
                $cb->($feed->{url}, $feed->{data});
            }
        }
    );

    return $feedr;
}

1;
